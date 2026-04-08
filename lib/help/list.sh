#!/usr/bin/env bash
# Renders the CLI help listing.
# Usage: list.sh <TASKFILE_PATH>
# Reads CLI_NAME, CLI_VERSION from environment.

set -euo pipefail

TASKFILE_PATH="${1:-}"

if [[ -z "$TASKFILE_PATH" ]]; then
  echo "error: list.sh requires taskfile path as argument" >&2
  exit 1
fi

CLI_NAME="${CLI_NAME:-mycli}"
CLI_VERSION="${CLI_VERSION:-0.0.0}"

echo "${CLI_NAME} - version ${CLI_VERSION}"
echo ""
echo "Commands:"

# Get task list as JSON
json=$(task --list-all --json --taskfile "$TASKFILE_PATH" 2>/dev/null) || {
  echo "error: failed to read task list" >&2
  exit 1
}

# Parse and format with jq
# Filter out:
#   - Tasks in _-prefixed namespaces (framework internals)
#   - The root "default" task
echo "$json" | jq -r '
  .tasks[]
  | select(.name != "default")
  | select(.name | startswith("_") | not)
  | select(.name | test(":[_]") | not)
  | {
      name: .name,
      desc: (.desc // ""),
      location: (.location.taskfile // "")
    }
  | .display_name = (
      if (.location | contains("/cmds/")) then
        (.name | gsub(":default$"; "") | gsub(":"; " "))
      else
        (.name | gsub(":default$"; ""))
      end
    )
  | select(.display_name != "")
  | "\(.display_name)\t\(.desc)"
' | column -t -s $'\t' | sed 's/^/  /'

echo ""
echo "Run '${CLI_NAME} <command>:help' for details on a command."
