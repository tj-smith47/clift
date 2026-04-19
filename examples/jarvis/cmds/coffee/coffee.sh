#!/usr/bin/env bash
set -euo pipefail

source "${FRAMEWORK_DIR}/lib/log/log.sh"

size="${CLIFT_FLAGS[size]:-medium}"
milk="${CLIFT_FLAGS[milk]:-}"

if [[ "$milk" == "true" ]]; then
  beverage="${size} coffee with milk"
else
  beverage="${size} coffee"
fi

if command -v gum &>/dev/null; then
  gum spin --spinner meter --title "Brewing your ${beverage}…" -- sleep 3
else
  log_info "Brewing your ${beverage}…"
  sleep 3
fi

log_success "☕  One ${beverage}, ready."
