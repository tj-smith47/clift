#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR"
  export FRAMEWORK_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  touch "$HOME/.bashrc"
  export CLIFT_RC_FILE="$HOME/.bashrc"
  export SHELL=/bin/bash
  export PROMPT=false
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "fresh install task mode: alias in rc, no wrapper" {
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "0.1.0" "minimal" "task"
  run grep -c '^alias mycli=' "$HOME/.bashrc"
  [ "$output" = "1" ]
  [ ! -f "$TEST_DIR/mycli/bin/mycli" ]
}

@test "fresh install standard mode: wrapper + PATH, no alias" {
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "0.1.0" "minimal" "standard"
  run grep -c 'export PATH=' "$HOME/.bashrc"
  [ "$output" = "1" ]
  [ -x "$TEST_DIR/mycli/bin/mycli" ]
  run grep -c '^alias mycli=' "$HOME/.bashrc"
  [ "$output" = "0" ]
}

@test "switch task → standard scrubs alias, adds wrapper" {
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "0.1.0" "minimal" "task"
  RECONFIGURE_YES=1 bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "0.1.0" "minimal" "standard"
  run grep -c '^alias mycli=' "$HOME/.bashrc"
  [ "$output" = "0" ]
  run grep -c 'export PATH=' "$HOME/.bashrc"
  [ "$output" = "1" ]
  [ -x "$TEST_DIR/mycli/bin/mycli" ]
}

@test "switch standard → task scrubs PATH + wrapper, adds alias" {
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "0.1.0" "minimal" "standard"
  RECONFIGURE_YES=1 bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "0.1.0" "minimal" "task"
  run grep -c 'export PATH=' "$HOME/.bashrc"
  [ "$output" = "0" ]
  run grep -c '^alias mycli=' "$HOME/.bashrc"
  [ "$output" = "1" ]
  [ ! -f "$TEST_DIR/mycli/bin/mycli" ]
}

@test "invalid CLIFT_MODE errors" {
  run bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "0.1.0" "minimal" "banana"
  [ "$status" -ne 0 ]
  [[ "$output" == *"CLIFT_MODE"* ]]
}
