#!/usr/bin/env bash
set -euo pipefail

source "${FRAMEWORK_DIR}/lib/log/log.sh"

target="${CLIFT_FLAG_TARGET}"
force="${CLIFT_FLAG_FORCE:-}"
replicas="${CLIFT_FLAG_REPLICAS:-3}"
tag_count="${CLIFT_FLAG_TAG_COUNT:-0}"
profile="${CLIFT_FLAG_PROFILE:-default}"

log_info "Deploying to ${target} (profile=${profile}, replicas=${replicas})"

if (( tag_count == 0 )); then
  log_warn "No tags specified — deploying latest"
else
  for (( i=1; i<=tag_count; i++ )); do
    var="CLIFT_FLAG_TAG_${i}"
    log_info "  image: ${!var}"
  done
fi

if [[ "$force" != "true" ]] && [[ "$target" == "prod" ]]; then
  log_warn "Production deploy requires --force"
  exit 1
fi

# Simulate deployment
log_info "Rolling out to ${target}..."
log_success "Deployed ${tag_count} service(s) to ${target}"
