#!/usr/bin/env bash
# clift rc-file helpers — shared sentinel-based alias / PATH management.
# Sentinel format: a comment line `# clift: <name>` immediately followed by
# exactly one entry line. Scrubbing removes both; writing replaces both.

# shellcheck disable=SC2317  # `exit 0` fallback fires only if file is run directly
if [[ -n "${_CLIFT_RC_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
_CLIFT_RC_LOADED=1

_clift_rc_sentinel() {
  echo "# clift: $1"
}

clift_rc_scrub() {
  local rc_file="$1" name="$2"
  [[ -f "$rc_file" ]] || return 0
  local sentinel
  sentinel="$(_clift_rc_sentinel "$name")"
  local tmp
  tmp="$(mktemp)"
  if ! awk -v s="$sentinel" '
    skip > 0 { skip--; next }
    $0 == s  { skip = 1; next }
    { print }
  ' "$rc_file" > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  if ! chmod "$(stat -c '%a' "$rc_file" 2>/dev/null || stat -f '%Lp' "$rc_file" 2>/dev/null || echo 644)" "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  mv "$tmp" "$rc_file"
}

clift_rc_write() {
  local rc_file="$1" name="$2" entry="$3"
  clift_rc_scrub "$rc_file" "$name"
  # Only add blank line if file doesn't already end with one
  if [[ -s "$rc_file" ]] && [[ "$(tail -c1 "$rc_file")" != "" ]]; then
    echo "" >> "$rc_file"
  fi
  _clift_rc_sentinel "$name" >> "$rc_file"
  printf '%s\n' "$entry" >> "$rc_file"
}
