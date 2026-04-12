#!/usr/bin/env bash
# clift Flag Parser Error Helpers
# Sourced by parser.sh, wrapper.sh, and validate.sh.
# Provides did-you-mean suggestions and consistent error formatting.

# Guard against double-source
if [[ -n "${_CLIFT_ERRORS_LOADED:-}" ]]; then return 0; fi
_CLIFT_ERRORS_LOADED=1

_CLIFT_ERRORS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Suggest the single closest match from a space-separated candidate list,
# only when Levenshtein distance <= 2. Prints the suggestion to stdout
# (empty string if no suggestion).
clift_did_you_mean() {
  local target="$1"
  local candidates="$2"
  local best="" best_dist=3

  for cand in $candidates; do
    local dist
    dist="$(bash "$_CLIFT_ERRORS_DIR/levenshtein.sh" "$target" "$cand")"
    if (( dist < best_dist )); then
      best_dist=$dist
      best="$cand"
    fi
  done

  if (( best_dist <= 2 )); then
    echo "$best"
  fi
}

clift_err_unknown_flag() {
  local flag="$1"
  local known="$2"  # space-separated long names (no --)
  local bare="${flag#--}"
  bare="${bare#-}"

  echo "error: unknown flag '$flag'" >&2
  local suggestion
  suggestion="$(clift_did_you_mean "$bare" "$known")"
  if [[ -n "$suggestion" ]]; then
    echo "  did you mean '--$suggestion'?" >&2
  fi
  return 1
}

clift_err_unknown_command() {
  local cmd="$1"
  local known="$2"

  echo "error: unknown command '$cmd'" >&2
  local suggestion
  suggestion="$(clift_did_you_mean "$cmd" "$known")"
  if [[ -n "$suggestion" ]]; then
    echo "  did you mean '$suggestion'?" >&2
  fi
  echo "  run '${CLI_NAME:-mycli} --help' for commands" >&2
  return 1
}

clift_err_flag_before_command() {
  local cli="${1:-mycli}"
  echo "error: flags must come after the command" >&2
  echo "  run '$cli --help' for commands" >&2
  return 1
}

clift_err_subcmd_before_flags() {
  local cli="$1"; shift
  local cmd="$1"; shift
  local subcmd="$1"; shift
  local flags="$*"
  echo "error: subcommand must come before flags" >&2
  echo "  did you mean: $cli $cmd $subcmd $flags" >&2
  return 1
}

clift_err_missing_required() {
  local flag="$1"
  echo "error: required flag '--$flag' not provided" >&2
  return 1
}

clift_err_missing_value() {
  local flag="$1"
  echo "error: flag '$flag' requires a value" >&2
  return 1
}

clift_err_wrong_type() {
  local flag="$1" expected="$2" got="$3"
  echo "error: flag '$flag' requires $expected, got '$got'" >&2
  return 1
}

clift_err_nonbool_in_cluster() {
  local short="$1" cluster="$2" layer="$3"
  echo "error: short flag '-$short' cannot appear in cluster '$cluster'" >&2
  echo "  '-$short' is declared by $layer as non-bool" >&2
  return 1
}
