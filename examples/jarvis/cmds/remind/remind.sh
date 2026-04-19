#!/usr/bin/env bash
set -euo pipefail

source "${FRAMEWORK_DIR}/lib/log/log.sh"

message="${CLIFT_POS_1:-}"
in_="${CLIFT_FLAGS[in]:-}"
at="${CLIFT_FLAGS[at]:-}"
via="${CLIFT_FLAGS[via]:-push}"

if [[ -z "$message" ]]; then
  clift_exit 2 'usage: jarvis remind "<message>" (--in DUR | --at HH:MM) [--via CHANNEL]'
fi

if [[ -z "$in_" && -z "$at" ]]; then
  clift_exit 2 "must provide --in <duration> or --at <HH:MM>"
fi

if [[ -n "$in_" ]]; then
  when="in ${in_}"
else
  when="at ${at}"
fi

log_success "reminder scheduled ${when} via ${via}"
printf '  message: %s\n' "$message"
