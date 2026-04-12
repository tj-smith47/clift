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

  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
dotenv: ['.env']
vars:
  FLAGS:
    - {name: help, short: h, type: bool, desc: "Show help"}
    - {name: verbose, short: v, type: bool, desc: "Verbose output"}
includes:
  deploy:
    taskfile: ./cmds/deploy
tasks:
  default:
    cmd: echo root
YAML
  echo "CLI_NAME=testcli" > "$TEST_DIR/.env"

  mkdir -p "$TEST_DIR/cmds/deploy"
  cat > "$TEST_DIR/cmds/deploy/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: target, short: t, type: string, default: staging, desc: "Target env"}
tasks:
  default:
    desc: "Deploy something"
    vars:
      FLAGS:
        - {name: force, short: f, type: bool, desc: "Skip confirm"}
    cmd: echo deploy
YAML

  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$TEST_DIR"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "list.sh includes Global Flags section" {
  run bash "$FRAMEWORK_DIR/lib/help/list.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Global Flags"* ]]
  [[ "$output" == *"--help"* ]]
  [[ "$output" == *"--verbose"* ]]
}

@test "detail.sh renders command flags" {
  run bash "$FRAMEWORK_DIR/lib/help/detail.sh" "deploy" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Flags"* ]]
  [[ "$output" == *"--target"* ]]
  [[ "$output" == *"--force"* ]]
}

@test "detail.sh shows type hints and defaults" {
  run bash "$FRAMEWORK_DIR/lib/help/detail.sh" "deploy" "$TEST_DIR/Taskfile.yaml"
  [[ "$output" == *"<string>"* ]]
  [[ "$output" == *"default: staging"* ]]
}
