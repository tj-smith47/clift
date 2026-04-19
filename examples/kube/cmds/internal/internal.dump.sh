#!/usr/bin/env bash
set -euo pipefail

source "${FRAMEWORK_DIR}/lib/log/log.sh"

log_info "internal:dump — hidden but executable"
log_info "this command is absent from help listings and shell completion"
