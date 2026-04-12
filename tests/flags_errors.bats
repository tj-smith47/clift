#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load test_helper

@test "did-you-mean suggests close match" {
  source "$FRAMEWORK_DIR/lib/flags/errors.sh"
  run clift_did_you_mean "froce" "force help version verbose"
  [ "$status" -eq 0 ]
  [ "$output" = "force" ]
}

@test "did-you-mean empty when nothing close" {
  source "$FRAMEWORK_DIR/lib/flags/errors.sh"
  run clift_did_you_mean "xyzzy" "force help version"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "unknown flag error with suggestion" {
  source "$FRAMEWORK_DIR/lib/flags/errors.sh"
  run clift_err_unknown_flag "--froce" "force help version"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown flag '--froce'"* ]]
  [[ "$output" == *"did you mean '--force'"* ]]
}

@test "flag before command error" {
  source "$FRAMEWORK_DIR/lib/flags/errors.sh"
  run clift_err_flag_before_command "mycli"
  [ "$status" -eq 1 ]
  [[ "$output" == *"flags must come after the command"* ]]
}

@test "subcommand before flags error" {
  source "$FRAMEWORK_DIR/lib/flags/errors.sh"
  run clift_err_subcmd_before_flags "mycli" "deploy" "prod" "-v"
  [ "$status" -eq 1 ]
  [[ "$output" == *"subcommand must come before flags"* ]]
  [[ "$output" == *"mycli deploy prod -v"* ]]
}
