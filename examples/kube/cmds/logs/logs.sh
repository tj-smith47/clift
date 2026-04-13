#!/usr/bin/env bash
set -euo pipefail

source "${FRAMEWORK_DIR}/lib/log/log.sh"

service="${CLIFT_FLAG_SERVICE}"
follow="${CLIFT_FLAG_FOLLOW:-}"
lines="${CLIFT_FLAG_LINES:-50}"

log_info "Showing last ${lines} lines for ${service}"
echo ""

# Simulated log output
for (( i=1; i<=5; i++ )); do
  echo "2024-01-15T10:00:0${i}Z [${service}] request handled in ${RANDOM}ms"
done

if [[ "$follow" == "true" ]]; then
  log_info "Streaming... (Ctrl+C to stop)"
fi
