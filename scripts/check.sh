#!/usr/bin/env bash
# 红娘 skill — 查看推荐和匹配状态
# Usage: check.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/api.sh"

USER_ID=$(get_user_id)
api_request GET "/api/v1/hongniang/recommendations/${USER_ID}"
