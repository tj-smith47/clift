#!/usr/bin/env bash
# DIYCLI Router
# Called by every command's default task.
# Usage: router.sh <TASK_NAME>
# Reads CLI_ARGS from environment (set by command Taskfile template).
#
# Flow:
#   1. Run deps.sh to validate dependencies
#   2. Parse CLI_ARGS via eval set -- for proper word splitting
#   3. Scan for global flags (--no-color, --verbose, --quiet, --help, --version)
#   4. Source log.sh (with correct env vars from global flags)
#   5. If first arg is "help", delegate to task <namespace>:help
#   6. Otherwise, resolve and execute the command's .sh script

set -euo pipefail

TASK_NAME="${1:-}"

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

# Step 2: Parse CLI_ARGS with proper word splitting
if [[ -n "${CLI_ARGS:-}" ]]; then
  eval set -- ${CLI_ARGS}
else
  set --
fi

# Step 3: Scan for global flags
args=()
for arg in "$@"; do
  case "$arg" in
    --no-color)   export NO_COLOR=1 ;;
    --verbose|-v) export VERBOSE=true ;;
    --quiet|-q)   export QUIET=true ;;
    --help|-h)
      local_namespace="${TASK_NAME%%:*}"
      source "${FRAMEWORK_DIR}/lib/log/log.sh"
      task "${local_namespace}:help"
      exit 0
      ;;
    --version|-V)
      echo "${CLI_NAME:-unknown} version ${CLI_VERSION:-0.0.0}"
      exit 0
      ;;
    *) args+=("$arg") ;;
  esac
done
set -- "${args[@]+"${args[@]}"}"

# Step 4: Source log.sh (now with correct NO_COLOR/VERBOSE/QUIET)
source "${FRAMEWORK_DIR}/lib/log/log.sh"

# Step 5: Check for help redirect (bare "help" word)
if [[ "${1:-}" == "help" ]]; then
  local_namespace="${TASK_NAME%%:*}"
  task "${local_namespace}:help"
  exit 0
fi

# Step 6: Resolve and execute command script
local_namespace="${TASK_NAME%%:*}"

if [[ -z "${CLI_DIR:-}" ]]; then
  die "CLI_DIR is not set" "$EXIT_ERROR"
fi

script_path="${CLI_DIR}/cmds/${local_namespace}/${local_namespace}.sh"

if [[ ! -f "$script_path" ]]; then
  log_error "Unknown command: ${local_namespace}"
  if [[ -d "${CLI_DIR}/cmds" ]]; then
    prefix="${local_namespace:0:3}"
    for cmd_dir in "${CLI_DIR}/cmds"/*/; do
      cmd="$(basename "$cmd_dir")"
      if [[ "${cmd,,}" == *"${prefix,,}"* ]]; then
        log_suggest "Did you mean: $cmd"
      fi
    done
  fi
  exit "$EXIT_NOT_FOUND"
fi

# Forward args to command script
exec bash "$script_path" "$@"
