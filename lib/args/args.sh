#!/usr/bin/env bash
# clift Argument Parser — DEPRECATED.
#
# This module is the pre-Phase-1 argument parser. Every framework consumer has
# migrated to `lib/flags/parser.sh` (schema-driven, validated, integrated with
# the override + help systems). No in-repo code path sources this file; only
# `tests/args.bats` remains, pinning the legacy behavior until a deprecation
# period lapses.
#
# If you are an external consumer sourcing this directly: switch to declaring
# `vars.FLAGS` in your command's Taskfile and reading `CLIFT_FLAG_*` env vars
# from your script — the framework takes care of parsing, validation, help
# rendering, and completion. See `docs/flags.md`.
#
# Removal plan: this file is a candidate for deletion in clift 1.0. A one-shot
# stderr warning fires whenever `parse_args` is invoked so stale callers see
# the migration path. Silence via `CLIFT_SILENCE_ARGS_DEPRECATION=1` for tests.
#
# Original contract (preserved for compat):
# Usage (sourced by command scripts):
#   source <(parse_args "$@" --flags "name,loud,verbose")
#
# Outputs `declare` statements for:
#   - Named flags: --name=value or name=value → NAME=value
#   - Boolean flags: --loud or loud (if in --flags list) → LOUD=true
#   - Positional args: bare values → ARG_1, ARG_2, ...
#   - ARG_COUNT: number of positional args
#
# All output is properly quoted via `declare -x` (injection-safe).

_CLIFT_ARGS_DEPRECATION_WARNED=0

parse_args() {
  if [[ "${CLIFT_SILENCE_ARGS_DEPRECATION:-0}" != "1" ]] \
     && (( _CLIFT_ARGS_DEPRECATION_WARNED == 0 )); then
    echo "warn: lib/args/args.sh:parse_args is deprecated; use lib/flags/parser.sh (schema-driven FLAGS in Taskfile + CLIFT_FLAG_* env vars). Silence with CLIFT_SILENCE_ARGS_DEPRECATION=1." >&2
    _CLIFT_ARGS_DEPRECATION_WARNED=1
  fi
  local known_flags=""
  local -a raw_args=()

  # Separate our meta-flags (--flags) from actual args
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--flags" ]]; then
      known_flags="$2"
      shift 2
    else
      raw_args+=("$1")
      shift
    fi
  done

  # Build associative lookup for known boolean flags
  local -A flag_lookup=()
  if [[ -n "$known_flags" ]]; then
    IFS=',' read -ra flag_names <<< "$known_flags"
    for f in "${flag_names[@]}"; do
      flag_lookup["${f,,}"]="1"  # lowercase key
    done
  fi

  local positional_count=0

  for arg in "${raw_args[@]}"; do
    if [[ "$arg" == *"="* ]]; then
      # key=value pair — strip dashes from key
      local clean="${arg#--}"
      clean="${clean#-}"
      local key="${clean%%=*}"
      local val="${clean#*=}"
      local upper_key="${key^^}"
      upper_key="${upper_key//-/_}"
      printf 'declare -x %s=%q\n' "$upper_key" "$val"
    elif [[ "$arg" == --* || "$arg" == -* ]]; then
      # Flag-style arg — check if it's a known boolean
      local clean="${arg#--}"
      clean="${clean#-}"
      if [[ -n "${flag_lookup[${clean,,}]:-}" ]]; then
        local upper_key="${clean^^}"
        upper_key="${upper_key//-/_}"
        printf 'declare -x %s=true\n' "$upper_key"
      else
        echo "warn: Unknown flag: $arg" >&2
      fi
    else
      # Bare word — positional argument
      ((positional_count++))
      printf 'declare -x ARG_%d=%q\n' "$positional_count" "$arg"
    fi
  done

  printf 'declare -x ARG_COUNT=%d\n' "$positional_count"
}
