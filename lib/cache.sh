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
  local -a files=()
  local f
  for f in "$@"; do
    [[ -f "$f" ]] && files+=("$f")
  done
  (( ${#files[@]} == 0 )) && { echo 0; return; }

  # Both GNU and BSD stat accept multiple files.
  # Detect once per shell session, batch all files in one call.
  if [[ -z "${_CLIFT_STAT_FMT:-}" ]]; then
    if stat -c '%Y' /dev/null &>/dev/null; then
      _CLIFT_STAT_FMT="gnu"
    else
      _CLIFT_STAT_FMT="bsd"
    fi
  fi
  if [[ "$_CLIFT_STAT_FMT" == "gnu" ]]; then
    stat -c '%Y' "${files[@]}" | sort -rn | head -1
  else
    stat -f '%m' "${files[@]}" | sort -rn | head -1
  fi
}

# Ensure the .clift/ cache is fresh. Rebuilds if checksum differs or is missing.
# Uses mkdir-based locking to prevent concurrent rebuilds (portable — works on
# macOS and Linux without flock).
#
# CLIFT_CACHE env var overrides:
#   unset/empty/other — default behavior (stat-based staleness check)
#   rebuild           — force compile, skip staleness check (but still honor
#                       the lock so concurrent rebuild requests serialize
#                       correctly; every explicit `rebuild` request compiles,
#                       so after-lock-acquire we skip the "another process
#                       already refreshed" shortcut)
#   bypass            — return 0 immediately; no cache dir created, no compile
#
# Usage: clift_ensure_cache <CLI_DIR> <FRAMEWORK_DIR>
clift_ensure_cache() {
  local cli_dir="$1" fw_dir="$2"

  # Bypass mode: skip the cache machinery entirely. No directory creation,
  # no staleness check, no compile. The wrapper and router both gracefully
  # degrade when the cache is absent under bypass.
  local _cache_mode="${CLIFT_CACHE:-}"
  if [[ "$_cache_mode" == "bypass" ]]; then
    return 0
  fi

  local cache_dir="$cli_dir/.clift"
  local checksum_file="$cache_dir/checksum"
  local sources_file="$cache_dir/sources"

  mkdir -p "$cache_dir"

  # Read tracked source files from the manifest written by compile.sh.
  # Falls back to the root Taskfile if no manifest exists yet (first run).
  local current
  if [[ -f "$sources_file" ]]; then
    # shellcheck disable=SC2046
    current="$(clift_max_mtime $(< "$sources_file"))"
  else
    current="$(clift_max_mtime "$cli_dir/Taskfile.yaml")"
  fi

  local _needs_rebuild=0
  if [[ "$_cache_mode" == "rebuild" ]]; then
    _needs_rebuild=1
  elif [[ ! -f "$checksum_file" ]] || [[ "$(<"$checksum_file")" != "$current" ]]; then
    _needs_rebuild=1
  fi

  if (( _needs_rebuild == 1 )); then
    # Serialize concurrent rebuilds. mkdir is atomic on all POSIX systems,
    # so exactly one process wins the race. Others wait and use the winner's
    # output.
    local lockdir="$cache_dir/.lock.d"
    if mkdir "$lockdir" 2>/dev/null; then
      # Re-check after acquiring lock — another process may have finished
      # the rebuild while we were checking staleness. Exception: when the
      # user explicitly asked for rebuild (mode=rebuild), we honor the
      # request unconditionally — the re-check shortcut would silently
      # turn a `--no-cache` invocation into a no-op after a concurrent
      # refresh, which is the opposite of what the user asked for.
      if [[ -f "$sources_file" ]]; then
        # shellcheck disable=SC2046
        current="$(clift_max_mtime $(< "$sources_file"))"
      else
        current="$(clift_max_mtime "$cli_dir/Taskfile.yaml")"
      fi
      local _compile_rc=0
      local _do_compile=0
      if [[ "$_cache_mode" == "rebuild" ]]; then
        _do_compile=1
      elif [[ ! -f "$checksum_file" ]] || [[ "$(<"$checksum_file")" != "$current" ]]; then
        _do_compile=1
      fi
      if (( _do_compile == 1 )); then
        bash "$fw_dir/lib/flags/compile.sh" "$cli_dir" >&2 || _compile_rc=$?
      fi
      rm -rf "$lockdir"
      return "$_compile_rc"
    else
      # Another process holds the lock — wait for it to finish (up to 5s).
      local _tries=0
      while [[ -d "$lockdir" ]] && (( _tries < 50 )); do
        sleep 0.1
        _tries=$((_tries + 1))
      done
      # Stale lock guard: if still present after timeout, the holder likely
      # crashed. Remove the lock so the next invocation can rebuild.
      [[ -d "$lockdir" ]] && rm -rf "$lockdir"
    fi
  fi
}
