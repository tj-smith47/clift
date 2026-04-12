#!/usr/bin/env bash
# Renders the CLI help listing with grouped commands.
# Uses --nested for structured namespace data.
# Usage: list.sh <TASKFILE_PATH>
# Reads CLI_NAME, CLI_VERSION from environment.

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

echo "${CLI_NAME} - version ${CLI_VERSION}"

# Get task list as nested JSON (namespaces are separate from root tasks)
TASKFILE_DIR="$(dirname "$TASKFILE_PATH")"
TASKS_CACHE="${TASKFILE_DIR}/.clift/tasks.json"

if [[ -f "$TASKS_CACHE" ]]; then
  json="$(cat "$TASKS_CACHE")"
else
  json=$(task --list-all --json --nested --taskfile "$TASKFILE_PATH" 2>/dev/null) || {
    echo "error: failed to read task list" >&2
    exit 1
  }
fi

# Flatten nested JSON into group<TAB>display_name<TAB>desc lines.
# Root tasks → "Commands" group (unless they have a vars.group override).
# Namespaced tasks → title-cased namespace group.
# Filter out _-prefixed namespaces (framework internals) and "default" task.
all_entries=$(echo "$json" | jq -r '
  # Root tasks
  (
    (.tasks // [])[]
    | select(.name != "default")
    | select(.name | startswith("_") | not)
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
    | .display_name = (.name | gsub(":default$"; ""))
    | select(.display_name != "")
    | .group = (
        if (.group_var != "" and .group_var != "null") then .group_var
        else "Commands"
        end
      )
    | "\(.group)\t\(.display_name)\t\(.desc)"
  ),
  # Namespaced tasks
  (
    (.namespaces // {}) | to_entries[]
    | select(.key | startswith("_") | not)
    | .key as $ns
    | (.value.tasks // [])[]
    | select(.name | test(":[_]") | not)
    | select(.name != ($ns + ":default"))
    | {
        name: .name,
        desc: (.desc // ""),
        location: (.location.taskfile // ""),
        ns: $ns,
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
        else (.ns | sub("^."; (.[:1] | ascii_upcase)))
        end
      )
    | "\(.group)\t\(.display_name)\t\(.desc)"
  )
')

# Helper: render Global Flags section from root Taskfile vars.FLAGS
_render_global_flags() {
  local gf
  gf="$(cat "${FRAMEWORK_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/lib/flags/globals.json" 2>/dev/null || echo '[]')"
  if [[ -n "$gf" && "$gf" != "[]" && "$gf" != "null" ]]; then
    echo "Global Flags:"
    clift_render_flags "$gf"
    echo ""
  fi
}

if [[ -z "$all_entries" ]]; then
  echo ""
  echo "  (no commands found)"
  echo ""
  _render_global_flags
  echo "Run '${CLI_NAME} <command>:help' for details on a command."
  exit 0
fi

# Build sorted unique group list with "Commands" first
groups=$(echo "$all_entries" | cut -f1 | sort -u)
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

echo "Run '${CLI_NAME} <command>:help' for details on a command."
