#!/usr/bin/env bash
# Displays current CLI configuration from .env

set -euo pipefail

CLI_DIR="${1:-}"
if [[ -z "$CLI_DIR" ]]; then
  echo "error: CLI_DIR required" >&2
  exit 1
fi

ENV_FILE="${CLI_DIR}/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "error: .env not found at ${ENV_FILE}" >&2
  exit 1
fi

echo "Configuration (${ENV_FILE}):"
echo ""
# Print non-comment, non-empty lines formatted
while IFS='=' read -r key value; do
  [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
  printf "  %-20s %s\n" "$key" "$value"
done < "$ENV_FILE"
