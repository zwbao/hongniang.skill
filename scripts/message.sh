#!/usr/bin/env bash
# 红娘 skill — 传话功能
# Usage: message.sh send <recommendation_id> <message>   — 给对方传话
#        message.sh inbox                                 — 查看收到的传话
#        message.sh read <message_id>                     — 标记已读

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/api.sh"

ACTION="${1:-}"
USER_ID=$(get_user_id)

case "$ACTION" in
  send)
    REC_ID="${2:-}"
    MSG="${3:-}"
    if [[ -z "$REC_ID" || -z "$MSG" ]]; then
      echo "Usage: message.sh send <recommendation_id> <message>" >&2
      exit 1
    fi
    PAYLOAD=$(jq -n \
      --arg user_id "$USER_ID" \
      --arg recommendation_id "$REC_ID" \
      --arg message "$MSG" \
      '{user_id: $user_id, recommendation_id: ($recommendation_id | tonumber), message: $message}')
    api_request POST "/api/v1/hongniang/messages" "$PAYLOAD"
    ;;
  inbox)
    api_request GET "/api/v1/hongniang/messages/${USER_ID}"
    ;;
  read)
    MSG_ID="${2:-}"
    if [[ -z "$MSG_ID" ]]; then
      echo "Usage: message.sh read <message_id>" >&2
      exit 1
    fi
    api_request POST "/api/v1/hongniang/messages/${MSG_ID}/read" "{\"user_id\":\"${USER_ID}\"}"
    ;;
  *)
    echo "Usage: message.sh <send|inbox|read> [args]" >&2
    exit 1
    ;;
esac
