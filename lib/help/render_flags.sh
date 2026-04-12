#!/usr/bin/env bash
# Renders a JSON flag array into formatted terminal output.
# Sourced by list.sh and detail.sh.
# Usage: source render_flags.sh; clift_render_flags <flags_json>

if [[ -n "${_CLIFT_RENDER_FLAGS_LOADED:-}" ]]; then return 0; fi
_CLIFT_RENDER_FLAGS_LOADED=1

# Renders a JSON array of flag objects into aligned columns on stdout.
# Each flag gets: short, long, type hint, description, default/required.
clift_render_flags() {
  local flags_json="$1"
  echo "$flags_json" | jq -r '
    .[] |
    (if .short then "-\(.short), " else "    " end) +
    "--\(.name)" +
    (if .type and .type != "bool" then "=<\(.type)>" else "" end) +
    "\t" +
    (.desc // "") +
    (if .required == true then " (required)" elif .default then " (default: \(.default))" else "" end)
  ' | column -t -s $'\t' | sed 's/^/  /'
}
