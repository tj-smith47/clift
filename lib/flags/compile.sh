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

# Dependency check (full — includes version metadata)
source "$SCRIPT_DIR/../check/deps.sh"
clift_check_deps_full

mkdir -p "$CACHE_DIR"

trap 'rm -f "${CACHE_DIR}/tasks.json.tmp" "${CACHE_DIR}/flags.json.tmp" "${CACHE_DIR}/checksum.tmp" "${CACHE_DIR}/entries.tmp" "${CACHE_DIR}/sources.tmp"' EXIT

# Step 1: capture task list via `task --list-all --json --nested`.
# Must run from within the CLI dir so Task resolves includes correctly.
# This runs FIRST so we can derive the authoritative list of command Taskfile
# paths from Task's own output — no hardcoded filename globs.
if ! ( cd "$CLI_DIR" && task --list-all --json --nested ) > "${CACHE_DIR}/tasks.json.tmp" 2>/dev/null; then
  echo "error: failed to list tasks for ${CLI_DIR}" >&2
  exit 1
fi
mv "${CACHE_DIR}/tasks.json.tmp" "${CACHE_DIR}/tasks.json"

# Step 2: flatten the nested task list.
# `--list-all --json --nested` has TWO sources of tasks:
#   - .tasks[]                         (root-level tasks)
#   - .namespaces.<ns>.tasks[]         (namespaced/included tasks, recursive
#                                       for deeper nesting)
# The recursive descent `.. | .tasks? // empty` flattens any depth. Each task
# object carries `.location.taskfile` pointing at its source file — the
# authoritative way to know which command a task belongs to, without ever
# string-parsing task names.
all_tasks_json="$(jq '[.. | .tasks? // empty | .[]]' "${CACHE_DIR}/tasks.json")"

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

