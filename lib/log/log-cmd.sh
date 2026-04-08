#!/usr/bin/env bash
# Wrapper script for log functions, called by log Taskfile.
# Usage: log-cmd.sh <level> <message>

set -euo pipefail

LEVEL="${1:-}"
shift || true
MSG="$*"

if [[ -z "$LEVEL" || -z "$MSG" ]]; then
  echo "error: log-cmd.sh requires level and message" >&2
  exit 1
fi

source "${FRAMEWORK_DIR}/lib/log/log.sh"

case "$LEVEL" in
  info)    log_info "$MSG" ;;
  warn)    log_warn "$MSG" ;;
  error)   log_error "$MSG" ;;
  success) log_success "$MSG" ;;
  *) echo "error: unknown log level: $LEVEL" >&2; exit 1 ;;
esac
