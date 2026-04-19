#!/usr/bin/env bash
set -euo pipefail

source "${FRAMEWORK_DIR}/lib/log/log.sh"

duration="${CLIFT_POS_1:-}"
topic="${CLIFT_FLAGS[on]:-}"
silent="${CLIFT_FLAGS[silent]:-}"

if [[ -z "$duration" ]]; then
  clift_exit 2 "usage: jarvis focus <duration> [--on TOPIC]"
fi

if [[ ! "$duration" =~ ^[0-9]+[smhd]$ ]]; then
  clift_exit 2 "duration must match ^[0-9]+[smhd]\$ (e.g. 25m, 10s, 1h)"
fi

# Convert to seconds for `sleep`.
_unit="${duration: -1}"
_value="${duration%?}"
case "$_unit" in
  s) seconds="$_value" ;;
  m) seconds=$(( _value * 60 )) ;;
  h) seconds=$(( _value * 3600 )) ;;
  d) seconds=$(( _value * 86400 )) ;;
esac

title="Focus: ${topic:-unspecified} (${duration})"
if command -v gum &>/dev/null; then
  gum spin --spinner points --title "$title" -- sleep "$seconds"
else
  log_info "$title"
  sleep "$seconds"
fi

if [[ "$silent" != "true" ]]; then
  log_success "✓ ${duration} focus session on ${topic:-'—'} complete."
else
  log_success "✓ complete."
fi
