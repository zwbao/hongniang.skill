# 红娘 — 技术架构报告

## 系统概览

红娘是一个两层架构的 AI 婚恋匹配系统。用户端是一个遵循 [Agent Skills](https://agentskills.io) 标准的本地 Skill，后端是基于 [OpenClaw](https://github.com/openclaw/openclaw) 改造的匹配引擎。两层通过 REST API 通信。

```
用户 A 的机器                           用户 B 的机器
┌─────────────────┐                    ┌─────────────────┐
│  红娘 Skill (A)  │                    │  红娘 Skill (B)  │
│  私人红娘 A      │                    │  私人红娘 B      │
│  本地对话+筛选   │                    │  本地对话+筛选   │
└────────┬────────┘                    └────────┬────────┘
         │ REST API                             │ REST API
         ▼                                      ▼
┌──────────────────────────────────────────────────────────┐
│                 匹配引擎 (OpenClaw fork)                   │
│                                                          │
│  PostgreSQL    三层漏斗匹配    自进化系统    传话消息队列    │
│  (档案+状态)   (SQL→向量→LLM)  (每日复盘)   (异步中转)     │
└──────────────────────────────────────────────────────────┘
```

## 用户端：私人红娘

每个用户安装的 Skill 都是一个**独立的私人红娘**。她不只是调 API 的客户端——她有自己的判断力。

### 职责分工

| 用户端负责 | 后端负责 |
|-----------|---------|
| 对话式信息收集（从聊天中提取结构化档案） | 档案存储 |
| 推荐二次筛选（后端推 20 个，红娘可能只展示 3 个） | 全量匹配计算 |
| 传话措辞包装（不直接转发用户原话） | 消息中转存储 |
| 婚恋认知引导（帮用户理清自己要什么） | 匹配分+理由生成 |
| 约会后跟进（主动问进展，收集反馈） | 反馈数据聚合 |
| 暂停/恢复判断（识别用户意图） | 状态管理 |

### 为什么要两层

后端只有结构化档案（年龄、城市、性格标签），但用户端红娘在对话中积累了大量**非结构化信息**：

- 用户嘴上说"学历无所谓"，但每次聊到高学历的人语气明显不同
- 用户回避谈异地话题——档案里没写 dealbreaker，但红娘知道
- 用户前后矛盾——先说不在乎收入，后来又问对方收入多少

这些信息只有本地红娘知道，后端无法获取。所以后端做粗筛，用户端做细筛。

### 筛选反馈闭环

本地红娘的筛选判断会回传给后端：

```
后端推荐 → 本地红娘筛选 → 回传 filter 反馈 (shown/suppressed + 理由) → 后端学习
```

后端匹配引擎下次跑的时候会参考这些反馈——如果某类推荐被本地红娘频繁压住，说明匹配逻辑在那个维度上不准。

### 本地状态

```
~/.hongniang/
├── config.yaml           # user_id, api_token, backend_url, 联系方式
├── profile-cache.json    # 档案本地缓存（解决 PATCH 浅合并问题）
└── conversations/        # 对话记录（只在本地）
```

## 后端：匹配引擎

基于 OpenClaw 改造。OpenClaw 提供了 gateway、cron 引擎、多通道适配器等基础设施，红娘在上面加了匹配逻辑、传话系统和自进化引擎。

### 三层漏斗匹配

用户量增长后，全量两两比较不可行（N 个用户 = N*(N-1)/2 对）。采用三层漏斗逐层缩小候选范围：

**第一层：SQL 预筛（毫秒级）**

```sql
-- 硬性条件过滤：性别互斥、年龄区间交集、城市匹配、排除已推荐
SELECT a.id, b.id FROM profiles a CROSS JOIN profiles b
WHERE a.id < b.id
  AND gender 互斥
  AND 年龄在对方偏好范围内
  AND 城市有交集
  AND 未被推荐过
```

200 用户 → 约 2000 候选对。

**第二层：向量粗排（秒级）**

使用阿里通义千问 text-embedding-v4 模型，将每个用户的档案转成 1024 维向量：

```
档案文本 → "性别: 男。年龄: 28岁。城市: 杭州。职业: 软件工程师。
            爱好: 跑步、做饭、看电影。性格: 理性、安静、有耐心..."
         → [0.023, -0.154, 0.089, ...] (1024维)
```

计算候选对的余弦相似度，每人保留 top-K（当前 K=10）。2000 对 → 约 500 对。

Embedding 有缓存机制——只对档案有变化的用户重新计算（通过 text hash 判断）。

**第三层：LLM 精判（分钟级）**

对通过前两层的候选对，调用 LLM（Claude）做深度评估：

```
输入：两份完整档案 + 进化上下文（历史反馈、失败原因、阈值调整）
输出：{
  "score": 85,
  "should_recommend": true,
  "reason_for_a": "对方在杭州有稳定事业，游戏和美食是共同兴趣...",
  "reason_for_b": "对方外向开朗，与你的陪伴型社交风格契合...",
  "challenge": "两人事业心都很强，需注意工作与相处时间的平衡"
}
```

评估维度：互补性(40%)、价值观兼容(30%)、生活方式(20%)、基本条件(10%)。

### 自进化系统

匹配引擎不是静态的——它每天复盘、自我调整。

**数据来源（四层反馈）：**

| 层级 | 数据 | 来源 | 含义 |
|------|------|------|------|
| 红娘筛选 | shown/suppressed + 理由 | 本地 Skill | 后端觉得合适但本地红娘不认可 |
| 用户决策 | accept/reject + 原因 | 用户操作 | 用户的显性偏好 |
| 约会反馈 | chatting/met/dating/ended + 评分 | 用户回访 | 匹配的真实结果 |
| 进化分析 | insights + 阈值调整 | LLM 复盘 | 系统自我认知 |

**进化流程：**

```
每日 01:00 → 复盘最近 30 天数据
  → 分析成功因素（哪些维度预测了好结果）
  → 分析失败因素（哪些推荐被拒绝/结束了）
  → 生成 insights（如"异地匹配接受率低，加强地理距离过滤"）
  → 调整阈值和权重
  → 生成进化上下文，注入下一次匹配的 LLM prompt

每日 02:00 → 执行匹配（使用最新进化参数）
```

当前进化状态示例：
```json
{
  "version": 3,
  "scoreThreshold": 60,
  "insights": [
    "高分推荐（88-92）具备同城、价值观一致、性格互补等全部核心要素",
    "75分以下推荐普遍存在异地或生活方式差异问题",
    "建议加强地理距离过滤，加强生活方式匹配权重"
  ]
}
```

### 传话系统

```
用户 A 对红娘说："帮我问问她周末干嘛"
  ↓
A 的红娘包装："有位跟你匹配度挺高的先生想了解一下，你周末一般喜欢做什么？"
  ↓
POST /messages → 存入数据库 → 关联 recommendation_id
  ↓
用户 B 下次打开 Skill → 红娘检查 inbox → 发现新消息
  ↓
B 的红娘转述："对了，之前推荐给你的那位问你，周末一般喜欢做什么？"
  ↓
B 回复 → B 的红娘包装后传回 → A 下次来时收到
```

消息不暴露发送方 UUID，只有 recommendation_id 供红娘关联上下文。

### 双向同意状态机

```
recommended → A accept → waiting_for_b
recommended → B accept → waiting_for_a
waiting_for_x → X accept → matched (可交换联系方式)
任一方 reject → rejected
```

联系方式交换有安全校验——只有 `matched` 状态才能提交和获取。

## 数据模型

```
profiles            — 用户档案（UUID, summary JSONB, preferences JSONB, status）
profile_embeddings  — 向量缓存（user_id, embedding FLOAT8[], text_hash）
recommendations     — 匹配推荐（user_a, user_b, score, reasons, status）
exchanges           — 联系方式交换（match_id, user_id, contact）
filter_feedback     — 红娘筛选反馈（recommendation_id, action, reason）
messages            — 传话消息（from_user, to_user, content, read_at）
date_feedback       — 约会后反馈（recommendation_id, outcome, rating, comment）
```

## API

基础地址：`{BACKEND_URL}/api/v1/hongniang`

| 接口 | 方法 | 功能 | 认证 |
|------|------|------|------|
| `/profile` | POST | 注册 | 无 |
| `/profile/:id` | GET | 获取档案 | Bearer token |
| `/profile/:id` | PATCH | 更新档案 | Bearer token |
| `/profile/:id` | DELETE | 注销 | Bearer token |
| `/profile/:id/pause` | POST/GET | 暂停匹配 | Bearer token |
| `/profile/:id/resume` | POST | 恢复匹配 | Bearer token |
| `/recommendations/:id` | GET | 获取推荐（含对方脱敏画像） | Bearer token |
| `/response` | POST | 接受/拒绝推荐 | Bearer token |
| `/recommendations/:id/filter` | POST | 红娘筛选反馈 | 无 |
| `/exchange/:match_id` | POST | 提交联系方式 | Bearer token |
| `/exchange/:match_id` | GET | 获取对方联系方式 | Bearer token |
| `/messages` | POST | 发送传话 | Bearer token |
| `/messages/:user_id` | GET | 查看收件箱 | Bearer token |
| `/messages/:id/read` | POST | 标记已读 | Bearer token |
| `/feedback` | POST | 提交约会后反馈 | Bearer token |
| `/feedback/:user_id` | GET | 查看反馈记录 | Bearer token |
| `/match/run` | POST | 手动触发匹配 | 无 |
| `/match/status` | GET | 匹配运行状态 | 无 |
| `/evolve` | POST | 触发自进化 | 无 |
| `/evolve/status` | GET | 进化状态 | 无 |
| `/evolve/context` | GET | 进化上下文 | 无 |

## 技术栈

| 组件 | 技术 |
|------|------|
| 用户端 | Agent Skills 标准（SKILL.md + Bash 脚本） |
| 后端 | TypeScript / Node.js（OpenClaw fork） |
| 数据库 | PostgreSQL 16 |
| LLM（匹配） | MiniMax M2.7（通过 OpenClaw 配置） |
| LLM（用户对话） | 用户本地 Agent 工具自带的 LLM |
| Embedding | 阿里通义千问 text-embedding-v4 |
| 部署 | Docker（PostgreSQL）+ Node.js 直接运行 |

## 数据安全

| 数据类型 | 存储位置 | 说明 |
|----------|---------|------|
| 对话原文 | 用户本地 | 永不上传到后端 |
| 联系方式 | 用户本地 `~/.hongniang/config.yaml` | 双方同意后才通过 API 交换 |
| 结构化档案 | 后端 PostgreSQL | 年龄/城市/性格标签等，无姓名 |
| 匹配记录 | 后端 PostgreSQL | 包含分数、理由、状态 |
| 推荐展示 | API 返回 | 脱敏：无姓名、无联系方式、无 UUID |
