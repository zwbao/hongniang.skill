#!/usr/bin/env bash
# 红娘 skill — 联系方式交换
# Usage: exchange.sh submit <match_id> <contact_info>
#        exchange.sh get <match_id>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/api.sh"

ACTION="${1:-}"
MATCH_ID="${2:-}"

if [[ -z "$ACTION" || -z "$MATCH_ID" ]]; then
  echo "Usage: exchange.sh <submit|get> <match_id> [contact_info]" >&2
  exit 1
fi

USER_ID=$(get_user_id)

case "$ACTION" in
  submit)
    CONTACT="${3:-}"
    if [[ -z "$CONTACT" ]]; then
      # 从本地配置读取联系方式
      CONTACT_TYPE=$(read_nested_config "contact" "type")
      CONTACT_VALUE=$(read_nested_config "contact" "value")
      if [[ -z "$CONTACT_VALUE" ]]; then
        echo "ERROR: No contact info provided and none found in config." >&2
        echo "Please update ~/.hongniang/config.yaml or pass contact as argument." >&2
        exit 1
      fi
      CONTACT="${CONTACT_TYPE}:${CONTACT_VALUE}"
    fi

    PAYLOAD=$(jq -n \
      --arg user_id "$USER_ID" \
      --arg contact "$CONTACT" \
      '{user_id: $user_id, contact: $contact}')

    api_request POST "/api/v1/hongniang/exchange/${MATCH_ID}" "$PAYLOAD"
    echo "Contact submitted. Waiting for the other party..."
    ;;
  get)
    RESULT=$(api_request GET "/api/v1/hongniang/exchange/${MATCH_ID}?user_id=${USER_ID}")
    CONTACT=$(echo "$RESULT" | jq -r '.contact // empty')
    if [[ -n "$CONTACT" ]]; then
      echo "Match contact info: ${CONTACT}"
    else
      echo "Waiting for the other party to submit their contact info."
    fi
    ;;
  *)
    echo "Usage: exchange.sh <submit|get> <match_id> [contact_info]" >&2
    exit 1
    ;;
esac
