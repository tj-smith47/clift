#!/usr/bin/env bash
# clift Taskfile source reader
#
# Tier 1A primitive for `clift init --from`. Wraps go-task's own
# `--list-all --json --nested` output and joins it with raw YAML
# `vars` / `requires.vars` data so the higher tiers can stop caring
# about YAML at all. Output is a flat task list — namespaces collapsed,
# `<ns>:default` rewritten to bare `<ns>`, wildcards flagged, internals
# omitted (go-task already filters them out of `--list-all`).
#
# Single entry point:
#   read_source <path>   → JSON document on stdout
#
# Output schema (one task per entry):
#   {
#     "source": "<absolute path>",
#     "tasks": [
#       {
#         "name": "deploy",        # clift-side task name (`:default` trimmed)
#         "task": "deploy",        # original go-task task name (preserved)
#         "desc": "...",
#         "summary": "...",
#         "aliases": [...],
#         "wildcard": false,       # true when original name contains `*`
#         "vars":           {...}, # raw `vars:` map from the YAML
#         "requires_vars":  [...], # raw `requires.vars:` list from the YAML
#         "passthrough":   true    # vars empty AND requires empty
#       }
#     ]
#   }
#
# Error behaviour:
#   - Missing / unreadable source path → exits 1 with `error: ...` on stderr.
#   - `task` parse failure              → exits 1 with `error: ...` on stderr.
#   - `yq` parse failure on the source  → exits 1 with `error: ...` on stderr.

set -euo pipefail

# shellcheck disable=SC2317  # `exit 0` fallback fires only if file is run directly
if [[ -n "${_CLIFT_FROM_TASKFILE_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
_CLIFT_FROM_TASKFILE_LOADED=1

_CLIFT_FROM_TASKFILE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../check/deps.sh
. "$_CLIFT_FROM_TASKFILE_DIR/../check/deps.sh"

# read_source <path>
# Emits the normalized JSON document on stdout. Returns 0 on success and
# 1 on any error (with a clear `error: ...` line on stderr).
read_source() {
  if [[ $# -lt 1 ]]; then
    echo "error: read_source requires <path>" >&2
    return 1
  fi

  local src="$1"

  if [[ ! -e "$src" ]]; then
    echo "error: source not found: ${src}" >&2
    return 1
  fi
  if [[ ! -f "$src" ]]; then
    echo "error: source is not a regular file: ${src}" >&2
    return 1
  fi
  if [[ ! -r "$src" ]]; then
    echo "error: source not readable: ${src}" >&2
    return 1
  fi

  # Resolve to an absolute path so downstream tiers can stuff it into
  # generated wrappers / .clift.yaml without re-resolving.
  local abs
  abs="$(cd "$(dirname "$src")" && pwd)/$(basename "$src")"

  # Confirm the toolchain we depend on. clift_check_deps_full also covers
  # bash version, jq, and yq — exactly the set we need below.
  clift_check_deps_full

  # Step 1: list-all from go-task. The `--nested` flag groups namespaced
  # tasks under `.namespaces.<ns>.tasks[]`; we flatten with a recursive
  # descent below. `internal: true` is already excluded by go-task.
  local list_json
  if ! list_json="$(task --list-all --json --nested --taskfile "$abs" 2>/dev/null)"; then
    echo "error: failed to list tasks for ${abs}" >&2
    return 1
  fi

  # Step 2: raw YAML — gives us `vars:` and `requires.vars:`, which
  # `--list-all --json` does not surface. Limited to the source file's
  # own tasks; included files would need their own read_source call,
  # which is outside this tier's scope.
  local yaml_json
  if ! yaml_json="$(yq -o=json '.tasks // {}' "$abs" 2>/dev/null)"; then
    echo "error: failed to parse YAML: ${abs}" >&2
    return 1
  fi

  # Step 3: single jq pass joins the two streams and produces the
  # output document. Task names are normalized:
  #   - `<ns>:default`   →  bare `<ns>`   (clift-side `name`)
  #   - `<ns>:<sub>`     →  unchanged
  #   - `<ns>:*`         →  bare `<ns>`   (wildcard segment stripped)
  #   - `build:*:release`→  `build:release` (wildcard segment stripped)
  # In all wildcard cases `wildcard: true` is flagged so downstream
  # writers know to emit a positional-taking wrapper. The original task
  # identifier is preserved verbatim in `task` so the wrapper can
  # dispatch via `task -t … '<original>'` (with `${target}` substituted
  # in for the wildcard segment).
  jq -cn \
    --arg source "$abs" \
    --argjson list "$list_json" \
    --argjson yaml "$yaml_json" '
    # Flatten root + every nested namespace into one task array.
    def flatten_tasks:
      [ .. | objects | .tasks? // empty | .[] ];

    # Strip wildcard segment(s) from a colon-separated task name and
    # normalize trailing `:default`. Examples:
    #   "deploy"          → "deploy"
    #   "deploy:*"        → "deploy"
    #   "build:*:release" → "build:release"
    #   "lint:default"    → "lint"
    #   "lint:eslint"     → "lint:eslint"
    def normalize_name:
      ( split(":")
        | map(select(. != "*"))
        | join(":")
      )
      | sub(":default$"; "")
      ;

    ($list | flatten_tasks) as $entries |
    {
      source: $source,
      tasks:
        ( $entries
          | map(
              . as $t |
              ($t.task | test("\\*"))                       as $is_wild |
              ($t.task | normalize_name)                    as $clift_name |
              ($yaml[$t.task]                  // {})       as $yt |
              ($yt.vars                        // {})       as $vars |
              (($yt.requires // {}).vars       // [])       as $reqs |
              (
                ( ($vars | length) == 0 )
                and ( ($reqs | length) == 0 )
              )                                             as $is_passthrough |
              {
                name:           $clift_name,
                task:           $t.task,
                desc:           ($t.desc    // ""),
                summary:        ($t.summary // ""),
                aliases:        ($t.aliases // []),
                wildcard:       $is_wild,
                vars:           $vars,
                requires_vars:  $reqs,
                passthrough:    $is_passthrough
              }
            )
        )
    }
  '
}

# When invoked directly (`bash from_taskfile.sh <path>`) act as a thin CLI
# so callers can pipe the JSON to jq or save it for inspection. Sourced
# usage skips this branch via the load-guard at the top of the file.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  read_source "$@"
fi
