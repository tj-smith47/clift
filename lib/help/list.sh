#!/usr/bin/env bash
# Renders the CLI help listing with grouped commands.
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

# Get task list as JSON
json=$(task --list-all --json --taskfile "$TASKFILE_PATH" 2>/dev/null) || {
  echo "error: failed to read task list" >&2
  exit 1
}

# Parse tasks into group<TAB>display_name<TAB>desc lines.
# Group priority: vars.group > namespace prefix (title-cased) > "Commands".
entries=$(echo "$json" | jq -r '
  .tasks[]
  | select(.name != "default")
  | select(.name | startswith("_") | not)
  | select(.name | test(":[_]") | not)
  | {
      name: .name,
      desc: (.desc // ""),
      location: (.location.taskfile // ""),
      group_var: (
        if (.vars.group | type) == "object" then (.vars.group.value // "")
        else (.vars.group // "")
        end | tostring
      )
    }
  | .display_name = (
      if (.location | contains("/cmds/")) then
        (.name | gsub(":default$"; "") | gsub(":"; " "))
      else
        (.name | gsub(":default$"; ""))
      end
    )
  | select(.display_name != "")
  | .group = (
      if (.group_var != "" and .group_var != "null") then .group_var
      elif (.name | contains(":")) then
        (.name | split(":")[0] | sub("^."; (.[:1] | ascii_upcase)))
      else "Commands"
      end
    )
  | "\(.group)\t\(.display_name)\t\(.desc)"
')

if [[ -z "$entries" ]]; then
  echo ""
  echo "  (no commands found)"
  echo ""
  echo "Run '${CLI_NAME} <command>:help' for details on a command."
  exit 0
fi

# Build sorted unique group list with "Commands" first
groups=$(echo "$entries" | cut -f1 | sort -u)
ordered_groups=""
if echo "$groups" | grep -qx "Commands"; then
  ordered_groups="Commands"
fi
while IFS= read -r g; do
  [[ "$g" == "Commands" ]] && continue
  if [[ -z "$ordered_groups" ]]; then
    ordered_groups="$g"
  else
    ordered_groups="${ordered_groups}"$'\n'"$g"
  fi
done <<< "$groups"

# Print each group with header and aligned columns
first_group=true
while IFS= read -r group; do
  [[ -z "$group" ]] && continue

  group_entries=$(echo "$entries" \
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

echo "Run '${CLI_NAME} <command>:help' for details on a command."
