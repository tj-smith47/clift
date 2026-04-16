#!/usr/bin/env bash
# clift runtime boot wrapper
# Invoked by the router in place of `exec bash "$script_path"`. Sources the
# prelude once (loading log helpers, etc.) then sources the user's command
# script in the same process — no extra fork, no BASH_ENV recursion.
#
# Usage: exec.sh <user_script_path>
#
# This file is only ever invoked via `exec bash …` from the router; it is
# never sourced. No source guard is needed.

set -euo pipefail

if [[ -z "${FRAMEWORK_DIR:-}" ]]; then
  echo "exec.sh: FRAMEWORK_DIR unset" >&2
  exit 1
fi

if [[ $# -lt 1 ]]; then
  echo "exec.sh: missing user script path" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "${FRAMEWORK_DIR}/lib/runtime/prelude.sh"

_clift_user_script="$1"
shift

# Register the command_post hook via EXIT trap. The trap fires on:
#   - Normal exit (exit 0)
#   - set -e bailout (non-zero exit)
#   - SIGINT/SIGTERM (signals trigger EXIT before the process terminates)
#
# The post-hook receives the original exit code but CANNOT change it.
# Whatever the user script exited with is what the process exits with.
#
# overrides.sh is already loaded by prelude.sh (source-guarded), so
# clift_call_override is available. The explicit source inside the handler
# is belt-and-suspenders against future refactors that might remove the
# prelude→overrides dependency.
_clift_run_command_post() {
  local rc=$?
  # Disable set -e inside the trap handler so the override running does
  # not accidentally abort the trap before we can re-assert the exit code.
  set +e
  # shellcheck source=/dev/null
  source "${FRAMEWORK_DIR}/lib/runtime/overrides.sh"
  clift_call_override command_post clift_default_command_post \
    --task "${CLIFT_TASK:-}" "${CLIFT_TASK:-}" "$rc"
  exit "$rc"
}
trap _clift_run_command_post EXIT

# shellcheck source=/dev/null
source "$_clift_user_script" "$@"