# Step 3: validate all command Taskfiles before emitting any cache. If any flag
# schema is invalid, fail loudly and leave the cache untouched so a stale-but-valid
# build stays usable.
# Uses the authoritative file list from Task's output — not a hardcoded glob —
# so custom-named Taskfiles are included.
# NOTE: the root Taskfile is intentionally skipped — its vars.FLAGS defines
# the framework globals (help, verbose, quiet, no-color, version) which are
# themselves the reserved names. Validating them against the reserved-name
# blocklist is circular.
source "$SCRIPT_DIR/validate.sh"
while IFS= read -r tf; do
  [[ -z "$tf" ]] && continue
  [[ "$tf" == "$ROOT_TASKFILE" ]] && continue

  local_tf_json="$(yq -o=json '.' "$tf")" || {
    echo "error: failed to parse Taskfile: ${tf}" >&2
    exit 1
  }

  top_layer="$(echo "$local_tf_json" | jq -c '.vars.FLAGS // null')"
  _validate_layer "$top_layer" "${tf}:vars.FLAGS" || exit 1

  local_tasks_type="$(echo "$local_tf_json" | jq -r '.tasks | type')"
  if [[ "$local_tasks_type" == "object" ]]; then
    while IFS= read -r -d '' vt_name && IFS= read -r -d '' vt_flags; do
      [[ -z "$vt_name" ]] && continue
      _validate_layer "$vt_flags" "${tf}:tasks.${vt_name}.vars.FLAGS" || exit 1
    done < <(echo "$local_tf_json" | jq -j '
      .tasks | to_entries[] |
      .key + "\u0000" + ((.value.vars.FLAGS // null) | tojson) + "\u0000"
    ')
  fi
done <<< "$unique_taskfiles"

# Step 4: batch-load each command Taskfile exactly ONCE.
# At scale (100+ commands) we cannot afford per-task yq invocations. Read each
# unique command Taskfile a single time and cache its FLAGS data in-memory as
# a jq object keyed by absolute file path.

root_flags="$(yq -o=json '.vars.FLAGS // []' "$ROOT_TASKFILE")" || {
  echo "error: failed to parse root Taskfile: ${ROOT_TASKFILE}" >&2
  exit 1
}

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
  ' "$tf")" || {
    echo "error: failed to parse Taskfile: ${tf}" >&2
    exit 1
  }
  taskfile_data["$tf"]="$tf_json"
done <<< "$unique_taskfiles"

# Step 5: build flags.json entries via temp file, assemble once at the end.
entries_tmpfile="${CACHE_DIR}/entries.tmp"
: > "$entries_tmpfile"

# Cache has_optin results per Taskfile to avoid redundant jq calls.
declare -A _tf_optin_cache

while IFS=$'\x01' read -r -d '' task_name source_tf aliases_json; do
  [[ -z "$task_name" ]] && continue

  # Skip framework-internal tasks (underscore prefix).
  [[ "$task_name" == _* ]] && continue
  [[ "$task_name" == *:_* ]] && continue

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
  # If not, the command is passthrough and the router falls back to positional argv.
  if [[ -n "${_tf_optin_cache[$source_tf]+x}" ]]; then
    has_optin="${_tf_optin_cache[$source_tf]}"
  else
    has_optin="$(jq -r '
      (.toplevel != null) or
      ([.tasks[]? | select(. != null)] | length > 0)
    ' <<< "$tf_data")"
    _tf_optin_cache["$source_tf"]="$has_optin"
  fi

  # Read aliases as NUL-separated list (safe for names with spaces/colons).
  # Aliases get the same flags entry as the canonical task name.
  aliases=()
  if [[ "$aliases_json" != "[]" ]]; then
    while IFS= read -r -d '' a; do
      [[ -n "$a" ]] && aliases+=("$a")
    done < <(jq -j '.[] + "\u0000"' <<< "$aliases_json")
  fi

  if [[ "$has_optin" != "true" ]]; then
    printf '%s\t%s\n' "$task_name" '{"passthrough":true}' >> "$entries_tmpfile"
    for alias in "${aliases[@]+"${aliases[@]}"}"; do
      printf '%s\t%s\n' "$alias" '{"passthrough":true}' >> "$entries_tmpfile"
    done
    continue
  fi

  # Combined merge + shadow check in a single jq call.
  {
    IFS= read -r -d '' merged || true
    IFS= read -r -d '' shadow_check || true
  } < <(jq -j -n \
    --argjson root "$root_flags" \
    --argjson tfdata "$tf_data" \
    --arg local_task "$local_task" \
    --arg task_name "$task_name" \
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
    ) as $merged |

    # Spec §4.3: warn if a command-level flag shadows a global short alias.
    ($root | map({(.short // ""): .name}) | add // {}) as $globals |
    ([
      [($tfdata.toplevel // [])[], ($tfdata.tasks[$local_task] // [])[]]
      | .[]
      | select(.short != null and .short != "")
      | select($globals[.short] != null)
      | "warning: task \($task_name) shadows global short -\(.short) (was --\($globals[.short]), now --\(.name))"
    ] | join("\n")) as $warnings |

    ($merged | tojson) + "\u0000" + $warnings + "\u0000"
    ')

  if [[ -n "$shadow_check" ]]; then
    echo "$shadow_check" >&2
  fi

  printf '%s\t%s\n' "$task_name" "$merged" >> "$entries_tmpfile"
  for alias in "${aliases[@]+"${aliases[@]}"}"; do
    printf '%s\t%s\n' "$alias" "$merged" >> "$entries_tmpfile"
  done
done < <(jq -j '
  .[] |
  .name + "\u0001" +
  .location.taskfile + "\u0001" +
  ((.aliases // []) | tojson) + "\u0000"
' <<< "$all_tasks_json")

# Assemble all entries into flags.json with a single jq call.
# Tab-separated: key<TAB>json_value
jq -R -n '
  [inputs | split("\t") | {key: .[0], value: (.[1:] | join("\t") | fromjson)}]
  | from_entries
' "$entries_tmpfile" > "${CACHE_DIR}/flags.json.tmp"
mv "${CACHE_DIR}/flags.json.tmp" "${CACHE_DIR}/flags.json"

# Step 6: write sources manifest + checksum using portable mtime helper.
# The sources manifest lists every Taskfile the cache depends on so that the
# staleness check in cache.sh tracks the right files — no hardcoded globs.
source "$SCRIPT_DIR/../cache.sh"
{
  echo "$ROOT_TASKFILE"
  while IFS= read -r _sf; do
    [[ -n "$_sf" ]] && echo "$_sf"
  done <<< "$unique_taskfiles"
} > "${CACHE_DIR}/sources.tmp"
mv "${CACHE_DIR}/sources.tmp" "${CACHE_DIR}/sources"
# Word splitting is intentional: one file path per line from the sources manifest.
# shellcheck disable=SC2046
clift_max_mtime $(< "${CACHE_DIR}/sources") > "${CACHE_DIR}/checksum.tmp"
mv "${CACHE_DIR}/checksum.tmp" "${CACHE_DIR}/checksum"

exit 0
