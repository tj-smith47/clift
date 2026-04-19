#!/usr/bin/env bash
set -euo pipefail

source "${FRAMEWORK_DIR}/lib/log/log.sh"

id="${CLIFT_POS_1:-}"

if [[ -z "$id" ]]; then
  clift_exit 2 "usage: jarvis task done <id>"
fi

log_success "task #${id} marked done  🎉"
