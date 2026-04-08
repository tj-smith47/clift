#!/usr/bin/env bash
# DIYCLI Setup — bootstraps a new CLI in a target directory.
# Usage: setup.sh <TARGET_DIR> <FRAMEWORK_DIR> <CLI_NAME> <CLI_VERSION> <LOG_THEME>

set -euo pipefail

TARGET="${1:-}"
FRAMEWORK_DIR="${2:-}"
CLI_NAME="${3:-}"
CLI_VERSION="${4:-0.1.0}"
LOG_THEME="${5:-icons-color}"

if [[ -z "$TARGET" || -z "$FRAMEWORK_DIR" ]]; then
  echo "error: setup.sh requires TARGET_DIR and FRAMEWORK_DIR" >&2
  exit 1
fi

source "${FRAMEWORK_DIR}/lib/log/log.sh"

# Strip trailing Taskfile.yaml if full path was passed
if [[ "$TARGET" == *.yaml ]] || [[ "$TARGET" == *.yml ]]; then
  TARGET="$(dirname "$TARGET")"
fi

# Resolve to absolute path
TARGET="$(cd "$(dirname "$TARGET")" 2>/dev/null && pwd)/$(basename "$TARGET")" || TARGET="$(realpath -m "$TARGET")"

# Default CLI_NAME to directory basename
if [[ -z "$CLI_NAME" ]]; then
  CLI_NAME="$(basename "$TARGET")"
fi

# Check for existing installation — offer per-field reconfigure
RECONFIGURE=false
if [[ -f "${TARGET}/.env" ]]; then
  log_warn "CLI already exists at ${TARGET}"
  read -rp "Reconfigure? [y/N] " response </dev/tty
  if [[ ! "$response" =~ ^[Yy] ]]; then
    log_info "Setup cancelled"
    exit 0
  fi
  RECONFIGURE=true

  # Read current values from existing .env as defaults
  _read_env_val() {
    grep "^${1}=" "${TARGET}/.env" 2>/dev/null | head -1 | cut -d= -f2-
  }

  _current_name="$(_read_env_val CLI_NAME)"
  _current_version="$(_read_env_val CLI_VERSION)"
  _current_theme="$(_read_env_val LOG_THEME)"

  # Re-prompt with current values as defaults
  THEMES="icons,icons-color,brackets,brackets-color,minimal,minimal-color,custom"
  CLI_NAME=$("${FRAMEWORK_DIR}/lib/prompt/prompt.sh" input 'CLI name' --var _RECONFIG_NAME --default "${_current_name:-$CLI_NAME}")
  CLI_VERSION=$("${FRAMEWORK_DIR}/lib/prompt/prompt.sh" input 'Version' --var _RECONFIG_VERSION --default "${_current_version:-$CLI_VERSION}")
  LOG_THEME=$("${FRAMEWORK_DIR}/lib/prompt/prompt.sh" choose 'Log theme' --var _RECONFIG_THEME --options "$THEMES" --default "${_current_theme:-$LOG_THEME}")
fi

# Create directory structure
mkdir -p "${TARGET}/cmds"

# Render .env
ENV_FILE="${TARGET}/.env"
if [[ "$RECONFIGURE" == "true" ]] || [[ ! -f "$ENV_FILE" ]]; then
  # Fresh render (new install or reconfigure)
  sed \
    -e "s|%%FRAMEWORK_DIR%%|${FRAMEWORK_DIR}|g" \
    -e "s|%%CLI_DIR%%|${TARGET}|g" \
    -e "s|%%CLI_NAME%%|${CLI_NAME}|g" \
    -e "s|%%CLI_VERSION%%|${CLI_VERSION}|g" \
    -e "s|%%LOG_THEME%%|${LOG_THEME}|g" \
    "${FRAMEWORK_DIR}/templates/cli/.env.tmpl" > "$ENV_FILE"
else
  # First install but .env somehow exists without reconfigure — update paths only
  sed -i \
    -e "s|^FRAMEWORK_DIR=.*|FRAMEWORK_DIR=${FRAMEWORK_DIR}|" \
    -e "s|^CLI_DIR=.*|CLI_DIR=${TARGET}|" \
    "$ENV_FILE"
fi

# Render .task-cli.yaml (only if not exists)
METADATA="${TARGET}/.task-cli.yaml"
if [[ ! -f "$METADATA" ]]; then
  sed \
    -e "s|%%CLI_NAME%%|${CLI_NAME}|g" \
    -e "s|%%CLI_VERSION%%|${CLI_VERSION}|g" \
    "${FRAMEWORK_DIR}/templates/cli/.task-cli.yaml.tmpl" > "$METADATA"
fi

# Render Taskfile.yaml (only if not exists)
TASKFILE="${TARGET}/Taskfile.yaml"
if [[ ! -f "$TASKFILE" ]]; then
  sed \
    -e "s|%%CLI_NAME%%|${CLI_NAME}|g" \
    -e "s|%%CLI_VERSION%%|${CLI_VERSION}|g" \
    "${FRAMEWORK_DIR}/templates/cli/Taskfile.yaml.tmpl" > "$TASKFILE"
fi

# Configure shell alias (with proper quoting for paths with spaces)
ALIAS_LINE="alias ${CLI_NAME}='FRAMEWORK_DIR=\"${FRAMEWORK_DIR}\" task --taskfile \"${TARGET}/Taskfile.yaml\"'"

# Detect shell config file
SHELL_NAME="$(basename "${SHELL:-/bin/bash}")"
case "$SHELL_NAME" in
  zsh)  RC_FILE="$HOME/.zshrc" ;;
  bash) RC_FILE="$HOME/.bashrc" ;;
  *)    RC_FILE="$HOME/.${SHELL_NAME}rc" ;;
esac

# Add alias if not already present
if ! grep -qF "alias ${CLI_NAME}=" "$RC_FILE" 2>/dev/null; then
  echo "" >> "$RC_FILE"
  echo "# DIYCLI: ${CLI_NAME}" >> "$RC_FILE"
  echo "$ALIAS_LINE" >> "$RC_FILE"
else
  # Update existing alias
  sed -i "s|^alias ${CLI_NAME}=.*|${ALIAS_LINE}|" "$RC_FILE"
fi

echo ""
if [[ "$RECONFIGURE" == "true" ]]; then
  log_success "${CLI_NAME} reconfigured at ${TARGET}"
else
  log_success "${CLI_NAME} created at ${TARGET}"
  echo ""
  echo "Next steps:"
  echo "  source ${RC_FILE}"
  echo "  ${CLI_NAME}"
  echo "  ${CLI_NAME} new:cmd"
fi
