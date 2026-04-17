#!/usr/bin/env bash
# Renders the CLI help listing with grouped commands.
# Uses --nested for structured namespace data.
# Usage: list.sh <TASKFILE_PATH>
# Reads CLI_NAME, CLI_VERSION from environment.
#
# Overridable via the `help_list` slot. See docs/cli/overrides.md.

set -euo pipefail

# shellcheck source=render_flags.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/render_flags.sh"

TASKFILE_PATH="${1:-}"

if [[ -z "$TASKFILE_PATH" ]]; then
  echo "error: list.sh requires taskfile path as argument" >&2
  exit 1
fi

CLI_NAME="${CLI_NAME:-mycli}"
CLI_VERSION="${CLI_VERSION:-0.0.0}"
TASKFILE_DIR="$(dirname "$TASKFILE_PATH")"
# CLI_DIR may already be exported by the caller (router / wrapper). Fall back
# to TASKFILE_DIR so direct invocations still work — the override loader
# needs CLI_DIR set to resolve `.clift/overrides/help_list.sh`.
CLI_DIR="${CLI_DIR:-$TASKFILE_DIR}"
export CLI_DIR

# Helper: render Global Flags section from root Taskfile vars.FLAGS.
# Lifted to file scope so it isn't redefined on every call of
# `_clift_help_list_default` (e.g. when a wrapping override invokes it).
_render_global_flags() {
  local gf
  if [[ -f "$_CLIFT_GLOBALS_JSON" ]]; then
    gf="$(<"$_CLIFT_GLOBALS_JSON")"
  else
    gf='[]'
  fi
  if [[ -n "$gf" && "$gf" != "[]" && "$gf" != "null" ]]; then
    echo "Global Flags:"
    clift_render_flags "$gf"
    echo ""
  fi
}

# Helper: render the --task:* passthrough section. These flags are consumed
# by the wrapper and forwarded to the go-task runner with the `--task:`
# prefix stripped. Kept inside the default help body (not a post-processor)
# so wrapping overrides automatically inherit the footer.
_render_task_runner_flags() {
  echo "Task runner flags (passthrough):"
  printf '  %-24s  %s\n' "--task:watch"           "Re-run on file changes (go-task --watch)"
  printf '  %-24s  %s\n' "--task:dry"             "Print tasks without executing (go-task --dry)"
  printf '  %-24s  %s\n' "--task:parallel"        "Run deps in parallel (go-task --parallel)"
  printf '  %-24s  %s\n' "--task:status"          "Check status and exit (go-task --status)"
  printf '  %-24s  %s\n' "--task:summary"         "Show task summary (go-task --summary)"
  printf '  %-24s  %s\n' "--task:list"            "List go-task tasks (go-task --list)"
  printf '  %-24s  %s\n' "--task:list-all"        "List all go-task tasks (go-task --list-all)"
  printf '  %-24s  %s\n' "--task:force"           "Force-run even when up-to-date (go-task --force)"
  printf '  %-24s  %s\n' "--task:silent"          "Suppress task announcements (go-task --silent)"
  printf '  %-24s  %s\n' "--task:interval <dur>"  "Watch poll interval (go-task --interval)"
  printf '  %-24s  %s\n' "--task:concurrency <n>" "Max parallel tasks (go-task --concurrency)"
  echo ""
}

