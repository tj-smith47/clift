#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load test_helper

setup() { common_setup; }
teardown() { common_teardown; }

@test "clift_exit emits message and exits with given code" {
  run --separate-stderr bash -c 'LOG_THEME=minimal source "$FRAMEWORK_DIR/lib/log/log.sh"; clift_exit 42 "deployment conflict"'
  [ "$status" -eq 42 ]
  # minimal theme prefixes error messages with "error: " on stderr
  [[ "$stderr" == *"error: deployment conflict"* ]]
}

@test "clift_exit with no msg exits with code and emits no output" {
  run bash -c 'source "$FRAMEWORK_DIR/lib/log/log.sh"; clift_exit 7 2>&1'
  [ "$status" -eq 7 ]
  [ -z "$output" ]
}

@test "clift_exit with no args exits with default code 1" {
  run bash -c 'source "$FRAMEWORK_DIR/lib/log/log.sh"; clift_exit 2>&1'
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "clift_exit is visible to subshells via export -f" {
  run --separate-stderr bash -c 'source "$FRAMEWORK_DIR/lib/log/log.sh"; bash -c "clift_exit 9 oh-no"'
  [ "$status" -eq 9 ]
  [[ "$stderr" == *"oh-no"* ]]
}

@test "clift_exit honors active LOG_THEME" {
  # minimal theme prefixes "error: " on stderr; verify message survives the theme path
  run --separate-stderr bash -c 'LOG_THEME=minimal source "$FRAMEWORK_DIR/lib/log/log.sh"; clift_exit 5 "bad config"'
  [ "$status" -eq 5 ]
  [[ "$stderr" == *"error: bad config"* ]]
}

@test "clift_exit with explicit empty message emits no stderr (distinct from omitted-msg path)" {
  # Contract parity with the omitted-arg case: the [[ -n "$msg" ]] guard must
  # treat an explicit empty string identically — rc honored, stderr silent.
  run --separate-stderr bash -c 'source "$FRAMEWORK_DIR/lib/log/log.sh"; clift_exit 5 ""'
  [ "$status" -eq 5 ]
  [ -z "$stderr" ]
}

@test "clift_exit with non-numeric code fails loud via bash diagnostic" {
  # Contract: same loud-failure behavior as die with a non-numeric code.
  # log_error still reaches stderr, bash emits its own "numeric argument required"
  # diagnostic, and the final rc is bash's 2 (invalid-exit-arg), not the
  # script's happy-path 0.
  run --separate-stderr bash -c 'source "$FRAMEWORK_DIR/lib/log/log.sh"; clift_exit abc "bad"; exit 0'
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"bad"* ]]
  [[ "$stderr" == *"numeric argument required"* ]]
}
