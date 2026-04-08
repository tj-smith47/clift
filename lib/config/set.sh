#!/usr/bin/env bash
# Set a configuration value in .env
# Usage: set.sh <CLI_DIR> <FRAMEWORK_DIR> <KEY> <VALUE>

set -euo pipefail

CLI_DIR="${1:-}"
FRAMEWORK_DIR="${2:-}"
KEY="${3:-}"
VALUE="${4:-}"

if [[ -z "$CLI_DIR" || -z "$FRAMEWORK_DIR" || -z "$KEY" || -z "$VALUE" ]]; then
  echo "error: usage: config:set <KEY> <VALUE>" >&2
  exit 1
fi

source "${FRAMEWORK_DIR}/lib/log/log.sh"

ENV_FILE="${CLI_DIR}/.env"

if [[ ! "$KEY" =~ ^[A-Z_]+$ ]]; then
  echo "error: key must be uppercase letters and underscores only: '${KEY}'" >&2
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "error: .env not found at ${ENV_FILE}" >&2
  exit 1
fi

if grep -q "^${KEY}=" "$ENV_FILE"; then
  # Use a temp file to avoid sed delimiter issues with special chars in VALUE
  tmpfile=$(mktemp)
  while IFS= read -r line; do
    if [[ "$line" == "${KEY}="* ]]; then
      printf '%s=%s\n' "$KEY" "$VALUE"
    else
      printf '%s\n' "$line"
    fi
  done < "$ENV_FILE" > "$tmpfile"
  mv "$tmpfile" "$ENV_FILE"
else
  printf '%s=%s\n' "$KEY" "$VALUE" >> "$ENV_FILE"
fi

log_success "Set ${KEY}=${VALUE}"
