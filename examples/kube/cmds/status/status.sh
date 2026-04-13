#!/usr/bin/env bash
set -euo pipefail

source "${FRAMEWORK_DIR}/lib/log/log.sh"

target="${CLIFT_FLAG_TARGET}"
wide="${CLIFT_FLAG_WIDE:-}"

log_info "Status for ${target}:"
echo ""
printf "  %-12s %-10s %-8s" "SERVICE" "STATUS" "REPLICAS"
if [[ "$wide" == "true" ]]; then
  printf "  %-20s" "IMAGE"
fi
echo ""
printf "  %-12s %-10s %-8s" "api" "running" "3/3"
if [[ "$wide" == "true" ]]; then
  printf "  %-20s" "api:v1.2.0"
fi
echo ""
printf "  %-12s %-10s %-8s" "web" "running" "3/3"
if [[ "$wide" == "true" ]]; then
  printf "  %-20s" "web:v1.3.1"
fi
echo ""
printf "  %-12s %-10s %-8s" "worker" "degraded" "2/3"
if [[ "$wide" == "true" ]]; then
  printf "  %-20s" "worker:v1.1.0"
fi
echo ""
