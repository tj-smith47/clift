#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR"
  export FRAMEWORK_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export CLI_DIR="$TEST_DIR"
  export CLI_NAME="testcli"
  export CLI_VERSION="1.0.0"

  # Minimal CLI with two commands, one with a subcommand
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
dotenv: ['.env']
vars:
  FLAGS:
    - {name: trace, short: t, type: bool}
    - {name: debug, short: d, type: bool}
includes:
  hello:
    taskfile: ./cmds/hello
  deploy:
    taskfile: ./cmds/deploy
tasks:
  default:
    cmd: echo root-default
  version:
    cmd: 'echo "$CLI_NAME version $CLI_VERSION"'
YAML
  cat > "$TEST_DIR/.env" <<ENV
CLI_NAME=$CLI_NAME
CLI_VERSION=$CLI_VERSION
CLI_DIR=$TEST_DIR
FRAMEWORK_DIR=$FRAMEWORK_DIR
CLIFT_MODE=standard
ENV

  mkdir -p "$TEST_DIR/cmds/hello"
  cat > "$TEST_DIR/cmds/hello/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS: []
tasks:
  default:
    vars:
      FLAGS: []
    cmd: echo hello-ran
YAML

  mkdir -p "$TEST_DIR/cmds/deploy"
  cat > "$TEST_DIR/cmds/deploy/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS: []
tasks:
  default:
    vars:
      FLAGS: []
    cmd: echo deploy-default
  prod:
    vars:
      FLAGS: []
    cmd: echo deploy-prod
YAML

  # Precompile
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$TEST_DIR"

  # Generate wrapper script from template
  build_test_wrapper
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "zero args dispatches to root default" {
  run "$TEST_DIR/bin/$CLI_NAME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"root-default"* ]]
}

@test "--version echoes directly" {
  run "$TEST_DIR/bin/$CLI_NAME" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"testcli version 1.0.0"* ]]
}

@test "single-level command dispatches to task" {
  run "$TEST_DIR/bin/$CLI_NAME" hello
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello-ran"* ]]
}

@test "two-level command dispatches to subcommand task" {
  run "$TEST_DIR/bin/$CLI_NAME" deploy prod
  [ "$status" -eq 0 ]
  [[ "$output" == *"deploy-prod"* ]]
}

@test "unknown command errors with did-you-mean" {
  run "$TEST_DIR/bin/$CLI_NAME" hllo
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown command"* ]]
  [[ "$output" == *"hello"* ]]
}

@test "flag before command errors" {
  run "$TEST_DIR/bin/$CLI_NAME" -t hello
  [ "$status" -ne 0 ]
  [[ "$output" == *"flags must come after"* ]]
}

@test "subcommand before flags errors" {
  run "$TEST_DIR/bin/$CLI_NAME" deploy -t prod
  [ "$status" -ne 0 ]
  [[ "$output" == *"subcommand must come before"* ]]
  [[ "$output" == *"deploy prod -t"* ]]
}

@test "cache is auto-rebuilt when stale" {
  # First run: warm up
  "$TEST_DIR/bin/$CLI_NAME" hello > /dev/null

  # Touch a Taskfile to bump mtime
  sleep 1
  touch "$TEST_DIR/cmds/hello/Taskfile.yaml"

  # Next run should still succeed (auto-rebuild)
  run "$TEST_DIR/bin/$CLI_NAME" hello
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello-ran"* ]]
}

@test "-V echoes version directly" {
  run "$TEST_DIR/bin/$CLI_NAME" -V
  [ "$status" -eq 0 ]
  [[ "$output" == *"$CLI_NAME version $CLI_VERSION"* ]]
}

@test "--help on single-level command shows help" {
  run "$TEST_DIR/bin/$CLI_NAME" hello --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello"* ]]
  # Should NOT contain "hello-ran" — the command should not execute
  [[ "$output" != *"hello-ran"* ]]
}

@test "-h on single-level command shows help" {
  run "$TEST_DIR/bin/$CLI_NAME" hello -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello"* ]]
  [[ "$output" != *"hello-ran"* ]]
}

@test "--help on two-level command shows help" {
  run "$TEST_DIR/bin/$CLI_NAME" deploy prod --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"deploy"* ]]
  [[ "$output" != *"deploy-prod"* ]]
}

@test "--help works for non-routed commands" {
  # The hello command in this fixture doesn't route through router.sh
  # (it uses a bare cmd: echo). Before the fix, --help would have been
  # passed as a raw arg and the command would have run.
  run "$TEST_DIR/bin/$CLI_NAME" hello --help
  [ "$status" -eq 0 ]
  # detail.sh output contains the CLI name and command
  [[ "$output" == *"testcli"* ]]
  [[ "$output" == *"hello"* ]]
}
