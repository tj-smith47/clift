#!/usr/bin/env bash
# Get a configuration value from .env
# Usage: get.sh <CLI_DIR> <KEY>

set -euo pipefail

CLI_DIR="${1:-}"
KEY="${2:-}"

if [[ -z "$CLI_DIR" || -z "$KEY" ]]; then
  echo "error: usage: config:get <KEY>" >&2
  exit 1
fi

ENV_FILE="${CLI_DIR}/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "error: .env not found at ${ENV_FILE}" >&2
  exit 1
fi

while IFS='=' read -r k v; do
  [[ -z "$k" || "$k" =~ ^[[:space:]]*# ]] && continue
  if [[ "$k" == "$KEY" ]]; then
    echo "$v"
    exit 0
  fi
done < "$ENV_FILE"

echo "error: key '${KEY}' not found" >&2
exit 1
