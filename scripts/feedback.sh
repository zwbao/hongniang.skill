#!/usr/bin/env bash
# 红娘 skill — 约会后反馈
# Usage: feedback.sh submit <recommendation_id> '<json>'
#        feedback.sh list
#
# JSON 格式:
#   {"outcome":"chatting|met|dating|ended","rating":1-5,"comment":"..."}

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/api.sh"

ACTION="${1:-}"
USER_ID=$(get_user_id)

case "$ACTION" in
  submit)
    REC_ID="${2:-}"
    DATA="${3:-}"
    if [[ -z "$REC_ID" || -z "$DATA" ]]; then
      echo "Usage: feedback.sh submit <recommendation_id> '<json>'" >&2
      exit 1
    fi
    if ! echo "$DATA" | jq empty 2>/dev/null; then
      echo "ERROR: Invalid JSON" >&2
      exit 1
    fi
    PAYLOAD=$(echo "$DATA" | jq --arg uid "$USER_ID" --arg rid "$REC_ID" \
      '. + {user_id: $uid, recommendation_id: ($rid | tonumber)}')
    api_request POST "/api/v1/hongniang/feedback" "$PAYLOAD"
    ;;
  list)
    api_request GET "/api/v1/hongniang/feedback/${USER_ID}"
    ;;
  *)
    echo "Usage: feedback.sh <submit|list> [args]" >&2
    exit 1
    ;;
esac
