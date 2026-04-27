#!/usr/bin/env bash
# File-backed TTL cache. Per-profile: <profile>/cache/<key>.json.
# Atomic writes via temp+mv. Honors JARVIS_FAKE_NOW for tests.
#
# Contract:
#   cache_get <profile> <key> <ttl_sec>
#     - exits 0 + prints content if file exists and now-mtime < ttl_sec
#     - exits 1 if missing, stale, or ttl == 0
#   cache_put <profile> <key> <content>
#     - writes atomically (temp + mv), creates dirs as needed
#
# JARVIS_FAKE_NOW (UTC ISO, e.g. 2026-04-27T12:00:00Z) overrides "now"
# for deterministic test runs. Unset -> date +%s is the source of truth.

set -euo pipefail

# shellcheck disable=SC2317
if [[ -n "${_JARVIS_CACHE_FILE_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
_JARVIS_CACHE_FILE_LOADED=1

_cache_now_epoch() {
  if [[ -n "${JARVIS_FAKE_NOW:-}" ]]; then
    date -u -d "$JARVIS_FAKE_NOW" +%s 2>/dev/null \
      || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$JARVIS_FAKE_NOW" +%s
  else
    date -u +%s
  fi
}

_cache_path() {
  local profile="$1" key="$2"
  local home="${JARVIS_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/jarvis}"
  printf '%s/%s/cache/%s.json\n' "$home" "$profile" "$key"
}

_cache_mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"
}

cache_get() {
  local profile="$1" key="$2" ttl="$3"
  local f
  f="$(_cache_path "$profile" "$key")"
  [[ -f "$f" ]] || return 1
  if (( ttl == 0 )); then
    return 1
  fi
  local mtime now
  mtime="$(_cache_mtime "$f")"
  now="$(_cache_now_epoch)"
  if (( now - mtime >= ttl )); then
    return 1
  fi
  printf '%s' "$(<"$f")"
}

cache_put() {
  local profile="$1" key="$2" content="$3"
  local f tmp
  f="$(_cache_path "$profile" "$key")"
  tmp="${f}.tmp.$$"
  mkdir -p "$(dirname "$f")"
  printf '%s' "$content" > "$tmp"
  mv -f "$tmp" "$f"
}
