#!/usr/bin/env bash
# Renders detailed help for a single command.
# Usage: detail.sh <COMMAND_NAME> <TASKFILE_PATH>
#
# Overridable via the `help_detail` slot. Per-command overrides at
# cmds/<cmd-seg>/overrides/help_detail.sh take precedence over the CLI-global
# .clift/overrides/help_detail.sh. See docs/cli/overrides.md.

set -euo pipefail

# shellcheck source=render_flags.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/render_flags.sh"

# Shared alias-filter jq defs — consumed by the tasks.json fallback below.
# Canonical home is lib/flags/ because compile.sh owns alias preparation;
# detail.sh re-uses the same predicate when rendering aliases for
# framework-lib commands whose entries don't live in index.json.
# shellcheck source=../flags/alias_filter.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/flags/alias_filter.sh"

COMMAND="${1:-}"
TASKFILE_PATH="${2:-}"

if [[ -z "$COMMAND" || -z "$TASKFILE_PATH" ]]; then
  echo "error: detail.sh requires command name and taskfile path" >&2
  exit 1
fi

CLI_NAME="${CLI_NAME:-mycli}"
TASKFILE_DIR="$(dirname "$TASKFILE_PATH")"
# CLI_DIR may already be exported by the caller (router / wrapper). Fall back
# to TASKFILE_DIR so direct invocations still work — the override loader
# needs CLI_DIR set to resolve per-command / CLI-global overrides.
CLI_DIR="${CLI_DIR:-$TASKFILE_DIR}"
export CLI_DIR