# Default implementation — rendered when no override is defined, or invoked
# as the `$1` callback by a wrapping override.
_clift_help_list_default() {
  local cli_dir="${1:-$CLI_DIR}"
  local taskfile_dir="$cli_dir"
  local tasks_cache="${taskfile_dir}/.clift/tasks.json"
  local index_cache="${taskfile_dir}/.clift/index.json"
  local taskfile_path="${taskfile_dir}/Taskfile.yaml"

  echo "${CLI_NAME} - version ${CLI_VERSION}"

  local json
  if [[ -f "$tasks_cache" ]]; then
    json="$(<"$tasks_cache")"
  else
    json=$(task --list-all --json --nested --taskfile "$taskfile_path" 2>/dev/null) || {
      echo "error: failed to read task list" >&2
      return 1
    }
  fi

  # Load hidden-command map from index.json so we can filter commands marked
  # with `vars.HIDDEN: true`. Missing index is treated as "nothing hidden".
  local hidden_map='{}'
  if [[ -f "$index_cache" ]]; then
    hidden_map="$(jq -c '.tasks // {} | with_entries(.value = (.value.hidden // false))' "$index_cache" 2>/dev/null || echo '{}')"
  fi

  # Load alias map keyed by display name (canonical with `:default` stripped
  # and the namespace prefix dropped from each alias). Task 5.1: aliases of
  # included commands are namespaced by go-task (e.g. `deploy:d`); the user
  # invokes them as bare `d`, so the displayed list strips the same prefix.
  # Bare-namespace aliases (e.g. `deploy` for `deploy:default`) and aliases
  # that still contain `:` after stripping are dropped — the former is the
  # canonical name itself, the latter is unreachable via the wrapper's
  # first-token-only substitution.
  local aliases_map='{}'
  if [[ -f "$index_cache" ]]; then
    aliases_map="$(jq -c '
      .tasks // {}
      | to_entries
      | map(
          (.key | sub(":default$"; "")) as $disp
          | (.key | capture("^(?<ns>.*):[^:]+$").ns // "") as $ns
          | (((.value.aliases // [])
              | map(
                  if $ns == "" then .
                  elif startswith($ns + ":") then ltrimstr($ns + ":")
                  else . end
                )
              | map(select(. != "" and (contains(":") | not) and . != $disp))
            )) as $cleaned
          | select(($cleaned | length) > 0)
          | {key: $disp, value: $cleaned}
        )
      | from_entries
    ' "$index_cache" 2>/dev/null || echo '{}')"
  fi

  # Flatten into group<TAB>display_name<TAB>desc lines (one row per top-level
  # command). Root tasks emit directly. Namespaces collapse into a single row:
  # desc comes from the namespace's `default` task, else the first task, else
  # "(group)" as a last resort. A root task's `vars.group` can override which
  # section it appears under; namespaces always fall under "Commands".
  local all_entries
  all_entries=$(echo "$json" | jq -r \
      --argjson hidden "$hidden_map" \
      --argjson aliases "$aliases_map" '
    # A command is hidden if EITHER its bare name OR its "<name>:default" key is
    # marked hidden:true in index.json. Root-level single tasks use the bare key;
    # namespaced groups with a default subtask use "<ns>:default".
    def is_hidden($disp):
      ($hidden[$disp] // false) or ($hidden[$disp + ":default"] // false);

    # Append `, alias1, alias2` to the display name when the command has any
    # aliases. Mirrors cobra/Click conventions and matches what `--help` for
    # individual commands shows. Aliases come from index.json via $aliases.
    def with_aliases($disp):
      ($aliases[$disp] // []) as $a
      | if ($a | length) > 0 then ($disp + ", " + ($a | join(", "))) else $disp end;

    (
      (.tasks // [])[]
      | select(.name != "default")
      | select(.name | startswith("_") | not)
      | {
          name: .name,
          desc: (.desc // ""),
          group_var: (
            if (.vars.group | type) == "object" then (.vars.group.value // "")
            else (.vars.group // "")
            end | tostring
          )
        }
      | .display_name = (.name | gsub(":default$"; ""))
      | select(.display_name != "")
      | select(is_hidden(.display_name) | not)
      | .group = (
          if (.group_var != "" and .group_var != "null") then .group_var
          else "Commands"
          end
        )
      | "\(.group)\t\(with_aliases(.display_name))\t\(.desc)"
    ),
    (
      (.namespaces // {}) | to_entries[]
      | select(.key | startswith("_") | not)
      | .key as $ns
      | select(is_hidden($ns) | not)
      | (
          [ (.value.tasks // [])[]
            | select(.name | test(":[_]") | not)
          ] as $all
          | ($all | map(select(.name == ($ns + ":default"))) | first) as $def
          | ($all | map(select(.name != ($ns + ":default"))) | first) as $fallback
          | ($def // $fallback) as $pick
          | if $pick == null then empty
            else
              (($pick.desc // "") | if . == "" then "(group)" else . end) as $desc
              | "Commands\t\(with_aliases($ns))\t\($desc)"
            end
        )
    )
  ')

  if [[ -z "$all_entries" ]]; then
    echo ""
    echo "  (no commands found)"
    echo ""
    _render_global_flags
    _render_task_runner_flags
    if [[ "${CLIFT_MODE:-task}" == "standard" ]]; then
      echo "Run '${CLI_NAME} <command> --help' for details on a command."
    else
      echo "Run '${CLI_NAME} <command>:help' for details on a command."
    fi
    return 0
  fi

  # Build sorted unique group list with "Commands" first
  local groups ordered_groups=""
  groups=$(echo "$all_entries" | cut -f1 | sort -u)
  if echo "$groups" | grep -qx "Commands"; then
    ordered_groups="Commands"
  fi
  local g
  while IFS= read -r g; do
    [[ "$g" == "Commands" ]] && continue
    if [[ -z "$ordered_groups" ]]; then
      ordered_groups="$g"
    else
      ordered_groups="${ordered_groups}"$'\n'"$g"
    fi
  done <<< "$groups"

  # Print each group with header and aligned columns
  local first_group=true
  local group group_entries
  while IFS= read -r group; do
    [[ -z "$group" ]] && continue

    group_entries=$(echo "$all_entries" \
      | awk -F'\t' -v g="$group" '$1 == g { print $2 "\t" $3 }' \
      | sort -t$'\t' -k1,1)

    if $first_group; then
      echo ""
      first_group=false
    fi
    echo "${group}:"
    echo "$group_entries" | column -t -s $'\t' | sed 's/^/  /'
    echo ""
  done <<< "$ordered_groups"

  _render_global_flags
  _render_task_runner_flags

  if [[ "${CLIFT_MODE:-task}" == "standard" ]]; then
    echo "Run '${CLI_NAME} <command> --help' for details on a command."
  else
    echo "Run '${CLI_NAME} <command>:help' for details on a command."
  fi
}

_LIB_DIR="${_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../log/log.sh
source "${_LIB_DIR}/log/log.sh"
# shellcheck source=../runtime/overrides.sh
source "${_LIB_DIR}/runtime/overrides.sh"

clift_call_override help_list _clift_help_list_default "$CLI_DIR"
