#!/usr/bin/env bash
# 红娘 skill — 回传筛选结果给后端
# Usage: filter.sh <recommendation_id> <action> [rank] [reason]
#   action: shown | suppressed
#   rank: 展示排序（1=最看好，null=没展示）
#   reason: 红娘的筛选理由

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/api.sh"

REC_ID="${1:-}"
ACTION="${2:-}"
RANK="${3:-}"
REASON="${4:-}"

if [[ -z "$REC_ID" || -z "$ACTION" ]]; then
  echo "Usage: filter.sh <recommendation_id> <shown|suppressed> [rank] [reason]" >&2
  exit 1
fi

if [[ "$ACTION" != "shown" && "$ACTION" != "suppressed" ]]; then
  echo "ERROR: Action must be 'shown' or 'suppressed'" >&2
  exit 1
fi

USER_ID=$(get_user_id)

PAYLOAD=$(jq -n \
  --arg user_id "$USER_ID" \
  --arg action "$ACTION" \
  --arg rank "$RANK" \
  --arg reason "$REASON" \
  '{user_id: $user_id, action: $action, rank: (if $rank == "" then null else ($rank | tonumber) end), reason: (if $reason == "" then null else $reason end)}')

api_request POST "/api/v1/hongniang/recommendations/${REC_ID}/filter" "$PAYLOAD"
