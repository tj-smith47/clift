#!/usr/bin/env bash
# Renders a JSON flag array into formatted terminal output.
# Sourced by list.sh and detail.sh.
# Usage: source render_flags.sh; clift_render_flags <flags_json>

if [[ -n "${_CLIFT_RENDER_FLAGS_LOADED:-}" ]]; then return 0; fi
_CLIFT_RENDER_FLAGS_LOADED=1

# Resolve the path to globals.json once at source time.
_CLIFT_GLOBALS_JSON="${FRAMEWORK_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/lib/flags/globals.json"

# Renders a JSON array of flag objects into aligned columns on stdout.
# Each flag gets: short, long, type hint, description, default/required.
clift_render_flags() {
  local flags_json="$1"
  echo "$flags_json" | jq -r '
    .[] |
    (if .short then "-\(.short), " else "    " end) +
    "--\(.name)" +
    ((.aliases // []) | map(", --" + .) | join("")) +
    (if .type and .type != "bool" then "=<\(.type)>" else "" end) +
    "\t" +
    (.desc // "") +
    (if .required == true then " (required)" elif .default then " (default: \(.default))" else "" end) +
    (if (.deprecated // "") != "" then " (deprecated)" else "" end)
  ' | column -t -s $'\t' | sed 's/^/  /'
}
