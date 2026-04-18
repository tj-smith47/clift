#!/usr/bin/env bats
# Pins legacy lib/args/args.sh behavior — see deprecation banner in that
# file. Tests export CLIFT_SILENCE_ARGS_DEPRECATION so the runtime warning
# doesn't pollute the captured stderr/stdout assertions.

load test_helper

setup() {
  common_setup
  export CLIFT_SILENCE_ARGS_DEPRECATION=1
}

@test "key=value parsing produces declare statement" {
  source "$FRAMEWORK_DIR/lib/args/args.sh"
  run parse_args "NAME=world"
  [ "$status" -eq 0 ]
  [[ "$output" == *'declare -x NAME='* ]]
  [[ "$output" == *'world'* ]]
}

@test "--flag=value parsing produces declare statement" {
  source "$FRAMEWORK_DIR/lib/args/args.sh"
  run parse_args "--name=alice"
  [ "$status" -eq 0 ]
  [[ "$output" == *'declare -x NAME='* ]]
  [[ "$output" == *'alice'* ]]
}

@test "boolean flags set to true when in --flags list" {
  source "$FRAMEWORK_DIR/lib/args/args.sh"
  run parse_args "--loud" --flags "loud"
  [ "$status" -eq 0 ]
  [[ "$output" == *'declare -x LOUD=true'* ]]
}

@test "positional args mapped to ARG_1, ARG_2" {
  source "$FRAMEWORK_DIR/lib/args/args.sh"
  run parse_args "hello" "world"
  [ "$status" -eq 0 ]
  [[ "$output" == *'declare -x ARG_1='* ]]
  [[ "$output" == *'hello'* ]]
  [[ "$output" == *'declare -x ARG_2='* ]]
  [[ "$output" == *'world'* ]]
}

@test "ARG_COUNT is set" {
  source "$FRAMEWORK_DIR/lib/args/args.sh"
  run parse_args "a" "b" "c"
  [ "$status" -eq 0 ]
  [[ "$output" == *'declare -x ARG_COUNT=3'* ]]
}

@test "ARG_COUNT is 0 with no positionals" {
  source "$FRAMEWORK_DIR/lib/args/args.sh"
  run parse_args "--name=val"
  [ "$status" -eq 0 ]
  [[ "$output" == *'declare -x ARG_COUNT=0'* ]]
}

@test "unknown flags produce warning on stderr" {
  source "$FRAMEWORK_DIR/lib/args/args.sh"
  run bash -c 'source "$FRAMEWORK_DIR/lib/args/args.sh"; parse_args "--unknown" 2>&1'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Unknown flag: --unknown"* ]]
}

@test "unknown flags are NOT added as positionals" {
  source "$FRAMEWORK_DIR/lib/args/args.sh"
  run bash -c 'source "$FRAMEWORK_DIR/lib/args/args.sh"; parse_args "--unknown" 2>/dev/null'
  [ "$status" -eq 0 ]
  [[ "$output" == *'declare -x ARG_COUNT=0'* ]]
}

@test "mixed args: key=value, boolean flag, and positional" {
  source "$FRAMEWORK_DIR/lib/args/args.sh"
  run parse_args "NAME=test" "--loud" "hello" --flags "loud"
  [ "$status" -eq 0 ]
  [[ "$output" == *'declare -x NAME='* ]]
  [[ "$output" == *'declare -x LOUD=true'* ]]
  [[ "$output" == *'declare -x ARG_1='* ]]
  [[ "$output" == *'hello'* ]]
  [[ "$output" == *'declare -x ARG_COUNT=1'* ]]
}
