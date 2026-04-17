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

trap 'rm -f "${CACHE_DIR}/tasks.json.tmp" "${CACHE_DIR}/flags.json.tmp" "${CACHE_DIR}/index.json.tmp" "${CACHE_DIR}/checksum.tmp" "${CACHE_DIR}/entries.tmp" "${CACHE_DIR}/sources.tmp"' EXIT

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

# Duplicate-alias check (Task 5.1, finding C1). Two top-level commands declaring
# the same alias name (e.g. `deploy → d` and `destroy → d`) would silently
# last-write-wins in the wrapper's _aliases_map, masking one route. Reject at
# compile time with a hard error analogous to the persistent-vs-per-command
# clash check above. Aliases that strip down to either empty or still contain
# `:` are skipped — those don't reach the wrapper's first-token substitution
# table so they can't collide there either.
_alias_clash_msg="$(jq -r '
  [ .[]
    | select(.name | test("^_|:_") | not)
    | . as $task
    | ($task.name | sub(":default$"; "")) as $canonical
    | ($task.name | capture("^(?<ns>.*):[^:]+$").ns // "") as $ns
    | ($task.aliases // [])[] as $a
    | (if $ns == "" then $a
       elif ($a | startswith($ns + ":")) then ($a | ltrimstr($ns + ":"))
       else $a
       end) as $user_alias
    | select($user_alias != ""
             and ($user_alias | contains(":") | not)
             and $user_alias != $canonical)
    | { alias: $user_alias, canonical: $canonical }
  ]
  | group_by(.alias)
  | map(select((map(.canonical) | unique | length) > 1))
  | .[0]
  | if . == null then ""
    else
      (.[0].alias) as $a
      | (map(.canonical) | unique | sort | join("'\'' and '\''"))
      | "error: alias '\''\($a)'\'' declared by both '\''\(.)'\''"
    end
' <<< "$all_tasks_json")"
if [[ -n "$_alias_clash_msg" ]]; then
  echo "$_alias_clash_msg" >&2
  exit 1
fi

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

# Pull both vars.FLAGS (framework globals, forms the base layer) and
# vars.PERSISTENT_FLAGS (user-declared CLI-wide flags) in a single yq call.
root_layers="$(yq -o=json '{"flags": (.vars.FLAGS // []), "persistent": (.vars.PERSISTENT_FLAGS // [])}' "$ROOT_TASKFILE")" || {
  echo "error: failed to parse root Taskfile: ${ROOT_TASKFILE}" >&2
  exit 1
}
root_flags="$(jq -c '.flags' <<< "$root_layers")"
persistent_flags="$(jq -c '.persistent' <<< "$root_layers")"

# Validate PERSISTENT_FLAGS as a flag layer using the standard validator.
# Reserved-name checks (help/verbose/quiet/no-color/version) already fire inside
# _validate_layer, so a clash with a framework global is rejected here with a
# clear "is reserved (framework global)" message.
_validate_layer "$persistent_flags" "${ROOT_TASKFILE}:vars.PERSISTENT_FLAGS" || exit 1

# Persistent-layer group/exclusive/requires are rejected — groups only make
# sense within a single command's flag table. The wrapper's early-bind pass
# would also have to understand group semantics, and cross-layer group
# consistency (persistent vs per-command) is out of scope.
_pg_first="$(jq -r '[.[]? | select((.group // "") != "" or (.exclusive // false) == true or (.requires // "") != "") | .name] | .[0] // ""' <<< "$persistent_flags")"
if [[ -n "$_pg_first" ]]; then
  echo "error: ${ROOT_TASKFILE}:vars.PERSISTENT_FLAGS: flag '${_pg_first}' cannot declare group/exclusive/requires (not yet supported — declare these on per-command flags only)" >&2
  exit 1
fi

# Cross-layer clash detection runs below if any persistent flag is declared.
# A persistent flag and a per-command flag that share a name (or short) is
# ambiguous — the wrapper would bind the persistent one before the command
# token and the per-command parser would redefine it afterward. Reject at
# compile time via jq on $persistent_flags directly; no intermediate CSV
# needed.

# Build an in-memory map: taskfile path -> {toplevel: [...], tasks: {name: [...]}}
declare -A taskfile_data
while IFS= read -r tf; do
  [[ -z "$tf" ]] && continue
  # Single yq call per Taskfile extracts EVERYTHING we need:
  #   - top-level vars.FLAGS
  #   - per-task vars.FLAGS keyed by task name
  #   - top-level vars.HIDDEN (bool) — hides the whole command
  #   - per-task vars.HIDDEN keyed by task name
  # Casing: vars.HIDDEN is ALL_CAPS to match the existing vars.FLAGS /
  # vars.PERSISTENT_FLAGS "section marker" convention. Per-flag `hidden:` is
  # lowercase because it's a flag attribute, not a section marker.
  tf_json="$(yq -o=json '
    {
      "toplevel": (.vars.FLAGS // null),
      "tasks": (.tasks // {} | with_entries(.value = (.value.vars.FLAGS // null))),
      "hidden_top": (.vars.HIDDEN // false),
      "hidden_tasks": (.tasks // {} | with_entries(.value = (.value.vars.HIDDEN // false)))
    }
  ' "$tf")" || {
    echo "error: failed to parse Taskfile: ${tf}" >&2
    exit 1
  }
  taskfile_data["$tf"]="$tf_json"
done <<< "$unique_taskfiles"

# Step 5: build index.json entries via temp file, assemble once at the end.
# Each TSV row is: task_name<TAB>json_value where json_value has shape:
#   {flags: [...] | {passthrough:true}, aliases: [...], hidden: bool, summary: str}
# Aliases of a task share the same per-task record (same flags/hidden/summary,
# but their `aliases` field is the empty list — only the canonical name lists
# its aliases).
entries_tmpfile="${CACHE_DIR}/entries.tmp"
: > "$entries_tmpfile"

# Cache has_optin results per Taskfile to avoid redundant jq calls.
declare -A _tf_optin_cache

while IFS=$'\x01' read -r -d '' task_name source_tf aliases_json summary; do
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

  # Resolve `hidden` with per-task precedence over top-level (matches FLAGS
  # merge order). A per-task `vars.HIDDEN: true` hides only that subtask; a
  # top-level one hides the whole command. Either true wins.
  hidden_bool="$(jq -r --arg lt "$local_task" '
    (.hidden_top // false) as $top |
    (.hidden_tasks[$lt] // false) as $per |
    ($top or $per)
  ' <<< "$tf_data")"

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
  aliases=()
  if [[ "$aliases_json" != "[]" ]]; then
    while IFS= read -r -d '' a; do
      [[ -n "$a" ]] && aliases+=("$a")
    done < <(jq -j '.[] + "\u0000"' <<< "$aliases_json")
  fi

  if [[ "$has_optin" != "true" ]]; then
    # Passthrough: no flag table, but hidden/summary still apply.
    canonical_entry="$(jq -c -n \
      --argjson aliases "$aliases_json" \
      --argjson hidden "$hidden_bool" \
      --arg summary "$summary" \
      '{flags: {passthrough: true}, aliases: $aliases, hidden: $hidden, summary: $summary}')"
    printf '%s\t%s\n' "$task_name" "$canonical_entry" >> "$entries_tmpfile"
    for alias in "${aliases[@]+"${aliases[@]}"}"; do
      alias_entry="$(jq -c -n \
        --argjson hidden "$hidden_bool" \
        --arg summary "$summary" \
        '{flags: {passthrough: true}, aliases: [], hidden: $hidden, summary: $summary}')"
      printf '%s\t%s\n' "$alias" "$alias_entry" >> "$entries_tmpfile"
    done
    continue
  fi

  # Cross-layer clash detection: a persistent flag cannot share a name, alias,
  # or short with a per-command (top-level or per-task) flag. The error names
  # both layers so the user knows where to fix it.
  if [[ "$persistent_flags" != "[]" && "$persistent_flags" != "null" ]]; then
    _clash_msg="$(jq -r -n \
      --argjson persistent "$persistent_flags" \
      --argjson tfdata "$tf_data" \
      --arg local_task "$local_task" \
      --arg tf "$source_tf" \
      '
      ($persistent | map(.name) | unique) as $pnames |
      ($persistent | map(select((.short // "") != "") | .short) | unique) as $pshorts |
      [($tfdata.toplevel // [])[], ($tfdata.tasks[$local_task] // [])[]] as $cmdflags |
      [ $cmdflags[] | . as $f |
        (
          if ($pnames | index($f.name)) then
            "error: flag '\''\($f.name)'\'' declared in persistent flags conflicts with per-command flag in \($tf)"
          elif (($f.aliases // []) | map(select($pnames | index(.))) | length > 0) then
            "error: alias of flag '\''\($f.name)'\'' conflicts with persistent flag name in \($tf)"
          elif (($f.short // "") != "" and ($pshorts | index($f.short))) then
            "error: short '\''-\($f.short)'\'' of flag '\''\($f.name)'\'' conflicts with persistent flag short in \($tf)"
          else empty
          end
        )
      ] | .[0] // ""
      ')"
    if [[ -n "$_clash_msg" ]]; then
      echo "$_clash_msg" >&2
      exit 1
    fi
  fi

  # Combined merge + shadow check in a single jq call.
  # Merge order: globals (root Taskfile's vars.FLAGS) -> persistent ->
  # per-command top-level -> per-task. Later layers override earlier ones on
  # name or short collision (persistent cannot clash with per-command — caught
  # above — but CAN override a global's short alias if the user redeclares it).
  {
    IFS= read -r -d '' merged || true
    IFS= read -r -d '' shadow_check || true
  } < <(jq -j -n \
    --argjson root "$root_flags" \
    --argjson persistent "$persistent_flags" \
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
      merge_in(
        merge_in($root; $persistent);
        $tfdata.toplevel
      );
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

  canonical_entry="$(jq -c -n \
    --argjson flags "$merged" \
    --argjson aliases "$aliases_json" \
    --argjson hidden "$hidden_bool" \
    --arg summary "$summary" \
    '{flags: $flags, aliases: $aliases, hidden: $hidden, summary: $summary}')"
  printf '%s\t%s\n' "$task_name" "$canonical_entry" >> "$entries_tmpfile"
  for alias in "${aliases[@]+"${aliases[@]}"}"; do
    alias_entry="$(jq -c -n \
      --argjson flags "$merged" \
      --argjson hidden "$hidden_bool" \
      --arg summary "$summary" \
      '{flags: $flags, aliases: [], hidden: $hidden, summary: $summary}')"
    printf '%s\t%s\n' "$alias" "$alias_entry" >> "$entries_tmpfile"
  done
done < <(jq -j '
  .[] |
  .name + "\u0001" +
  .location.taskfile + "\u0001" +
  ((.aliases // []) | tojson) + "\u0001" +
  (.summary // "") + "\u0000"
' <<< "$all_tasks_json")

# Assemble entries into index.json with a single jq pass, then derive flags.json
# as a {task: flags} view for backwards compat with out-of-tree consumers.
# Tab-separated: key<TAB>json_value
jq -R -n --argjson persistent "$persistent_flags" '
  [inputs | split("\t") | {key: .[0], value: (.[1:] | join("\t") | fromjson)}]
  | from_entries
  | {tasks: ., persistent_flags: $persistent}
' "$entries_tmpfile" > "${CACHE_DIR}/index.json.tmp"
mv "${CACHE_DIR}/index.json.tmp" "${CACHE_DIR}/index.json"

# Derive flags.json (flat {task: flags} view) from index.json. This is a
# compatibility shim; internal consumers now read index.json directly.
jq -c '.tasks | with_entries(.value = .value.flags)' \
  "${CACHE_DIR}/index.json" > "${CACHE_DIR}/flags.json.tmp"
mv "${CACHE_DIR}/flags.json.tmp" "${CACHE_DIR}/flags.json"

# Step 6: write sources manifest + checksum using portable mtime helper.
# The sources manifest lists every Taskfile the cache depends on so that the
# staleness check in cache.sh tracks the right files — no hardcoded globs.
source "$SCRIPT_DIR/../cache.sh"
{
  echo "$ROOT_TASKFILE"
  while IFS= read -r _sf; do
    [[ -z "$_sf" ]] && continue
    # `unique_taskfiles` can include the root Taskfile itself (root-level
    # tasks like `default`/`version` live there). Skip it here so the
    # manifest lists each file exactly once.
    [[ "$_sf" == "$ROOT_TASKFILE" ]] && continue
    echo "$_sf"
  done <<< "$unique_taskfiles"
} > "${CACHE_DIR}/sources.tmp"
mv "${CACHE_DIR}/sources.tmp" "${CACHE_DIR}/sources"
# Word splitting is intentional: one file path per line from the sources manifest.
# shellcheck disable=SC2046
clift_max_mtime $(< "${CACHE_DIR}/sources") > "${CACHE_DIR}/checksum.tmp"
mv "${CACHE_DIR}/checksum.tmp" "${CACHE_DIR}/checksum"

exit 0
