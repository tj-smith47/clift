#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load test_helper

@test "identical strings distance 0" {
  run bash "$FRAMEWORK_DIR/lib/flags/levenshtein.sh" "force" "force"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "one substitution distance 1" {
  run bash "$FRAMEWORK_DIR/lib/flags/levenshtein.sh" "force" "forge"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "one transposition distance 2" {
  run bash "$FRAMEWORK_DIR/lib/flags/levenshtein.sh" "froce" "force"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "empty vs non-empty distance equals length" {
  run bash "$FRAMEWORK_DIR/lib/flags/levenshtein.sh" "" "abc"
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

@test "totally different strings" {
  run bash "$FRAMEWORK_DIR/lib/flags/levenshtein.sh" "foo" "bar"
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}
