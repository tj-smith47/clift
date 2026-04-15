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

# Task 2.2 will build the CLIFT_FLAGS associative array here.
