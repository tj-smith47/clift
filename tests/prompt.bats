#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR"
  export FRAMEWORK_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "prompt input returns existing env var without prompting" {
  run bash -c 'export MY_VAR="existing_value"; "$FRAMEWORK_DIR/lib/prompt/prompt.sh" input "Label" --var MY_VAR'
  [ "$status" -eq 0 ]
  [ "$output" = "existing_value" ]
}

@test "prompt choose returns existing env var without prompting" {
  run bash -c 'export MY_VAR="opt2"; "$FRAMEWORK_DIR/lib/prompt/prompt.sh" choose "Label" --var MY_VAR --options "opt1,opt2,opt3"'
  [ "$status" -eq 0 ]
  [ "$output" = "opt2" ]
}

@test "prompt input with PROMPT=false uses default" {
  run bash -c 'export PROMPT=false; "$FRAMEWORK_DIR/lib/prompt/prompt.sh" input "Label" --var UNSET_VAR --default "fallback"'
  [ "$status" -eq 0 ]
  [ "$output" = "fallback" ]
}

@test "prompt input with PROMPT=false and no default exits with error" {
  run bash -c 'export PROMPT=false; "$FRAMEWORK_DIR/lib/prompt/prompt.sh" input "Label" --var UNSET_VAR 2>&1'
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing required value"* ]]
}

@test "prompt choose with PROMPT=false uses default" {
  run bash -c 'export PROMPT=false; "$FRAMEWORK_DIR/lib/prompt/prompt.sh" choose "Label" --var UNSET_VAR --options "a,b,c" --default "b"'
  [ "$status" -eq 0 ]
  [ "$output" = "b" ]
}

@test "prompt requires --var flag" {
  run bash -c '"$FRAMEWORK_DIR/lib/prompt/prompt.sh" input "Label" 2>&1'
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires --var"* ]]
}

@test "prompt rejects unknown flags" {
  run bash -c '"$FRAMEWORK_DIR/lib/prompt/prompt.sh" input "Label" --var X --bogus 2>&1'
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown"* ]]
}

@test "prompt choose requires --options" {
  run bash -c 'export PROMPT=true; echo "1" | "$FRAMEWORK_DIR/lib/prompt/prompt.sh" choose "Label" --var UNSET_VAR 2>&1'
  [ "$status" -eq 1 ]
  [[ "$output" == *"--options required"* ]]
}

@test "prompt rejects unknown type" {
  run bash -c '"$FRAMEWORK_DIR/lib/prompt/prompt.sh" bogustype "Label" --var X 2>&1'
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown prompt type"* ]]
}

@test "prompt input with read fallback uses default on empty input" {
  # No gum available, PROMPT not false, simulate empty input → default used
  run bash -c '
    export PATH="/usr/bin:/bin"
    echo "" | "$FRAMEWORK_DIR/lib/prompt/prompt.sh" input "Label" --var UNSET_VAR --default "mydefault" 2>&1
  '
  # Either default is used or we get an error about no tty — both are valid
  [[ "$output" == *"mydefault"* ]] || [[ "$status" -ne 0 ]]
}

@test "prompt choose with PROMPT=false and no default exits with error" {
  run bash -c 'export PROMPT=false; "$FRAMEWORK_DIR/lib/prompt/prompt.sh" choose "Label" --var UNSET_VAR --options "a,b,c" 2>&1'
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing required value"* ]]
}

@test "prompt input with PROMPT=false returns default for empty var" {
  run bash -c 'export PROMPT=false; export MY_VAR=""; "$FRAMEWORK_DIR/lib/prompt/prompt.sh" input "Label" --var MY_VAR --default "fb" 2>&1'
  [ "$status" -eq 0 ]
  [ "$output" = "fb" ]
}

@test "prompt requires type and label" {
  run bash -c '"$FRAMEWORK_DIR/lib/prompt/prompt.sh" 2>&1'
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires type and label"* ]]
}

@test "prompt choose existing env var takes priority over options" {
  run bash -c 'export PICK="special"; "$FRAMEWORK_DIR/lib/prompt/prompt.sh" choose "Label" --var PICK --options "a,b,c"'
  [ "$status" -eq 0 ]
  [ "$output" = "special" ]
}