_clift_help_detail_default() {
  local command="$1"
  local cli_dir="${2:-$CLI_DIR}"
  local taskfile_dir="$cli_dir"
  local tasks_cache="${taskfile_dir}/.clift/tasks.json"
  local taskfile_path="${taskfile_dir}/Taskfile.yaml"

  local json
  if [[ -f "$tasks_cache" ]]; then
    json="$(<"$tasks_cache")"
  else
    json=$(task --list-all --json --taskfile "$taskfile_path" 2>/dev/null) || {
      echo "error: failed to read task list" >&2
      return 1
    }
  fi

  # Try <command>:default first, then <command> (single jq pass)
  local task_info
  task_info=$(echo "$json" | jq -c --arg cmd "$command" '
    [.. | .tasks? // empty | .[] | select(.name == ($cmd + ":default") or .name == $cmd)]
    | sort_by(if .name | endswith(":default") then 0 else 1 end)
    | if length == 0 then null
      else first | {desc, summary, location: .location.taskfile}
      end
  ' 2>/dev/null)

  if [[ -z "$task_info" || "$task_info" == "null" ]]; then
    echo "error: unknown command: $command" >&2
    return 1
  fi

  local desc summary location
  {
    IFS= read -r -d '' desc || true
    IFS= read -r -d '' summary || true
    IFS= read -r -d '' location || true
  } < <(echo "$task_info" | jq -j '(.desc // "") + "\u0000" + (.summary // "") + "\u0000" + (.location // "") + "\u0000"')

  # Apply colon-to-space display heuristic for user commands (those under /cmds/)
  local display_name="$command"
  if [[ "$location" == *"/cmds/"* ]]; then
    display_name="${command//:/ }"
  fi

  echo "${CLI_NAME} ${display_name} - ${desc}"

  # Task 5.1: surface command aliases directly under the title. compile.sh
  # precomputes each USER task entry's user-facing alias list as
  # `user_aliases` (already filtered and stripped) so we just need to find
  # the right index.json key — `<cmd>:default` for namespaced commands with
  # a default task, falling back to the bare name for root-level tasks.
  #
  # Task 6.3: framework-lib tasks (config:*, update, etc.) are intentionally
  # skipped by compile.sh, so their aliases never reach index.json. Fall
  # back to tasks.json (authoritative for framework cmds) and apply the
  # same namespace-strip + drop-empty / drop-nested / drop-self-referential
  # filters compile.sh uses. This keeps the detail page's Aliases: line
  # accurate for every command the wrapper can dispatch.
  local index_json_path="${taskfile_dir}/.clift/index.json"
  local tasks_json_path="${taskfile_dir}/.clift/tasks.json"
  local aliases_csv=""
  if [[ -f "$index_json_path" ]]; then
    aliases_csv="$(jq -r \
      --arg cmd "${command}:default" \
      --arg cmd2 "$command" '
      (.tasks[$cmd].user_aliases // .tasks[$cmd2].user_aliases // [])
      | join(", ")
    ' "$index_json_path" 2>/dev/null)"
  fi
  if [[ -z "$aliases_csv" ]] && [[ -f "$tasks_json_path" ]]; then
    # Uses strip_ns + is_user_surfaceable_alias from alias_filter.sh. The
    # shadow-by-top-level-command drop that compile.sh's user_aliases pass
    # applies on top is intentionally NOT mirrored here: framework-lib
    # commands (the only consumers of this fallback) are curated so
    # shadow collisions don't arise in practice, and we don't have
    # `$cmd_segs` handy at this layer.
    aliases_csv="$(jq -r \
      --arg cmd "${command}:default" \
      --arg cmd2 "$command" \
      "$CLIFT_ALIAS_FILTER_JQ_DEFS"'
      [.. | .tasks? // empty | .[]
        | select(.name == $cmd or .name == $cmd2)
        | (.name | sub(":default$"; "")) as $disp
        | (.name | capture("^(?<ns>.*):[^:]+$").ns // "") as $ns
        | (.aliases // [])[]
        | strip_ns($ns; .) as $a
        | select(is_user_surfaceable_alias($a; $disp))
        | $a
      ] | unique | join(", ")
    ' "$tasks_json_path" 2>/dev/null)"
  fi
  if [[ -n "$aliases_csv" ]]; then
    echo "Aliases: $aliases_csv"
  fi

  echo ""

  if [[ -n "$summary" && "$summary" != "null" ]]; then
    echo "$summary"
  else
    echo "No detailed help available for '${command}'."
  fi

  # List subcommands if this command has children (e.g. deploy has deploy:prod)
  local subcmds
  subcmds="$(echo "$json" | jq -r --arg cmd "$command" '
    [.. | .tasks? // empty | .[]
     | select(.name | startswith($cmd + ":"))
     | select(.name != ($cmd + ":default"))
     | select(.name | test(":[_]") | not)
     | {
         display: (
           if (.location.taskfile // "" | contains("/cmds/")) then
             (.name | gsub(":"; " "))
           else .name end
         ),
         desc: (.desc // "")
       }
    ] | unique_by(.display) | sort_by(.display)
    | .[] | "\(.display)\t\(.desc)"
  ' 2>/dev/null)"

  if [[ -n "$subcmds" ]]; then
    echo ""
    echo "Available commands:"
    echo "$subcmds" | column -t -s $'\t' | sed 's/^/  /'
    echo ""
    echo "Run '${CLI_NAME} ${display_name} <command> --help' for more information."
  fi

  # Render flag sections from precompiled .clift/index.json (tasks[k].flags)
  local index_json="${taskfile_dir}/.clift/index.json"

  if [[ -f "$index_json" ]]; then
    # Look up this command's merged flags. Try "cmd:default" first, then "cmd".
    local cmd_flags
    cmd_flags="$(jq -c --arg cmd "${command}:default" --arg cmd2 "$command" '
      .tasks[$cmd].flags // .tasks[$cmd2].flags // null
    ' "$index_json")"

    if [[ -n "$cmd_flags" && "$cmd_flags" != "null" && "$cmd_flags" != '{"passthrough":true}' ]]; then
      # Load root globals to split local vs global flags
      local root_globals local_flags global_flags
      if [[ -f "$_CLIFT_GLOBALS_JSON" ]]; then
        root_globals="$(<"$_CLIFT_GLOBALS_JSON")"
      else
        root_globals='[]'
      fi
      # Merge globals.json into the command's flag list before rendering, then
      # split into local vs global. Mirrors the router's runtime merge (see
      # router.sh step 5) so pre-4.1 CLIs that scaffolded before --no-cache
      # was added to globals.json still see the new flag in `<cmd> --help`
      # without re-running setup. Dedupe on `.name` so CLIs whose root
      # Taskfile DID declare the flag don't show it twice.
      {
        IFS=$'\t' read -r local_flags global_flags
      } < <(echo "$cmd_flags" | jq -r --argjson globals "$root_globals" '
        . as $cmd
        | ($globals | map(.name)) as $gnames
        | ($cmd | map(.name)) as $cnames
        | ($cmd + ($globals | map(select(.name as $n | $cnames | index($n) | not))))
          as $merged
        | ([$merged[] | select(.name as $n | $gnames | index($n) | not)] | tojson) + "\t" +
          ([$merged[] | select(.name as $n | $gnames | index($n))] | tojson)
      ')

      if [[ "$local_flags" != "[]" ]]; then
        echo ""
        echo "Flags:"
        clift_render_flags "$local_flags"
      fi

      if [[ "$global_flags" != "[]" ]]; then
        echo ""
        echo "Global Flags:"
        clift_render_flags "$global_flags"
      fi
    fi
  fi
}

_LIB_DIR="${_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../log/log.sh
source "${_LIB_DIR}/log/log.sh"
# shellcheck source=../runtime/overrides.sh
source "${_LIB_DIR}/runtime/overrides.sh"

clift_call_override help_detail _clift_help_detail_default --task "$COMMAND" "$COMMAND" "$CLI_DIR"
