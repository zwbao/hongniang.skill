#!/usr/bin/env bash
# 红娘 skill — 暂停/恢复匹配
# Usage: pause.sh on [reason]    — 暂停匹配
#        pause.sh off             — 恢复匹配
#        pause.sh status          — 查看当前状态

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/api.sh"

ACTION="${1:-}"
USER_ID=$(get_user_id)

case "$ACTION" in
  on)
    REASON="${2:-}"
    PAYLOAD=$(jq -n --arg reason "$REASON" '{status: "paused", reason: $reason}')
    api_request POST "/api/v1/hongniang/profile/${USER_ID}/pause" "$PAYLOAD"
    ;;
  off)
    api_request POST "/api/v1/hongniang/profile/${USER_ID}/resume" '{}'
    ;;
  status)
    api_request GET "/api/v1/hongniang/profile/${USER_ID}/pause"
    ;;
  *)
    echo "Usage: pause.sh <on|off|status> [reason]" >&2
    exit 1
    ;;
esac
