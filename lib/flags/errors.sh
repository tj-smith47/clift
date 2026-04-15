#!/usr/bin/env bash
# clift Flag Parser Error Helpers
# Sourced by parser.sh, wrapper.sh, and validate.sh.
# Provides did-you-mean suggestions and consistent error formatting.

# Guard against double-source
if [[ -n "${_CLIFT_ERRORS_LOADED:-}" ]]; then return 0; fi
_CLIFT_ERRORS_LOADED=1

# Levenshtein distance — inline for zero-fork did-you-mean.
# Sets _CLIFT_DIST to the computed distance.
_clift_levenshtein() {
  local a="$1" b="$2"
  local la=${#a} lb=${#b}

  if (( la == 0 )); then _CLIFT_DIST=$lb; return 0; fi
  if (( lb == 0 )); then _CLIFT_DIST=$la; return 0; fi

  local -a row
  for (( j=0; j<=lb; j++ )); do row[j]=$j; done

  local prev prev_diag cost del ins sub min
  for (( i=1; i<=la; i++ )); do
    prev=$((i-1))
    row[0]=$i
    prev_diag=$prev
    for (( j=1; j<=lb; j++ )); do
      cost=1
      [[ "${a:i-1:1}" == "${b:j-1:1}" ]] && cost=0
      del=$(( row[j] + 1 ))
      ins=$(( row[j-1] + 1 ))
      sub=$(( prev_diag + cost ))
      min=$del
      (( ins < min )) && min=$ins
      (( sub < min )) && min=$sub
      prev_diag=${row[j]}
      row[j]=$min
    done
  done

  _CLIFT_DIST=${row[lb]}
}

# Suggest the single closest match from a space-separated candidate list,
# only when Levenshtein distance <= 2. Prints the suggestion to stdout
# (empty string if no suggestion).
clift_did_you_mean() {
  local target="$1"
  local candidates="$2"
  local best="" best_dist=3

  # Spec §10.1: bail out for very large candidate sets
  local count=0
  for _ in $candidates; do count=$((count+1)); done
  if (( count > 200 )); then return 0; fi

  for cand in $candidates; do
    # Spec §10.1: skip candidates whose length differs by more than 2
    local diff=$(( ${#cand} - ${#target} ))
    (( diff < 0 )) && diff=$(( -diff ))
    (( diff > 2 )) && continue

    _clift_levenshtein "$target" "$cand"
    if (( _CLIFT_DIST < best_dist )); then
      best_dist=$_CLIFT_DIST
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

clift_err_invalid_choice() {
  local name="$1" value="$2" choices_csv="$3"
  # Render choices as comma+space separated for readability
  local pretty="${choices_csv//,/, }"
  echo "error: value '$value' for flag '--$name' is not one of: $pretty" >&2
  return 1
}

clift_err_invalid_pattern() {
  local name="$1" value="$2" pattern="$3"
  echo "error: value '$value' for flag '--$name' does not match pattern '$pattern'" >&2
  return 1
}

clift_err_nonbool_in_cluster() {
  local short="$1" cluster="$2" layer="$3"
  echo "error: short flag '-$short' cannot appear in cluster '$cluster'" >&2
  echo "  '-$short' is declared by $layer as non-bool" >&2
  return 1
}

# Mutually-exclusive group violation. Members is a space-separated list of
# canonical flag names that were all set in this invocation (at least 2).
clift_err_mutex_group() {
  local group="$1" members="$2"
  local formatted=""
  for m in $members; do
    if [[ -z "$formatted" ]]; then
      formatted="'--$m'"
    else
      formatted="$formatted, '--$m'"
    fi
  done
  echo "error: flags $formatted in group '$group' are mutually exclusive" >&2
  return 1
}

# Required-together group violation. `set_members` is space-separated canonical
# names that WERE set; `missing_members` is the names that were NOT set but
# are required because another group member was provided.
clift_err_requires_all_group() {
  local group="$1" set_members="$2" missing_members="$3"
  local missing_fmt="" set_fmt=""
  for m in $missing_members; do
    if [[ -z "$missing_fmt" ]]; then
      missing_fmt="'--$m'"
    else
      missing_fmt="$missing_fmt, '--$m'"
    fi
  done
  for m in $set_members; do
    if [[ -z "$set_fmt" ]]; then
      set_fmt="'--$m'"
    else
      set_fmt="$set_fmt, '--$m'"
    fi
  done
  echo "error: in group '$group', flag(s) $missing_fmt required when $set_fmt is provided" >&2
  return 1
}
