#!/usr/bin/env bash
# command_pre override: fires before the command body runs.
set -euo pipefail

source "${FRAMEWORK_DIR}/lib/log/log.sh"

log_info "▶ pre-hook: starting deploy to ${CLIFT_FLAG_TARGET:-?} (profile=${CLIFT_FLAG_PROFILE:-default})"
