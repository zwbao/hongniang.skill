#!/usr/bin/env bash
# 红娘 skill — 注册新用户
# Usage: register.sh '<json_string>' [backend_url]
#    or: echo '<json>' | register.sh - [backend_url]
#
# Examples:
#   register.sh '{"summary":{"basic":{"name":"张三","gender":"male","age":28,"city":"杭州"}}}'
#   register.sh '{"summary":{...}}' http://43.163.116.103:8010

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/api.sh"

INPUT="${1:-}"
BACKEND_URL="${2:-http://43.163.116.103:8010}"

if [[ -z "$INPUT" ]]; then
  echo "Usage: register.sh '<json_string>' [backend_url]" >&2
  echo "   or: echo '<json>' | register.sh - [backend_url]" >&2
  exit 1
fi

if [[ -f "$HONGNIANG_CONFIG" ]]; then
  echo "ERROR: Already registered. Config exists at $HONGNIANG_CONFIG" >&2
  echo "Use profile.sh to update your profile." >&2
  exit 1
fi

# 读取 JSON：从参数、stdin 或文件
if [[ "$INPUT" == "-" ]]; then
  PROFILE_JSON=$(cat)
elif [[ -f "$INPUT" ]]; then
  PROFILE_JSON=$(cat "$INPUT")
else
  PROFILE_JSON="$INPUT"
fi

# 验证是合法 JSON
if ! echo "$PROFILE_JSON" | jq empty 2>/dev/null; then
  echo "ERROR: Invalid JSON" >&2
  exit 1
fi

# 注册
echo "Registering with backend at ${BACKEND_URL}..."
RESPONSE=$(api_register "$BACKEND_URL" "$PROFILE_JSON")

USER_ID=$(echo "$RESPONSE" | jq -r '.user_id')
API_TOKEN=$(echo "$RESPONSE" | jq -r '.api_token')

if [[ -z "$USER_ID" || "$USER_ID" == "null" ]]; then
  echo "ERROR: Invalid response from server" >&2
  echo "$RESPONSE" >&2
  exit 1
fi

# 保存配置
mkdir -p "${HOME}/.hongniang"
cat > "$HONGNIANG_CONFIG" <<EOF
user_id: ${USER_ID}
api_token: ${API_TOKEN}
backend_url: ${BACKEND_URL}
contact:
  type: wechat
  value: ''
EOF

# 保存本地 profile cache（用于后续增量更新）
echo "$PROFILE_JSON" | jq '.' > "${HOME}/.hongniang/profile-cache.json"

echo "Registration successful!"
echo "User ID: ${USER_ID}"
echo "Config saved to: ${HONGNIANG_CONFIG}"
echo ""
echo "IMPORTANT: Please update your contact info in ${HONGNIANG_CONFIG}"
