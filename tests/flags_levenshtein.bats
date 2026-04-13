#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load test_helper

# Tests exercise _clift_levenshtein via errors.sh (the single source of truth).
# A thin wrapper script is used because _clift_levenshtein sets _CLIFT_DIST
# rather than printing to stdout.

_run_levenshtein() {
  run bash -c '
    source "'"$FRAMEWORK_DIR"'/lib/flags/errors.sh"
    _clift_levenshtein "$1" "$2"
    echo "$_CLIFT_DIST"
  ' _ "$1" "$2"
}

@test "identical strings distance 0" {
  _run_levenshtein "force" "force"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "one substitution distance 1" {
  _run_levenshtein "force" "forge"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "one transposition distance 2" {
  _run_levenshtein "froce" "force"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "empty vs non-empty distance equals length" {
  _run_levenshtein "" "abc"
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

@test "totally different strings" {
  _run_levenshtein "foo" "bar"
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}
