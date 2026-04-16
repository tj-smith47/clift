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

@test "did-you-mean returns empty for >200 candidates" {
  source "$FRAMEWORK_DIR/lib/flags/errors.sh"
  local many=""
  for i in $(seq 1 201); do many="$many cand$i"; done
  run clift_did_you_mean "cand1" "$many"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "did-you-mean skips candidates with length difference >2" {
  source "$FRAMEWORK_DIR/lib/flags/errors.sh"
  run clift_did_you_mean "abc" "abcdef xy"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "bool flag --help=true is rejected" {
  # Bool flags never accept inline values; --help=true must error.
  create_test_cli "greet"
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR" >/dev/null 2>&1 || true
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" greet --help=true
  [ "$status" -ne 0 ]
  [[ "$output" == *"--help"* ]]
  [[ "$output" == *"does not take a value"* ]]
}

@test "bool flag --no-cache=foo is rejected" {
  create_test_cli "greet"
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR" >/dev/null 2>&1 || true
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" greet --no-cache=foo
  [ "$status" -ne 0 ]
  [[ "$output" == *"--no-cache"* ]]
  [[ "$output" == *"does not take a value"* ]]
}

@test "bool flag --quiet=1 is rejected" {
  create_test_cli "greet"
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR" >/dev/null 2>&1 || true
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" greet --quiet=1
  [ "$status" -ne 0 ]
  [[ "$output" == *"--quiet"* ]]
  [[ "$output" == *"does not take a value"* ]]
}

@test "bool short flag -h=true is rejected" {
  # Short form with inline value should also reject for bool flags.
  create_test_cli "greet"
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR" >/dev/null 2>&1 || true
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" greet -h=true
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not take a value"* ]]
}
