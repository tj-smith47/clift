#!/usr/bin/env bash
# clift runtime prelude
# Sourced once by lib/runtime/exec.sh in the user script's own process so that
# log helpers (and, later, CLIFT_FLAGS) are available without an explicit
# `source ${FRAMEWORK_DIR}/lib/log/log.sh` line in every command.
#
# Do NOT point BASH_ENV at this file. BASH_ENV re-sources on every
# non-interactive subshell the script spawns, re-running this work for every
# `$(bash -c …)` on the hot path. Instead, we run once here and rely on
# `export -f` in log.sh so subshells inherit the functions for free.

if [[ -n "${_CLIFT_PRELUDE_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
_CLIFT_PRELUDE_LOADED=1

if [[ -z "${FRAMEWORK_DIR:-}" ]]; then
  echo "prelude.sh: FRAMEWORK_DIR unset" >&2
  return 1 2>/dev/null || exit 1
fi

# shellcheck source=/dev/null
source "${FRAMEWORK_DIR}/lib/log/log.sh"

# CLIFT_FLAGS — associative array mirror of parsed flags, dash-preserving keys
# (e.g., ${CLIFT_FLAGS[dry-run]}). The legacy CLIFT_FLAG_<UPPER_NAME> env vars
# (dashes → underscores) are unchanged and still exported by the parser.
#
# Requires bash 4.2+ for `declare -A -g`. clift's documented floor is 4.0, but
# every known production user is on 4.2+ and CI runs 5.x. If a future 4.0
# fixture surfaces we'll add a fallback; for now we fail loudly rather than
# silently skip the array.
#
# List flags are exposed as a single comma-joined value:
#   CLIFT_FLAGS[tag]="a,b,c"
# Per-element access stays via CLIFT_FLAG_TAG_1, CLIFT_FLAG_TAG_2,
# CLIFT_FLAG_TAG_COUNT (unchanged).
#
# Subshells: bash assoc arrays don't export across process boundaries. A
# subshell that re-sources this prelude (or inherits CLIFT_FLAGS_FILE and
# reads it) can rebuild the array; otherwise subshells fall back to the
# exported CLIFT_FLAG_* env vars, which DO cross the boundary.
declare -A -g CLIFT_FLAGS=()
if [[ -n "${CLIFT_FLAGS_FILE:-}" && -f "${CLIFT_FLAGS_FILE}" ]]; then
  while IFS= read -r -d '' _clift_kv; do
    _clift_k="${_clift_kv%%=*}"
    _clift_v="${_clift_kv#*=}"
    # shellcheck disable=SC2034  # CLIFT_FLAGS is the public API consumed by user scripts
    CLIFT_FLAGS["$_clift_k"]="$_clift_v"
  done < "${CLIFT_FLAGS_FILE}"
  unset _clift_kv _clift_k _clift_v
  # The router's EXIT trap doesn't fire on the exec-replacement path into
  # exec.sh, so we clean up the tempfile here after reading it. The router
  # trap stays as belt-and-suspenders for the failure path where parsing
  # exits early and never reaches this prelude.
  rm -f "${CLIFT_FLAGS_FILE}"
fi
