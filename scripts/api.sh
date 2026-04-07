#!/usr/bin/env bash
# 红娘 skill — 共用 API 封装
# 被其他脚本 source 使用，不直接运行

set -euo pipefail

HONGNIANG_CONFIG="${HOME}/.hongniang/config.yaml"

# 检查依赖
check_deps() {
  for cmd in curl jq; do
    if ! command -v "$cmd" &>/dev/null; then
      echo "ERROR: $cmd is required but not installed." >&2
      exit 1
    fi
  done
}

# 读取配置（简单 YAML 解析，只处理顶层 key: value）
read_config() {
  local key="$1"
  if [[ ! -f "$HONGNIANG_CONFIG" ]]; then
    echo "ERROR: Config not found at $HONGNIANG_CONFIG. Please register first." >&2
    exit 1
  fi
  grep "^${key}:" "$HONGNIANG_CONFIG" | sed "s/^${key}:[[:space:]]*//" | tr -d "'\""
}

# 读取嵌套配置（如 contact.type）
read_nested_config() {
  local section="$1"
  local key="$2"
  if [[ ! -f "$HONGNIANG_CONFIG" ]]; then
    echo "ERROR: Config not found at $HONGNIANG_CONFIG." >&2
    exit 1
  fi
  awk -v sec="$section" -v k="$key" '
    $0 ~ "^"sec":"{found=1; next}
    found && /^[^ ]/{found=0}
    found && $0 ~ "^  "k":"{sub("^  "k":[[:space:]]*", ""); print}
  ' "$HONGNIANG_CONFIG"
}

get_backend_url() {
  read_config "backend_url"
}

get_user_id() {
  read_config "user_id"
}

get_api_token() {
  read_config "api_token"
}

# 发送 API 请求
api_request() {
  local method="$1"
  local path="$2"
  local data="${3:-}"

  local url
  url="$(get_backend_url)${path}"
  local token
  token="$(get_api_token)"

  local curl_args=(
    -s -w "\n%{http_code}"
    -X "$method"
    -H "Content-Type: application/json"
    -H "Authorization: Bearer ${token}"
  )

  if [[ -n "$data" ]]; then
    curl_args+=(-d "$data")
  fi

  local response
  response=$(curl "${curl_args[@]}" "$url")

  local http_code
  http_code=$(echo "$response" | tail -1)
  local body
  body=$(echo "$response" | sed '$d')

  if [[ "$http_code" -ge 400 ]]; then
    echo "ERROR: API returned HTTP $http_code" >&2
    echo "$body" >&2
    exit 1
  fi

  echo "$body"
}

# 初始化（无 config 时用于注册）
api_register() {
  local backend_url="$1"
  local profile_json="$2"

  local response
  response=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "$profile_json" \
    "${backend_url}/api/v1/hongniang/profile")

  local http_code
  http_code=$(echo "$response" | tail -1)
  local body
  body=$(echo "$response" | sed '$d')

  if [[ "$http_code" -ge 400 ]]; then
    echo "ERROR: Registration failed with HTTP $http_code" >&2
    echo "$body" >&2
    exit 1
  fi

  echo "$body"
}

check_deps
