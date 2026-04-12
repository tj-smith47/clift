#!/usr/bin/env bash
# clift Precompilation Cache Builder
# Usage: compile.sh <CLI_DIR>
# Builds .clift/tasks.json, .clift/flags.json, .clift/checksum from Taskfiles.
#
# Called by:
#   - setup:cli (fresh install)
#   - new:cmd / new:subcmd (after scaffold writes)
#   - wrapper.sh and router.sh when cache is stale

set -euo pipefail

CLI_DIR="${1:-}"

if [[ -z "$CLI_DIR" ]] || [[ ! -d "$CLI_DIR" ]]; then
  echo "error: compile.sh requires a valid CLI directory" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${CLI_DIR}/.clift"
ROOT_TASKFILE="${CLI_DIR}/Taskfile.yaml"

if [[ ! -f "$ROOT_TASKFILE" ]]; then
  echo "error: no Taskfile.yaml found at ${CLI_DIR}" >&2
  exit 1
fi

mkdir -p "$CACHE_DIR"

trap 'rm -f "${CACHE_DIR}/tasks.json.tmp" "${CACHE_DIR}/flags.json.tmp" "${CACHE_DIR}/checksum.tmp"' EXIT

# Step 1: validate all command Taskfiles before emitting any cache. If any flag
# schema is invalid, fail loudly and leave the cache untouched so a stale-but-valid
# build stays usable.
# NOTE: the root Taskfile is intentionally skipped — its vars.FLAGS defines
# the framework globals (help, verbose, quiet, no-color, version) which are
# themselves the reserved names. Validating them against the reserved-name
# blocklist is circular.
for tf in "$CLI_DIR"/cmds/*/Taskfile.yaml; do
  [[ -f "$tf" ]] || continue
  bash "$SCRIPT_DIR/validate.sh" "$tf"
done

# Step 2: capture task list via `task --list-all --json --nested`.
# Must run from within the CLI dir so Task resolves includes correctly.
( cd "$CLI_DIR" && task --list-all --json --nested ) > "${CACHE_DIR}/tasks.json.tmp"
mv "${CACHE_DIR}/tasks.json.tmp" "${CACHE_DIR}/tasks.json"

# Step 3: flatten the nested task list.
# `--list-all --json --nested` has TWO sources of tasks:
#   - .tasks[]                         (root-level tasks)
#   - .namespaces.<ns>.tasks[]         (namespaced/included tasks, recursive
#                                       for deeper nesting)
# The recursive descent `.. | .tasks? // empty` flattens any depth. Each task
# object carries `.location.taskfile` pointing at its source file — the
# authoritative way to know which command a task belongs to, without ever
# string-parsing task names.
all_tasks_json="$(jq '[.. | .tasks? // empty | .[]]' "${CACHE_DIR}/tasks.json")"

# Step 4: batch-load each command Taskfile exactly ONCE.
# At scale (100+ commands) we cannot afford per-task yq invocations. Read each
# unique command Taskfile a single time and cache its FLAGS data in-memory as
# a jq object keyed by absolute file path.

# Skip framework-internal taskfiles — their location.taskfile lives under
# FRAMEWORK_DIR. The `:-__nomatch__` fallback keeps us safe under `set -u`
# when FRAMEWORK_DIR isn't exported (e.g. when running outside a wrapper).
FW_DIR="${FRAMEWORK_DIR:-__nomatch__}"

unique_taskfiles="$(jq -r --arg fw "$FW_DIR" '
  [ .[]
    | .location.taskfile
    | select(startswith($fw) | not)
  ] | unique | .[]
' <<< "$all_tasks_json")"

root_flags="$(yq -o=json '.vars.FLAGS // []' "$ROOT_TASKFILE")"

# Build an in-memory map: taskfile path -> {toplevel: [...], tasks: {name: [...]}}
declare -A taskfile_data
while IFS= read -r tf; do
  [[ -z "$tf" ]] && continue
  # Single yq call per Taskfile extracts EVERYTHING we need:
  #   - top-level vars.FLAGS
  #   - per-task vars.FLAGS keyed by task name
  tf_json="$(yq -o=json '
    {
      "toplevel": (.vars.FLAGS // null),
      "tasks": (.tasks // {} | with_entries(.value = (.value.vars.FLAGS // null)))
    }
  ' "$tf")"
  taskfile_data["$tf"]="$tf_json"
done <<< "$unique_taskfiles"

# Step 5: build flags.json entries in memory, emit once at the end.
flags_entries='{}'

while IFS= read -r task_row; do
  [[ -z "$task_row" ]] && continue

  task_name="$(jq -r '.name' <<< "$task_row")"
  # Skip framework-internal tasks (underscore prefix).
  [[ "$task_name" == _* ]] && continue
  [[ "$task_name" == *:_* ]] && continue

  source_tf="$(jq -r '.location.taskfile' <<< "$task_row")"
  # Root-level helpers (version, default) are not dispatched through the router.
  [[ "$source_tf" == "$ROOT_TASKFILE" ]] && continue
  # Framework library taskfiles (lib/help/Taskfile.yaml, etc.).
  [[ "$source_tf" == "$FW_DIR"* ]] && continue

  tf_data="${taskfile_data[$source_tf]:-}"
  [[ -z "$tf_data" ]] && continue

  # The local task name is the portion after the namespace separator.
  # For `greet:loud`, local_task is `loud`. A bare `greet` maps to `default`.
  first_seg="${task_name%%:*}"
  if [[ "$first_seg" == "$task_name" ]]; then
    local_task="default"
  else
    local_task="${task_name#*:}"
  fi

  # Opt-in check: does this Taskfile declare any FLAGS (top-level or per-task)?
  # If not, the command is legacy and the router falls back to positional argv.
  has_optin="$(jq -r '
    (.toplevel != null) or
    ([.tasks[]? | select(. != null)] | length > 0)
  ' <<< "$tf_data")"

  # Read aliases as NUL-separated list (safe for names with spaces/colons).
  # Aliases get the same flags entry as the canonical task name.
  aliases=()
  while IFS= read -r -d '' a; do
    [[ -n "$a" ]] && aliases+=("$a")
  done < <(jq -j '(.aliases // []) | .[] + "\u0000"' <<< "$task_row")

  if [[ "$has_optin" != "true" ]]; then
    flags_entries="$(jq --arg k "$task_name" '.[$k] = {legacy: true}' <<< "$flags_entries")"
    for alias in "${aliases[@]}"; do
      flags_entries="$(jq --arg k "$alias" '.[$k] = {legacy: true}' <<< "$flags_entries")"
    done
    continue
  fi

  merged="$(jq -n \
    --argjson root "$root_flags" \
    --argjson tfdata "$tf_data" \
    --arg local_task "$local_task" \
    '
    def merge_in(acc; new):
      if new == null or new == [] then acc
      else
        reduce new[] as $e (acc;
          map(select(
            .name != $e.name
            and (((.short // "") == "") or ((.short // "") != ($e.short // "__none__")))
          )) + [$e]
        )
      end;
    merge_in(
      merge_in($root; $tfdata.toplevel);
      $tfdata.tasks[$local_task]
    )
    ')"

  # Spec §4.3: warn if a command-level flag shadows a global short alias.
  if [[ -n "${tf_data}" ]]; then
    shadow_check="$(jq -r -n \
      --argjson root "$root_flags" \
      --argjson tfdata "$tf_data" \
      --arg local_task "$local_task" \
      --arg task_name "$task_name" \
      '
      ($root | map({(.short // ""): .name}) | add // {}) as $globals |
      [($tfdata.toplevel // [])[], ($tfdata.tasks[$local_task] // [])[]] |
      .[] |
      select(.short != null and .short != "") |
      select($globals[.short] != null) |
      "warning: task \($task_name) shadows global short -\(.short) (was --\($globals[.short]), now --\(.name))"
      ')"
    if [[ -n "$shadow_check" ]]; then
      echo "$shadow_check" >&2
    fi
  fi

  flags_entries="$(jq --arg k "$task_name" --argjson v "$merged" '.[$k] = $v' <<< "$flags_entries")"
  for alias in "${aliases[@]}"; do
    flags_entries="$(jq --arg k "$alias" --argjson v "$merged" '.[$k] = $v' <<< "$flags_entries")"
  done
done < <(jq -c '.[]' <<< "$all_tasks_json")

echo "$flags_entries" > "${CACHE_DIR}/flags.json.tmp"
mv "${CACHE_DIR}/flags.json.tmp" "${CACHE_DIR}/flags.json"

# Step 6: write checksum using portable mtime helper.
source "$SCRIPT_DIR/../cache.sh"
clift_max_mtime "$ROOT_TASKFILE" "$CLI_DIR"/cmds/*/Taskfile.yaml > "${CACHE_DIR}/checksum.tmp"
mv "${CACHE_DIR}/checksum.tmp" "${CACHE_DIR}/checksum"

exit 0
