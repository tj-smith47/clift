#!/usr/bin/env bash
# clift rc-file helpers — shared sentinel-based alias / PATH management.
# Sentinel format: a comment line `# clift: <name>` immediately followed by
# exactly one entry line. Scrubbing removes both; writing replaces both.

if [[ -n "${_CLIFT_RC_LOADED:-}" ]]; then return 0; fi
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
  awk -v s="$sentinel" '
    skip > 0 { skip--; next }
    $0 == s  { skip = 1; next }
    { print }
  ' "$rc_file" > "$tmp"
  mv "$tmp" "$rc_file"
}

clift_rc_write() {
  local rc_file="$1" name="$2" entry="$3"
  clift_rc_scrub "$rc_file" "$name"
  {
    echo ""
    _clift_rc_sentinel "$name"
    printf '%s\n' "$entry"
  } >> "$rc_file"
}
