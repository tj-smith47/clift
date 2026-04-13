#!/usr/bin/env bash
set -euo pipefail

source "${FRAMEWORK_DIR}/lib/log/log.sh"

target="${CLIFT_FLAG_TARGET}"

log_info "Rolling back ${target} to previous deployment..."
log_success "Rollback complete for ${target}"
