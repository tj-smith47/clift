#!/usr/bin/env bash
# DIYCLI Router
# Called by every command's default task.
# Usage: router.sh <TASK_NAME> [CLI_ARGS...]
#
# Flow:
#   1. Run deps.sh to validate dependencies
#   2. If first arg is "help", delegate to task <namespace>:help
#   3. Otherwise, resolve and execute the command's .sh script

set -euo pipefail

TASK_NAME="${1:-}"
shift || true

if [[ -z "$TASK_NAME" ]]; then
  echo "error: router.sh called without a task name" >&2
  exit 1
fi

if [[ -z "${FRAMEWORK_DIR:-}" ]]; then
  echo "error: FRAMEWORK_DIR is not set" >&2
  exit 1
fi

# Step 1: Dependency check
source "${FRAMEWORK_DIR}/lib/check/deps.sh"

# Step 2: Check for help redirect
if [[ "${1:-}" == "help" ]]; then
  # Extract namespace from task name (e.g., "greet:default" → "greet")
  local_namespace="${TASK_NAME%%:*}"
  task "${local_namespace}:help"
  exit 0
fi

# Step 3: Resolve and execute command script
# TASK_NAME is like "greet:default" or "greet:loud"
# Namespace is the top-level command name
local_namespace="${TASK_NAME%%:*}"

# Find the command script
if [[ -z "${CLI_DIR:-}" ]]; then
  echo "error: CLI_DIR is not set" >&2
  exit 1
fi

script_path="${CLI_DIR}/cmds/${local_namespace}/${local_namespace}.sh"

if [[ ! -f "$script_path" ]]; then
  echo "error: command script not found: $script_path" >&2
  exit 1
fi

# Forward args to command script
exec bash "$script_path" "$@"
