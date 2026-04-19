#!/usr/bin/env bash
# State profile resolver.
# Reads JARVIS_HOME (default $XDG_DATA_HOME/jarvis or ~/.local/share/jarvis)
# and JARVIS_PROFILE (default 'default'), emits the resolved state dir.

# shellcheck disable=SC2317
if [[ -n "${_JARVIS_STATE_PROFILE_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
_JARVIS_STATE_PROFILE_LOADED=1

state_profile_dir() {
  local home="${JARVIS_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/jarvis}"
  local profile="${JARVIS_PROFILE:-default}"
  printf '%s/%s\n' "$home" "$profile"
}

state_ensure_tree() {
  local dir
  dir="$(state_profile_dir)"
  mkdir -p \
    "$dir/tasks" \
    "$dir/reminders" \
    "$dir/cache" \
    "$dir/notes/inbox" \
    "$dir/notes/daily" \
    "$dir/notes/meetings" \
    "$dir/notes/ref" \
    "$dir/notes/archive" \
    "$dir/notes/templates"
  if [[ ! -f "$dir/state.version" ]]; then
    printf '1\n' > "$dir/state.version"
  fi
}
