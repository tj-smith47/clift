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

# Check for existing installation — prompt to reconfigure
if [[ -f "${TARGET}/.env" ]]; then
  log_warn "CLI already exists at ${TARGET}"
  read -rp "Reconfigure? [y/N] " response </dev/tty
  if [[ ! "$response" =~ ^[Yy] ]]; then
    log_info "Setup cancelled"
    exit 0
  fi
fi

# Create directory structure
mkdir -p "${TARGET}/cmds"

# Render .env
ENV_FILE="${TARGET}/.env"
if [[ ! -f "$ENV_FILE" ]] || [[ ! -d "${TARGET}/cmds" ]] || [[ -z "$(ls -A "${TARGET}/cmds" 2>/dev/null)" ]]; then
  sed \
    -e "s|%%FRAMEWORK_DIR%%|${FRAMEWORK_DIR}|g" \
    -e "s|%%CLI_DIR%%|${TARGET}|g" \
    -e "s|%%CLI_NAME%%|${CLI_NAME}|g" \
    -e "s|%%CLI_VERSION%%|${CLI_VERSION}|g" \
    -e "s|%%LOG_THEME%%|${LOG_THEME}|g" \
    "${FRAMEWORK_DIR}/templates/cli/.env.tmpl" > "$ENV_FILE"
else
  # Update specific values in existing .env
  sed -i \
    -e "s|^FRAMEWORK_DIR=.*|FRAMEWORK_DIR=${FRAMEWORK_DIR}|" \
    -e "s|^CLI_DIR=.*|CLI_DIR=${TARGET}|" \
    -e "s|^CLI_NAME=.*|CLI_NAME=${CLI_NAME}|" \
    -e "s|^CLI_VERSION=.*|CLI_VERSION=${CLI_VERSION}|" \
    -e "s|^LOG_THEME=.*|LOG_THEME=${LOG_THEME}|" \
    "$ENV_FILE"
  log_info "Updated configuration in existing .env"
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
log_success "${CLI_NAME} created at ${TARGET}"
echo ""
echo "Next steps:"
echo "  source ${RC_FILE}"
echo "  ${CLI_NAME}"
echo "  ${CLI_NAME} new:cmd"
