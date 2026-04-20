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
# Tmp name mixes $$, $BASHPID, and $RANDOM so concurrent writers from the
# same parent shell (subshells share $$) don't collide on a single tmp path.
state_json_write() {
  local target="$1"
  local payload="$2"
  local tmp="${target}.tmp.$$.$BASHPID.$RANDOM"

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

# state_json_mutate <path> <jq-filter>
# Atomic read → apply jq filter → write, all inside one flock window. The
# filter is passed to jq via a tmp file (--from-file) so arbitrary shell
# metacharacters in the filter are safe. Filter errors, missing file, or
# rename failures → non-zero exit; target is left untouched.
state_json_mutate() {
  local target="$1"
  local filter="$2"
  [[ -f "$target" ]] || return 1

  local tmp="${target}.tmp.$$.$BASHPID.$RANDOM"
  local filter_file="${target}.filter.$$.$BASHPID.$RANDOM"
  printf '%s' "$filter" > "$filter_file"

  local status=0
  state_with_lock "$target" "
    if jq --from-file '$filter_file' '$target' > '$tmp' 2>/dev/null; then
      mv -f '$tmp' '$target'
    else
      rm -f '$tmp'
      exit 2
    fi
  " || status=$?
  rm -f "$filter_file"
  return "$status"
}
