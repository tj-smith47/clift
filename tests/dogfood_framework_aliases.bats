#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

# Task 6.3 — dogfood: the framework's own `config:show` and `update`
# commands declare cobra-conventional aliases. Unlike user commands,
# framework Taskfiles are not compiled into index.json (compile.sh skips
# $FW_DIR/ on purpose — those tasks are passthrough, not parsed). The
# wrapper must still honor their aliases by reading them directly from
# tasks.json as nested aliases.

load test_helper

setup() { common_setup; }
teardown() { common_teardown; }

_bootstrap_dogfood_cli() {
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/dcli" "$FRAMEWORK_DIR" "dcli" "1.0.0" "minimal" "standard" \
    > /dev/null 2>&1
  export PATH="$TEST_DIR/dcli/bin:$PATH"
}

@test "mycli config dump routes to config:show" {
  _bootstrap_dogfood_cli
  run dcli config dump
  [ "$status" -eq 0 ]
  # config:show prints the CLI's config — at minimum the CLI name appears.
  [[ "$output" == *"dcli"* ]]
}

@test "mycli config:dump (colon form) routes to config:show" {
  _bootstrap_dogfood_cli
  run dcli config:dump
  [ "$status" -eq 0 ]
  [[ "$output" == *"dcli"* ]]
}

@test "mycli upgrade routes to update (first-token alias)" {
  _bootstrap_dogfood_cli
  # `update` shells out to git; the test only cares that dispatch reached
  # update.sh. log_info's "Checking for updates..." on line 30 is emitted
  # before any git call — a sufficient proof-of-dispatch. The git command
  # will fail on the test host (no real remote), so we check for the
  # banner regardless of exit status.
  run dcli upgrade
  [[ "$output" == *"Checking for updates"* ]]
}

@test "mycli update:upgrade (colon form) routes to update" {
  _bootstrap_dogfood_cli
  run dcli update:upgrade
  [[ "$output" == *"Checking for updates"* ]]
}

@test "dogfooded aliases surface in config:show detail view" {
  _bootstrap_dogfood_cli
  run env \
    CLI_NAME=dcli \
    CLI_VERSION=1.0.0 \
    CLI_DIR="$TEST_DIR/dcli" \
    FRAMEWORK_DIR="$FRAMEWORK_DIR" \
    LOG_THEME=minimal \
    CLIFT_MODE=standard \
    bash "$FRAMEWORK_DIR/lib/help/detail.sh" "config:show" "$TEST_DIR/dcli/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Aliases: dump"* ]]
}

@test "dogfooded aliases surface in update detail view" {
  _bootstrap_dogfood_cli
  run env \
    CLI_NAME=dcli \
    CLI_VERSION=1.0.0 \
    CLI_DIR="$TEST_DIR/dcli" \
    FRAMEWORK_DIR="$FRAMEWORK_DIR" \
    LOG_THEME=minimal \
    CLIFT_MODE=standard \
    bash "$FRAMEWORK_DIR/lib/help/detail.sh" "update" "$TEST_DIR/dcli/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"upgrade"* ]]
}
