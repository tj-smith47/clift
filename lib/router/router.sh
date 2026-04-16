#!/usr/bin/env bash
# clift Router
# Called by every command's default task.
# Usage: router.sh <TASK_NAME>
#
# Flow:
#   1. Validate required env vars
#   2. Dependency check
#   3. Reconstruct argv: CLIFT_ARG_* (standard mode) or CLI_ARGS (task mode)
#   4. Early passthrough check: if no root Taskfile.yaml, skip cache/parser
#   5. Ensure precompiled cache is fresh
#   6. Load merged flag table for this task
#   7. Passthrough: if no FLAGS declared, exec script with positional argv
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

# Invariant: CLIFT_TASK is exported for the whole router lifetime, not just
# per-path. Both the pre-hook and the override loader key on it, so the
# single hoist here eliminates two duplicate exports further down and
# removes a "was this set before that source?" question from the code.
export CLIFT_TASK="$TASK_NAME"

# Step 1: Dependency check (fast — command presence only)
source "${FRAMEWORK_DIR}/lib/check/deps.sh"
clift_check_deps_fast

# Load the override loader once near the top; source-guarded so re-sourcing
# elsewhere (e.g., from prelude.sh when exec.sh runs) is a no-op. Hoisted
# here instead of per-call-site because all three sites (version_print,
# passthrough pre-hook, parsed pre-hook) need it, and the source guard
# makes the hoist semantically identical to three scoped sources.
# shellcheck source=../runtime/overrides.sh
source "${FRAMEWORK_DIR}/lib/runtime/overrides.sh"

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
  # Task mode — legacy CLI_ARGS word-splitting path.
  # Uses read -ra instead of eval to avoid command injection from user input.
  if [[ -n "${CLI_ARGS:-}" ]]; then
    read -ra args <<< "$CLI_ARGS"
  fi
fi

# Step 3: Early passthrough check — if the CLI has no root Taskfile (e.g.,
# minimal test fixture), treat everything as passthrough: skip cache management
# and parser entirely.
if [[ ! -f "$CLI_DIR/Taskfile.yaml" ]]; then
  is_passthrough_no_cache=true
else
  is_passthrough_no_cache=false
fi

# Step 4: Ensure cache is fresh (only when we have a root Taskfile)
source "${FRAMEWORK_DIR}/lib/cache.sh"

if [[ "$is_passthrough_no_cache" != "true" ]] && [[ -z "${CLIFT_CACHE_VERIFIED:-}" ]]; then
  clift_ensure_cache "$CLI_DIR" "$FRAMEWORK_DIR"
fi

# Step 5: Load flag table for this task, merge with globals — single jq call.
# Result is either "LEGACY" (no flags / not in cache) or the merged JSON array.
# Reads from the consolidated .clift/index.json (shape: {tasks: {<name>: {flags, aliases, hidden, summary}}}).
INDEX_FILE="$CLI_DIR/.clift/index.json"
if [[ "$is_passthrough_no_cache" == "true" ]] || [[ ! -f "$INDEX_FILE" ]]; then
  merged_table="LEGACY"
else
  merged_table="$(jq -c --arg k "$TASK_NAME" \
    --slurpfile globals "${FRAMEWORK_DIR}/lib/flags/globals.json" '
    .tasks[$k].flags // null |
    if . == null or (type == "object" and .passthrough == true) then "PASSTHROUGH"
    else $globals[0] + .
    end
  ' "$INDEX_FILE")"
fi

# Step 6: Passthrough — if the task has no FLAG declarations, exec the script
# directly with positional argv. No parser, no CLIFT_FLAG_* env vars.
if [[ "$merged_table" == '"PASSTHROUGH"' ]] || [[ "$merged_table" == "PASSTHROUGH" ]]; then
  source "${FRAMEWORK_DIR}/lib/log/log.sh"
  local_namespace="${TASK_NAME%%:*}"
  script_path="${CLI_DIR}/cmds/${local_namespace}/${local_namespace}.sh"
  if [[ ! -f "$script_path" ]]; then
    log_error "Unknown command: ${local_namespace}"
    exit "$EXIT_NOT_FOUND"
  fi
  # Pre-hook: fires before the user script on the passthrough path.
  clift_run_command_pre "$TASK_NAME"
  exec bash "${FRAMEWORK_DIR}/lib/runtime/exec.sh" "$script_path" "${args[@]+"${args[@]}"}"
fi

# Step 7: Parse flags via the merged table.

tmp_table="$(mktemp)"
# CLIFT_FLAGS_FILE: NUL-separated <name>=<value> records written by the parser
# for the prelude to materialize as declare -A CLIFT_FLAGS in the user script.
# Exported so the exec.sh → prelude chain (different process) can read it.
CLIFT_FLAGS_FILE="$(mktemp)"
export CLIFT_FLAGS_FILE
trap 'rm -f "$tmp_table" "$CLIFT_FLAGS_FILE"' EXIT
echo "$merged_table" > "$tmp_table"

# shellcheck source=/dev/null
source "${FRAMEWORK_DIR}/lib/flags/parser.sh"
clift_parse_args "$tmp_table" "${args[@]+"${args[@]}"}"

# Step 8: Intercept built-in flags BEFORE log setup for fast --help/--version.
# Note: top-level `mycli --version` is handled by wrapper.sh.tmpl before
# reaching the router. This block fires only for `mycli <cmd> --version`,
# where --version is merged in as a global flag from globals.json.
if [[ "${CLIFT_FLAG_VERSION:-}" == "true" ]]; then
  clift_call_override version_print clift_default_version_print \
    "${CLI_NAME:-unknown}" "${CLI_VERSION:-0.0.0}" "$CLI_DIR"
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

# Step 10: Resolve script path.
# CLIFT_TASK is already exported at the top of the router — see the
# single-hoist comment there.
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

# Pre-hook: fires before the user script on the parsed path.
clift_run_command_pre "$TASK_NAME"

exec bash "${FRAMEWORK_DIR}/lib/runtime/exec.sh" "$script_path"
