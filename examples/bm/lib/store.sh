#!/usr/bin/env bash
# bm bookmark store: NDJSON-backed CRUD over a per-profile file.
# Library — no `set -euo pipefail` (would leak to caller; conditionals
# here would abort the caller's command script).
# Row shape: {"name":..,"url":..,"description":..,"tags":[..],"added_at":..}
# Mutators write to a tempfile and `mv` — readers never see a half-write.

# shellcheck disable=SC2317
if [[ -n "${_BM_STORE_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
_BM_STORE_LOADED=1

# Resolve the active profile from CLIFT_FLAGS → CLIFT_FLAG_PROFILE →
# BM_PROFILE → "default". Exports BM_PROFILE so downstream callers (and
# the standalone-sourced completer) read the same value.
bm_resolve_profile() {
  local profile
  if declare -p CLIFT_FLAGS >/dev/null 2>&1 \
     && [[ -n "${CLIFT_FLAGS[profile]:-}" ]]; then
    profile="${CLIFT_FLAGS[profile]}"
  elif [[ -n "${CLIFT_FLAG_PROFILE:-}" ]]; then
    profile="${CLIFT_FLAG_PROFILE}"
  else
    profile="${BM_PROFILE:-default}"
  fi
  BM_PROFILE="$profile"
  export BM_PROFILE
  printf '%s\n' "$profile"
}

# Store path: ${BM_HOME:-$XDG_DATA_HOME/bm}/<profile>/store
bm_store_path() {
  local home="${BM_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/bm}"
  printf '%s/%s/store\n' "$home" "$(bm_resolve_profile)"
}

_bm_store_ensure() {
  local f; f="$(bm_store_path)"
  mkdir -p "$(dirname "$f")"
  [[ -f "$f" ]] || : > "$f"
  printf '%s' "$f"
}

# bm_store_add <url> <name> <description> [tag...] — append; refuse dup name.
bm_store_add() {
  local url="$1" name="$2" desc="$3"; shift 3
  local f; f="$(_bm_store_ensure)"
  if bm_store_get "$name" >/dev/null 2>&1; then
    printf 'bm_store_add: bookmark already exists: %s\n' "$name" >&2
    return 1
  fi
  local tags_json="[]" now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  (( $# > 0 )) && tags_json="$(printf '%s\n' "$@" | jq -R . | jq -cs .)"
  jq -cn --arg name "$name" --arg url "$url" --arg desc "$desc" \
    --arg now "$now" --argjson tags "$tags_json" \
    '{name:$name,url:$url,description:$desc,tags:$tags,added_at:$now}' >> "$f"
}

# bm_store_list — emit each row as JSON to stdout.
bm_store_list() {
  local f
  f="$(_bm_store_ensure)"
  [[ -s "$f" ]] || return 0
  cat "$f"
}

# bm_store_get <name> — emit one row's JSON or exit 1 if missing.
bm_store_get() {
  local name="$1" f row
  f="$(_bm_store_ensure)"
  row="$(jq -c --arg n "$name" 'select(.name == $n)' "$f" 2>/dev/null | head -n1)"
  [[ -n "$row" ]] || return 1
  printf '%s\n' "$row"
}

# bm_store_remove <name> — drop the matching row. Exit 1 if missing.
bm_store_remove() {
  local name="$1" f
  f="$(_bm_store_ensure)"
  bm_store_get "$name" >/dev/null 2>&1 || return 1
  local tmp="${f}.tmp.$$.$RANDOM"
  jq -c --arg n "$name" 'select(.name != $n)' "$f" > "$tmp"
  mv -f "$tmp" "$f"
}

# bm_store_tags <name> — emit tags JSON array (or exit 1).
bm_store_tags() {
  local row
  row="$(bm_store_get "$1")" || return 1
  jq -c '.tags' <<< "$row"
}

# bm_store_set_tags <name> <json-array> — replace tags (or exit 1).
bm_store_set_tags() {
  local name="$1" tags="$2" f
  f="$(_bm_store_ensure)"
  bm_store_get "$name" >/dev/null 2>&1 || return 1
  local tmp="${f}.tmp.$$.$RANDOM"
  jq -c --arg n "$name" --argjson t "$tags" \
    'if .name == $n then .tags = $t else . end' "$f" > "$tmp"
  mv -f "$tmp" "$f"
}

# Unique tags / names across the store, space-separated. Used by completers.
bm_store_all_tags() {
  local f; f="$(_bm_store_ensure)"
  [[ -s "$f" ]] || return 0
  jq -r '.tags[]' "$f" 2>/dev/null | sort -u | tr '\n' ' '
}
bm_store_all_names() {
  local f; f="$(_bm_store_ensure)"
  [[ -s "$f" ]] || return 0
  jq -r '.name' "$f" 2>/dev/null | sort -u | tr '\n' ' '
}
