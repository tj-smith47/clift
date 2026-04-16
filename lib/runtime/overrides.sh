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
# Public API: clift_call_override is the sole public entry point. The loader
# (_clift_load_override) is internal — direct callers rarely need the raw
# loader, and exposing it invites "wrong function called" footguns.
#
# Dynamic flag completers use a different, user-keyed prefix
# (clift_complete_<task>_<flag>) and are documented separately.

if [[ -n "${_CLIFT_OVERRIDES_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
_CLIFT_OVERRIDES_LOADED=1

# _clift_load_override <slot> [task]
# Sources the override file for <slot>. Per-command precedence when <task>
# is given: the per-command file wins and the CLI-global file is NOT loaded.
# No-op when no file exists at either tier.
#
# Internal to this module — use clift_call_override from call sites.
#
# Errors (return 2): CLI_DIR unset, invalid slot name.
# Sourcing failures (syntax errors, explicit non-zero exit in the override
# file) bubble up as-is — intentional fail-loud contract so authors see
# their own bugs instead of a silent skip.
_clift_load_override() {
  : "${CLI_DIR:?_clift_load_override: CLI_DIR unset}"
  local slot="$1"
  local task="${2:-}"
  # Defend against path traversal via a hostile slot name. Slot names are
  # framework-reserved identifiers (help_list, version_print, …), never user
  # input in normal use — but the check costs nothing and keeps a stray
  # caller like `_clift_load_override "../../etc/passwd"` from reading
  # arbitrary files.
  [[ "$slot" =~ ^[a-z][a-z0-9_]*$ ]] || {
    log_error "_clift_load_override: invalid slot name '$slot'"
    return 2
  }
  # Empty task is treated the same as unset (both skip the per-cmd tier).
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
#
# Positional contract: `--task <name>`, when supplied, MUST be the first arg
# after <default_fn>. Anything else is forwarded verbatim to the override /
# default as user args.
clift_call_override() {
  local slot="$1" default_fn="$2"
  local task=""
  shift 2
  if [[ "${1:-}" == "--task" ]]; then
    [[ $# -ge 2 ]] || {
      log_error "clift_call_override: --task requires a value"
      return 2
    }
    task="$2"
    shift 2
  fi
  _clift_load_override "$slot" "$task"
  if declare -F "clift_override_${slot}" >/dev/null; then
    "clift_override_${slot}" "$default_fn" "$@"
  else
    "$default_fn" "$@"
  fi
}

# ---- Slot defaults ----------------------------------------------------------
# Framework defaults for built-in override slots. Hoisted here so every call
# site (wrapper, router, version subcommand, …) shares one definition instead
# of redeclaring an inline `_default()` next to each clift_call_override call.
# Each function is `clift_default_<slot>` and forms part of the public surface
# documented in docs/cli/overrides.md — user overrides MAY invoke them via the
# default_fn ($1) handle to delegate.

# clift_default_version_print — framework default for the version_print slot.
# Args: <CLI_NAME> <CLI_VERSION> <CLI_DIR>
# Override via .clift/overrides/version_print.sh (see docs/cli/overrides.md).
clift_default_version_print() {
  echo "$1 version $2"
}

# clift_default_command_pre — framework default for the command_pre slot.
# Args: <task_name>
# No-op; exists so the clift_call_override callback signature stays uniform
# and so overrides can delegate with `"$1" "${@:2}"` when wrapping.
clift_default_command_pre() { :; }

# clift_default_command_post — framework default for the command_post slot.
# Args: <task_name> <script_exit_code>
# No-op; same rationale as clift_default_command_pre. The post-hook cannot
# change the framework's exit code — the script's exit code wins regardless
# of what happens inside the override.
clift_default_command_post() { :; }
