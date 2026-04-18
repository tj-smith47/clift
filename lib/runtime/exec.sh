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

# Register the command_post hook. The EXIT trap fires on:
#   - Normal exit (exit 0)
#   - set -e bailout (non-zero exit)
#   - SIGINT/SIGTERM (signals trigger EXIT before the process terminates)
#
# Signal rc capture: bash's default EXIT trap sees `$?=0` when a signal
# interrupts `source user_script` mid-run — the nominal 130/143 exit code
# is NOT reflected in $? for the EXIT trap. We install explicit INT/TERM
# handlers that stash the canonical signal rc in __CLIFT_USER_RC, then
# call `exit` to transfer control to the EXIT trap. The EXIT handler
# reads __CLIFT_USER_RC (falling back to $? for the non-signal paths).
#
# Naming: double-underscore + ALL_CAPS marks this as framework-private and
# defends against name collisions with user-script variables — a single
# leading underscore is convention-only in bash and a user `_clift_user_rc`
# in command_pre or the user script would silently shadow the signal rc.
#
# The post-hook receives the original exit code but CANNOT change it.
# Whatever the user script exited with is what the process exits with.
#
# overrides.sh is already loaded by prelude.sh (source-guarded), so
# clift_call_override is available. The explicit source inside the handler
# is belt-and-suspenders against future refactors that might remove the
# prelude→overrides dependency.
_clift_on_sigint() { __CLIFT_USER_RC=130; exit 130; }
_clift_on_sigterm() { __CLIFT_USER_RC=143; exit 143; }
_clift_run_command_post() {
  local rc="${__CLIFT_USER_RC:-$?}"
  # Disable set -e inside the trap handler so the override running does
  # not accidentally abort the trap before we can re-assert the exit code.
  set +e
  # shellcheck source=/dev/null
  source "${FRAMEWORK_DIR}/lib/runtime/overrides.sh"
  # Subshell-wrap the override so a user `exit N` inside command_post is
  # contained — otherwise it preempts our `exit "$rc"` below and the
  # post-hook silently wins the exit code. `return N` is already contained
  # by clift_call_override's function-return semantics; the subshell closes
  # the only remaining escape. Fork cost is on the terminate path (once per
  # command), not a hot loop — acceptable.
  ( clift_call_override command_post clift_default_command_post \
      --task "${CLIFT_TASK:-}" "${CLIFT_TASK:-}" "$rc" ) || true
  exit "$rc"
}
trap _clift_on_sigint INT
trap _clift_on_sigterm TERM
trap _clift_run_command_post EXIT

# shellcheck source=/dev/null
source "$_clift_user_script" "$@"
