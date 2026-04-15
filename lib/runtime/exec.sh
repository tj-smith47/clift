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

# shellcheck source=/dev/null
source "$_clift_user_script" "$@"
