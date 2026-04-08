#!/usr/bin/env bash
# Opens CLI .env file in the user's editor.
# Usage: edit.sh <CLI_DIR>

set -euo pipefail

CLI_DIR="${1:-}"
if [[ -z "$CLI_DIR" ]]; then
  echo "error: CLI_DIR required" >&2
  exit 1
fi

"${EDITOR:-vi}" "${CLI_DIR}/.env"
