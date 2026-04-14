#!/usr/bin/env bats
# Tests for bin/clift — the framework entry point that dispatches `clift init`.
# Validates that flag→env var translation is correct so init options aren't
# silently dropped.

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR"
  export FRAMEWORK_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export CLIFT_RC_FILE="$HOME/.bashrc"
  touch "$HOME/.bashrc"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "clift init without --cfgd does not create module.yaml" {
  run "$FRAMEWORK_DIR/bin/clift" init "$TEST_DIR/plain" --mode standard
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_DIR/plain/module.yaml" ]
}

@test "clift init --cfgd creates module.yaml" {
  run "$FRAMEWORK_DIR/bin/clift" init "$TEST_DIR/wcfgd" --mode standard --cfgd
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/wcfgd/module.yaml" ]
}

@test "clift init without --ci does not create workflow" {
  run "$FRAMEWORK_DIR/bin/clift" init "$TEST_DIR/plain" --mode standard
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_DIR/plain/.github/workflows/ci.yml" ]
}

@test "clift init --ci creates GitHub workflow" {
  run "$FRAMEWORK_DIR/bin/clift" init "$TEST_DIR/wci" --mode standard --ci
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/wci/.github/workflows/ci.yml" ]
}

@test "clift init help mentions --cfgd and --ci" {
  run "$FRAMEWORK_DIR/bin/clift" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--cfgd"* ]]
  [[ "$output" == *"--ci"* ]]
}

@test "clift init rejects unknown flag" {
  run "$FRAMEWORK_DIR/bin/clift" init "$TEST_DIR/bad" --bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown flag"* ]]
}

@test "clift init CFGD_VERSIONING env var still works" {
  CFGD_VERSIONING=true run "$FRAMEWORK_DIR/bin/clift" init "$TEST_DIR/ecfgd" --mode standard
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/ecfgd/module.yaml" ]
}

@test "clift init CLIFT_CI env var still works" {
  CLIFT_CI=true run "$FRAMEWORK_DIR/bin/clift" init "$TEST_DIR/eci" --mode standard
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/eci/.github/workflows/ci.yml" ]
}
