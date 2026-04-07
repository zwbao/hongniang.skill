#!/usr/bin/env bash
# 红娘 skill — 回应推荐
# Usage: respond.sh <agree|reject> <recommendation_id> [reason]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/api.sh"

ACTION="${1:-}"
REC_ID="${2:-}"
REASON="${3:-}"

if [[ -z "$ACTION" || -z "$REC_ID" ]]; then
  echo "Usage: respond.sh <agree|reject> <recommendation_id> [reason]" >&2
  exit 1
fi

if [[ "$ACTION" != "accept" && "$ACTION" != "reject" ]]; then
  echo "ERROR: Action must be 'accept' or 'reject'" >&2
  exit 1
fi

USER_ID=$(get_user_id)

PAYLOAD=$(jq -n \
  --arg user_id "$USER_ID" \
  --arg recommendation_id "$REC_ID" \
  --arg response "$ACTION" \
  --arg reason "$REASON" \
  '{user_id: $user_id, recommendation_id: ($recommendation_id | tonumber), response: $response, reason: $reason}')

RESULT=$(api_request POST "/api/v1/hongniang/response" "$PAYLOAD")

echo "Response recorded: ${ACTION}"
echo "$RESULT" | jq .
