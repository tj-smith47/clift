#!/usr/bin/env bash
# clift Cache Utilities — portable mtime + staleness check.
# Sourced by compile.sh, router.sh, wrapper.sh.

if [[ -n "${_CLIFT_CACHE_LOADED:-}" ]]; then return 0; fi
_CLIFT_CACHE_LOADED=1

# Portable max-mtime across a list of files.
# Works on Linux (GNU stat -c) and macOS (BSD stat -f).
# Prints a single integer (epoch seconds) to stdout.
# Silently ignores non-existent paths (glob no-match).
clift_max_mtime() {
  local max=0
  for f in "$@"; do
    [[ -f "$f" ]] || continue
    local mt
    # GNU stat: -c '%Y' prints mtime as epoch seconds
    # BSD stat: -f '%m' prints mtime as epoch seconds
    if mt="$(stat -c '%Y' "$f" 2>/dev/null)" || mt="$(stat -f '%m' "$f" 2>/dev/null)"; then
      (( mt > max )) && max=$mt
    fi
  done
  echo "$max"
}

# Ensure the .clift/ cache is fresh. Rebuilds if checksum differs or is missing.
# Usage: clift_ensure_cache <CLI_DIR> <FRAMEWORK_DIR>
clift_ensure_cache() {
  local cli_dir="$1" fw_dir="$2"
  local cache_dir="$cli_dir/.clift"
  local checksum_file="$cache_dir/checksum"

  local current
  current="$(clift_max_mtime "$cli_dir/Taskfile.yaml" "$cli_dir"/cmds/*/Taskfile.yaml)"

  if [[ ! -f "$checksum_file" ]] || [[ "$(cat "$checksum_file")" != "$current" ]]; then
    bash "$fw_dir/lib/flags/compile.sh" "$cli_dir" >&2
  fi
}
