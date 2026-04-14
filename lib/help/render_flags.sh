#!/usr/bin/env bash
# Renders a JSON flag array into formatted terminal output.
# Sourced by list.sh and detail.sh.
# Usage: source render_flags.sh; clift_render_flags <flags_json>

if [[ -n "${_CLIFT_RENDER_FLAGS_LOADED:-}" ]]; then return 0; fi
_CLIFT_RENDER_FLAGS_LOADED=1

# Resolve the path to globals.json once at source time.
_CLIFT_GLOBALS_JSON="${FRAMEWORK_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/lib/flags/globals.json"

# Format a single row of flag TSV (the inner jq pipeline). Extracted so
# ungrouped and grouped partitions share the exact same rendering.
_clift_render_flag_row() {
  jq -r '
    .[] |
    select(.hidden != true) |
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

# Renders a JSON array of flag objects into aligned columns on stdout.
# Each flag gets: short, long, type hint, description, default/required.
#
# Grouped flags (those declaring `group: <name>` with either `exclusive: true`
# or `requires: "all"`) are partitioned into named subsections, each labeled
# with the modifier. Ungrouped flags render at the top with no subheader,
# preserving the pre-groups layout exactly.
clift_render_flags() {
  local flags_json="$1"

  # Emit the ungrouped partition first (flags with no `group` field, or
  # `group: ""`). This preserves the pre-groups output verbatim when no
  # groups are declared.
  local _ungrouped
  _ungrouped="$(echo "$flags_json" | jq -c '[.[] | select((.group // "") == "")]')"
  if [[ "$_ungrouped" != "[]" ]]; then
    echo "$_ungrouped" | _clift_render_flag_row
  fi

  # Collect the distinct group names in declaration order so output is
  # stable, then render each group as its own subsection.
  local _groups
  _groups="$(echo "$flags_json" | jq -r '[.[] | (.group // "")] | map(select(. != "")) | unique | .[]')"
  [[ -z "$_groups" ]] && return 0

  local _g _subset _mode _label _first
  _first=true
  while IFS= read -r _g; do
    [[ -z "$_g" ]] && continue
    _subset="$(echo "$flags_json" | jq -c --arg g "$_g" '[.[] | select((.group // "") == $g)]')"
    # Determine the group's modifier from its members. All members share the
    # same modifier (validated at compile), so the first informs the label.
    _mode="$(echo "$_subset" | jq -r '
      [.[] | if (.exclusive == true) then "exclusive"
             elif ((.requires // "") == "all") then "requires-all"
             else empty end] | .[0] // ""
    ')"
    case "$_mode" in
      exclusive)    _label="$_g (mutually exclusive)" ;;
      requires-all) _label="$_g (required together)" ;;
      *)            _label="$_g" ;;
    esac
    # Blank line separator between sections (but not before the very first
    # group when there were no ungrouped flags above).
    if [[ "$_first" != "true" || "$_ungrouped" != "[]" ]]; then
      echo ""
    fi
    _first=false
    echo "${_label}:"
    echo "$_subset" | _clift_render_flag_row
  done <<< "$_groups"
}
