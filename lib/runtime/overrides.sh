#!/usr/bin/env bash
# clift override loader. Resolves and sources override files from two tiers:
#   1. $CLI_DIR/cmds/<cmd-seg>/overrides/<slot>.sh   (per-command)
#   2. $CLI_DIR/.clift/overrides/<slot>.sh            (CLI-global)
# First file that exists wins. Callers use clift_call_override to dispatch.
#
# Sourced-only module: do NOT set shell options here. The caller (router /
# prelude path) already established `set -euo pipefail`, and setting options
# in a sourced file propagates to — and pollutes — the caller's shell state.
#
# Override slot naming convention (locks Phase 3):
#   clift_override_<area>_<action>     e.g. clift_override_help_list,
#                                           clift_override_version_print,
#                                           clift_override_command_pre,
#                                           clift_override_log_info
#
# Override signature:
#   clift_override_<area>_<action> <default_fn> <args...>
# The user function receives the default implementation as $1 and MAY invoke
# it (`"$1" "${@:2}"`) to delegate — supporting partial overrides and
# before/after wrapping.
#
# Dynamic flag completers use a different, user-keyed prefix
# (clift_complete_<task>_<flag>) and are documented separately.

if [[ -n "${_CLIFT_OVERRIDES_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
_CLIFT_OVERRIDES_LOADED=1

# clift_load_override <slot> [task]
# Sources the override file for <slot>. Per-command precedence when <task>
# is given: the per-command file wins and the CLI-global file is NOT loaded.
# No-op when no file exists at either tier.
clift_load_override() {
  local slot="$1"
  local task="${2:-}"
  if [[ -n "$task" ]]; then
    local cmd_seg="${task%%:*}"
    local per_cmd="${CLI_DIR}/cmds/${cmd_seg}/overrides/${slot}.sh"
    if [[ -f "$per_cmd" ]]; then
      # shellcheck source=/dev/null
      source "$per_cmd"
      return 0
    fi
  fi
  local global="${CLI_DIR}/.clift/overrides/${slot}.sh"
  if [[ -f "$global" ]]; then
    # shellcheck source=/dev/null
    source "$global"
  fi
}

# clift_call_override <slot> <default_fn> [--task <name>] [args...]
# Loads the override, then calls clift_override_<slot> (passing default_fn as
# $1) if defined. Otherwise calls default_fn directly with the passed args.
clift_call_override() {
  local slot="$1" default_fn="$2"
  local task=""
  shift 2
  if [[ "${1:-}" == "--task" ]]; then
    task="$2"
    shift 2
  fi
  clift_load_override "$slot" "$task"
  if declare -F "clift_override_${slot}" >/dev/null; then
    "clift_override_${slot}" "$default_fn" "$@"
  else
    "$default_fn" "$@"
  fi
}
