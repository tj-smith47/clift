#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR"
  export FRAMEWORK_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export CLI_DIR="$TEST_DIR"
  export CLI_NAME="testcli"

  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
dotenv: ['.env']
vars:
  FLAGS:
    - {name: help,     short: h, type: bool, desc: "Show help"}
    - {name: verbose,  short: v, type: bool, desc: "Verbose output"}
    - {name: quiet,    short: q, type: bool, desc: "Suppress info/success output"}
    - {name: no-color,           type: bool, desc: "Disable color output"}
    - {name: version,            type: bool, desc: "Show version"}
includes:
  # User commands
tasks:
  default:
    cmd: echo ok
YAML
  cat > "$TEST_DIR/.env" <<EOF
CLI_NAME=testcli
FRAMEWORK_DIR=$FRAMEWORK_DIR
CLI_DIR=$TEST_DIR
EOF
  mkdir -p "$TEST_DIR/cmds"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "new:cmd creates Taskfile and script with FLAGS stub" {
  bash "$FRAMEWORK_DIR/lib/scaffold/scaffold.sh" "deploy" "Deploy things" "$TEST_DIR" "$FRAMEWORK_DIR"
  [ -f "$TEST_DIR/cmds/deploy/Taskfile.yaml" ]
  [ -x "$TEST_DIR/cmds/deploy/deploy.sh" ]
  run grep -c 'FLAGS:' "$TEST_DIR/cmds/deploy/Taskfile.yaml"
  [ "$output" -ge 1 ]
}

@test "new:cmd rejects invalid name" {
  run bash "$FRAMEWORK_DIR/lib/scaffold/scaffold.sh" "-bad" "x" "$TEST_DIR" "$FRAMEWORK_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"command names"* ]]
}

@test "new:subcmd creates separate script file per subcommand" {
  bash "$FRAMEWORK_DIR/lib/scaffold/scaffold.sh" "deploy" "Deploy" "$TEST_DIR" "$FRAMEWORK_DIR"
  bash "$FRAMEWORK_DIR/lib/scaffold/scaffold.sh" "deploy:prod" "Deploy to prod" "$TEST_DIR" "$FRAMEWORK_DIR"
  [ -f "$TEST_DIR/cmds/deploy/deploy.sh" ]
  [ -f "$TEST_DIR/cmds/deploy/deploy.prod.sh" ]
}

@test "new:cmd regenerates .clift cache" {
  bash "$FRAMEWORK_DIR/lib/scaffold/scaffold.sh" "deploy" "Deploy" "$TEST_DIR" "$FRAMEWORK_DIR"
  [ -f "$TEST_DIR/.clift/tasks.json" ]
  [ -f "$TEST_DIR/.clift/flags.json" ]
}

@test "new:cmd rejects Taskfile with invalid FLAGS (via validator)" {
  mkdir -p "$TEST_DIR/cmds/bad"
  cat > "$TEST_DIR/cmds/bad/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: bad_name, type: bool}
tasks:
  default:
    cmd: echo bad
YAML
  sed -i 's|# User commands|\0\n  bad:\n    taskfile: ./cmds/bad|' "$TEST_DIR/Taskfile.yaml"
  run bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$TEST_DIR"
  [ "$status" -ne 0 ]
}
