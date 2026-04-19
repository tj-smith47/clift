#!/usr/bin/env bash
# Atomic JSON read/write, flock-guarded.
# Writes validate via jq before rename; failures leave existing file intact.

# shellcheck disable=SC2317
if [[ -n "${_JARVIS_STATE_JSON_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
_JARVIS_STATE_JSON_LOADED=1

# state_json_write <path> <json-string>
# Validates via jq, writes to <path>.tmp, renames under flock.
state_json_write() {
  local target="$1"
  local payload="$2"
  local tmp="${target}.tmp.$$"

  if ! jq -e . <<< "$payload" > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    return 2
  fi

  state_with_lock "$target" "mv -f '$tmp' '$target'"
}

# state_json_read <path>
# Prints file contents (shared lock); exits 1 if missing.
state_json_read() {
  local target="$1"
  [[ -f "$target" ]] || return 1
  state_with_lock "$target" "cat '$target'"
}
