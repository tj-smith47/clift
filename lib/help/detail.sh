#!/usr/bin/env bash
# Renders detailed help for a single command.
# Usage: detail.sh <COMMAND_NAME> <TASKFILE_PATH>

set -euo pipefail

# shellcheck source=render_flags.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/render_flags.sh"

COMMAND="${1:-}"
TASKFILE_PATH="${2:-}"

if [[ -z "$COMMAND" || -z "$TASKFILE_PATH" ]]; then
  echo "error: detail.sh requires command name and taskfile path" >&2
  exit 1
fi

CLI_NAME="${CLI_NAME:-mycli}"

# The task to look up is "<command>:default" or just "<command>"
TASKFILE_DIR="$(dirname "$TASKFILE_PATH")"
TASKS_CACHE="${TASKFILE_DIR}/.clift/tasks.json"

if [[ -f "$TASKS_CACHE" ]]; then
  json="$(cat "$TASKS_CACHE")"
else
  json=$(task --list-all --json --taskfile "$TASKFILE_PATH" 2>/dev/null) || {
    echo "error: failed to read task list" >&2
    exit 1
  }
fi

# Try <command>:default first, then <command> (single jq pass)
task_info=$(echo "$json" | jq -r --arg cmd "$COMMAND" '
  [.. | .tasks? // empty | .[] | select(.name == ($cmd + ":default") or .name == $cmd)]
  | sort_by(if .name | endswith(":default") then 0 else 1 end)
  | first
  | {desc, summary, location: .location.taskfile}
' 2>/dev/null)

if [[ -z "$task_info" || "$task_info" == "null" ]]; then
  echo "error: unknown command: $COMMAND" >&2
  exit 1
fi

desc=$(echo "$task_info" | jq -r '.desc // ""')
summary=$(echo "$task_info" | jq -r '.summary // ""')
location=$(echo "$task_info" | jq -r '.location // ""')

# Apply colon-to-space display heuristic for user commands (those under /cmds/)
display_name="$COMMAND"
if [[ "$location" == *"/cmds/"* ]]; then
  display_name="${COMMAND//:/ }"
fi

echo "${CLI_NAME} ${display_name} - ${desc}"
echo ""

if [[ -n "$summary" && "$summary" != "null" ]]; then
  echo "$summary"
else
  echo "No detailed help available for '${COMMAND}'."
fi

# Render flag sections from precompiled .clift/flags.json
FLAGS_JSON="${TASKFILE_DIR}/.clift/flags.json"

if [[ -f "$FLAGS_JSON" ]]; then
  # Look up this command's merged flags. Try "cmd:default" first, then "cmd".
  cmd_flags="$(jq -r --arg cmd "${COMMAND}:default" --arg cmd2 "$COMMAND" '
    .[$cmd] // .[$cmd2] // null
  ' "$FLAGS_JSON")"

  if [[ -n "$cmd_flags" && "$cmd_flags" != "null" && "$cmd_flags" != '{"legacy":true}' ]]; then
    # Load root globals to split local vs global flags
    root_globals="$(cat "${FRAMEWORK_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/lib/flags/globals.json" 2>/dev/null || echo '[]')"
    root_names="$(echo "$root_globals" | jq -r '.[].name' 2>/dev/null)"

    # Split into local flags (not in root globals) and global flags (in root globals)
    local_flags="$(echo "$cmd_flags" | jq -r --argjson globals "$root_globals" '
      [.[] | select(.name as $n | [$globals[].name] | index($n) | not)]
    ')"
    global_flags="$(echo "$cmd_flags" | jq -r --argjson globals "$root_globals" '
      [.[] | select(.name as $n | [$globals[].name] | index($n))]
    ')"

    if [[ "$(echo "$local_flags" | jq 'length')" -gt 0 ]]; then
      echo ""
      echo "Flags:"
      clift_render_flags "$local_flags"
    fi

    if [[ "$(echo "$global_flags" | jq 'length')" -gt 0 ]]; then
      echo ""
      echo "Global Flags:"
      clift_render_flags "$global_flags"
    fi
  fi
fi
