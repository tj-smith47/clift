#!/usr/bin/env bash
# Renders detailed help for a single command.
# Usage: detail.sh <COMMAND_NAME> <TASKFILE_PATH>

set -euo pipefail

COMMAND="${1:-}"
TASKFILE_PATH="${2:-}"

if [[ -z "$COMMAND" || -z "$TASKFILE_PATH" ]]; then
  echo "error: detail.sh requires command name and taskfile path" >&2
  exit 1
fi

CLI_NAME="${CLI_NAME:-mycli}"

# The task to look up is "<command>:default" or just "<command>"
json=$(task --list-all --json --taskfile "$TASKFILE_PATH" 2>/dev/null) || {
  echo "error: failed to read task list" >&2
  exit 1
}

# Try <command>:default first, then <command> (single jq pass)
task_info=$(echo "$json" | jq -r --arg cmd "$COMMAND" '
  [.tasks[] | select(.name == ($cmd + ":default") or .name == $cmd)]
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
