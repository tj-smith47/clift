#!/usr/bin/env bash
# Interactive log theme switcher.
# Usage: log-theme.sh <CLI_DIR> <FRAMEWORK_DIR>

set -euo pipefail

CLI_DIR="${1:-}"
FRAMEWORK_DIR="${2:-}"

if [[ -z "$CLI_DIR" || -z "$FRAMEWORK_DIR" ]]; then
  echo "error: log-theme.sh requires CLI_DIR and FRAMEWORK_DIR" >&2
  exit 1
fi

source "${FRAMEWORK_DIR}/lib/log/log.sh"

ENV_FILE="${CLI_DIR}/.env"

THEMES="icons,icons-color,brackets,brackets-color,minimal,minimal-color,custom"

NEW_THEME=$("${FRAMEWORK_DIR}/lib/prompt/prompt.sh" choose 'Select log theme' --var LOG_THEME --options "$THEMES")

# Update LOG_THEME in .env
if grep -q "^LOG_THEME=" "$ENV_FILE"; then
  sed -i "s|^LOG_THEME=.*|LOG_THEME=${NEW_THEME}|" "$ENV_FILE"
else
  echo "LOG_THEME=${NEW_THEME}" >> "$ENV_FILE"
fi

LOG_THEME="$NEW_THEME" log_success "Log theme set to: ${NEW_THEME}"
