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

# Check for existing installation
if [[ -f "${TARGET}/.env" ]]; then
  log_warn "CLI already exists at ${TARGET}"
  log_info "Re-running setup will update .env and alias without overwriting cmds/ or Taskfile.yaml"
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
    "$ENV_FILE"
  log_info "Updated FRAMEWORK_DIR and CLI_DIR in existing .env"
fi

# Render Taskfile.yaml (only if not exists)
TASKFILE="${TARGET}/Taskfile.yaml"
if [[ ! -f "$TASKFILE" ]]; then
  sed \
    -e "s|%%CLI_NAME%%|${CLI_NAME}|g" \
    -e "s|%%CLI_VERSION%%|${CLI_VERSION}|g" \
    "${FRAMEWORK_DIR}/templates/cli/Taskfile.yaml.tmpl" > "$TASKFILE"
fi

# Configure shell alias
ALIAS_LINE="alias ${CLI_NAME}='FRAMEWORK_DIR=${FRAMEWORK_DIR} task --taskfile ${TARGET}/Taskfile.yaml'"

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
  log_info "Updated existing alias in ${RC_FILE}"
fi

log_success "Created ${CLI_NAME} at ${TARGET}"
log_success "Added alias to ${RC_FILE}"
echo ""
log_info "Restart your shell or run: source ${RC_FILE}"
echo ""
log_info "Then try:"
log_info "  ${CLI_NAME}              Show help"
log_info "  ${CLI_NAME} new:cmd      Create your first command"
