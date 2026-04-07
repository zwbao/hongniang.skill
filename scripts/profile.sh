#!/usr/bin/env bash
# 红娘 skill — 档案管理（带本地 cache，解决 PATCH 浅合并问题）
# Usage: profile.sh get
#        profile.sh update '<json_string>'
#        profile.sh delete
#
# update 会先读取本地 cache，深度合并新字段后发送全量 PATCH。
# 这样即使后端 PATCH 是浅合并，也不会丢失已有字段。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/api.sh"

PROFILE_CACHE="${HOME}/.hongniang/profile-cache.json"

ACTION="${1:-}"
USER_ID=$(get_user_id)

# 确保 cache 存在（首次从服务器拉取）
ensure_cache() {
  if [[ ! -f "$PROFILE_CACHE" ]]; then
    local remote
    remote=$(api_request GET "/api/v1/hongniang/profile/${USER_ID}")
    echo "$remote" | jq '{summary: .summary, preferences: .preferences}' > "$PROFILE_CACHE"
  fi
}

case "$ACTION" in
  get)
    RES=$(api_request GET "/api/v1/hongniang/profile/${USER_ID}")
    # 同时更新本地 cache
    echo "$RES" | jq '{summary: .summary, preferences: .preferences}' > "$PROFILE_CACHE" 2>/dev/null
    echo "$RES"
    ;;
  update)
    NEW_JSON="${2:-}"
    if [[ -z "$NEW_JSON" ]]; then
      echo "Usage: profile.sh update '<json_string>'" >&2
      exit 1
    fi
    if [[ -f "$NEW_JSON" ]]; then
      NEW_JSON=$(cat "$NEW_JSON")
    fi

    # 验证 JSON
    if ! echo "$NEW_JSON" | jq empty 2>/dev/null; then
      echo "ERROR: Invalid JSON" >&2
      exit 1
    fi

    # 读取本地 cache，深度合并
    ensure_cache
    MERGED=$(jq -s '.[0] * .[1]' "$PROFILE_CACHE" <(echo "$NEW_JSON"))

    # 发送全量更新
    api_request PATCH "/api/v1/hongniang/profile/${USER_ID}" "$MERGED"

    # 更新本地 cache
    echo "$MERGED" > "$PROFILE_CACHE"

    echo "Profile updated."
    ;;
  delete)
    api_request DELETE "/api/v1/hongniang/profile/${USER_ID}"
    rm -f "$HONGNIANG_CONFIG" "$PROFILE_CACHE"
    echo "Profile deleted. Config removed."
    ;;
  *)
    echo "Usage: profile.sh <get|update|delete> [json_string]" >&2
    exit 1
    ;;
esac
