#!/usr/bin/env bash
# clift Router
# Called by every command's default task.
# Usage: router.sh <TASK_NAME>
#
# Flow:
#   1. Validate required env vars
#   2. Dependency check
#   3. Reconstruct argv: CLIFT_ARG_* (standard mode) or CLI_ARGS (task mode)
#   4. Early legacy check: if no root Taskfile.yaml, skip cache/parser
#   5. Ensure precompiled cache is fresh
#   6. Load merged flag table for this task
#   7. Legacy opt-out: if "legacy: true", exec script with positional argv
#   8. Otherwise: clift_parse_args → export CLIFT_FLAG_* / CLIFT_POS_*
#   9. Intercept --help, --version
#  10. Emit legacy-compat VERBOSE / QUIET / NO_COLOR env vars
#  11. Resolve script path and exec

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

if [[ -z "${CLI_DIR:-}" ]]; then
  echo "error: CLI_DIR is not set" >&2
  exit 1
fi

# Step 1: Dependency check
source "${FRAMEWORK_DIR}/lib/check/deps.sh"

# Step 2: Reconstruct argv from either CLIFT_ARG_* (standard mode) or
# CLI_ARGS (task mode, legacy)
args=()
if [[ -n "${CLIFT_ARG_COUNT:-}" ]]; then
  # Standard mode — indexed env vars set by wrapper.sh
  for (( i=1; i<=CLIFT_ARG_COUNT; i++ )); do
    var="CLIFT_ARG_$i"
    args+=("${!var}")
  done
else
  # Task mode — legacy CLI_ARGS word-splitting path
  if [[ -n "${CLI_ARGS:-}" ]]; then
    # shellcheck disable=SC2086
    eval "set -- ${CLI_ARGS}"
    args=("$@")
  fi
fi

# Step 3: Early legacy check — if the CLI has no root Taskfile (e.g., minimal
# test fixture), treat everything as legacy: skip cache management and parser
# entirely.
if [[ ! -f "$CLI_DIR/Taskfile.yaml" ]]; then
  is_legacy_no_cache=true
else
  is_legacy_no_cache=false
fi

# Step 4: Ensure cache is fresh (only when we have a root Taskfile)
source "${FRAMEWORK_DIR}/lib/cache.sh"

if [[ "$is_legacy_no_cache" != "true" ]] && [[ -z "${CLIFT_CACHE_VERIFIED:-}" ]]; then
  clift_ensure_cache "$CLI_DIR" "$FRAMEWORK_DIR"
fi

# Step 5: Load merged flag table for this task from precompiled cache
FLAGS_FILE="$CLI_DIR/.clift/flags.json"
if [[ "$is_legacy_no_cache" == "true" ]] || [[ ! -f "$FLAGS_FILE" ]]; then
  task_entry='{"legacy":true}'
else
  task_entry="$(jq -c --arg k "$TASK_NAME" '.[$k] // null' "$FLAGS_FILE")"
  if [[ "$task_entry" == "null" ]]; then
    # Task not in cache (e.g., framework-internal task routed through router)
    task_entry='{"legacy":true}'
  fi
fi

# Step 6: Legacy opt-out — if the task has no FLAG declarations, fall through
# to a simple positional-argv exec, preserving backward compatibility.
# task_entry can be: an object with {legacy: true}, an array (flag table), or null.
if [[ "$task_entry" == '{"legacy":true}' ]]; then
  is_legacy=true
else
  is_legacy=false
fi
if [[ "$is_legacy" == "true" ]]; then
  source "${FRAMEWORK_DIR}/lib/log/log.sh"
  local_namespace="${TASK_NAME%%:*}"
  script_path="${CLI_DIR}/cmds/${local_namespace}/${local_namespace}.sh"
  if [[ ! -f "$script_path" ]]; then
    log_error "Unknown command: ${local_namespace}"
    exit "$EXIT_NOT_FOUND"
  fi
  exec bash "$script_path" "${args[@]+"${args[@]}"}"
fi

# Step 7: Non-legacy — parse flags via the precompiled table.
# Inject framework-global flags (version, verbose, quiet, no-color, help) into
# the task's flag table so the parser recognises them. These names are reserved
# in the validator and cannot be user-declared, so there is no collision risk.
FRAMEWORK_GLOBALS="$(cat "${FRAMEWORK_DIR}/lib/flags/globals.json")"
merged_table="$(jq -n --argjson user "$task_entry" --argjson globals "$FRAMEWORK_GLOBALS" '$globals + $user')"

tmp_table="$(mktemp)"
trap 'rm -f "$tmp_table"' EXIT
echo "$merged_table" > "$tmp_table"

# shellcheck source=/dev/null
source "${FRAMEWORK_DIR}/lib/flags/parser.sh"
clift_parse_args "$tmp_table" "${args[@]+"${args[@]}"}"

# Step 8: Intercept built-in flags BEFORE log setup for fast --help/--version
if [[ "${CLIFT_FLAG_VERSION:-}" == "true" ]]; then
  echo "${CLI_NAME:-unknown} version ${CLI_VERSION:-0.0.0}"
  exit 0
fi

if [[ "${CLIFT_FLAG_HELP:-}" == "true" ]]; then
  local_namespace="${TASK_NAME%%:*}"
  exec bash "${FRAMEWORK_DIR}/lib/help/detail.sh" "$TASK_NAME" "$CLI_DIR/Taskfile.yaml"
fi

# Step 9: Emit legacy-compat env vars for log.sh and theming
if [[ "${CLIFT_FLAG_VERBOSE:-}" == "true" ]]; then export VERBOSE=true; fi
if [[ "${CLIFT_FLAG_QUIET:-}" == "true" ]]; then export QUIET=true; fi
if [[ "${CLIFT_FLAG_NO_COLOR:-}" == "true" ]]; then export NO_COLOR=1; fi

source "${FRAMEWORK_DIR}/lib/log/log.sh"

# Step 10: Resolve script path
export CLIFT_TASK="$TASK_NAME"
first_seg="${TASK_NAME%%:*}"
cmd_dir="${CLI_DIR}/cmds/${first_seg}"

# One-script-per-task rule: deploy:prod → cmds/deploy/deploy.prod.sh
if [[ "$TASK_NAME" == *:* ]]; then
  script_name="${TASK_NAME//:/.}"
else
  script_name="$TASK_NAME"
fi
script_path="${cmd_dir}/${script_name}.sh"

# Fallback to single-script convention for pre-spec commands
if [[ ! -f "$script_path" ]]; then
  script_path="${cmd_dir}/${first_seg}.sh"
  log_debug "one-script-per-task path not found, falling back to legacy: ${script_path}"
fi

if [[ ! -f "$script_path" ]]; then
  log_error "script not found for task '${TASK_NAME}' (looked at ${cmd_dir}/${script_name}.sh, ${cmd_dir}/${first_seg}.sh)"
  exit 1
fi

exec bash "$script_path"
