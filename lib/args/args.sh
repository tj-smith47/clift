#!/usr/bin/env bash
# DIYCLI Argument Parser
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

parse_args() {
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
    # Strip leading dashes
    local clean="${arg#--}"
    clean="${clean#-}"

    if [[ "$clean" == *"="* ]]; then
      # key=value pair
      local key="${clean%%=*}"
      local val="${clean#*=}"
      local upper_key="${key^^}"
      upper_key="${upper_key//-/_}"
      printf 'declare -x %s=%q\n' "$upper_key" "$val"
    elif [[ -n "${flag_lookup[${clean,,}]:-}" ]]; then
      # Known boolean flag
      local upper_key="${clean^^}"
      upper_key="${upper_key//-/_}"
      printf 'declare -x %s=true\n' "$upper_key"
    else
      # Positional argument
      ((positional_count++))
      printf 'declare -x ARG_%d=%q\n' "$positional_count" "$clean"
    fi
  done

  printf 'declare -x ARG_COUNT=%d\n' "$positional_count"
}
