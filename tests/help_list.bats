#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR"
  export FRAMEWORK_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export CLI_DIR="$TEST_DIR"
  export CLI_NAME="testcli"
  export CLI_VERSION="2.0.0"
  export CLIFT_MODE="standard"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Helper: create a CLI with commands and precompile cache
_setup_cli_with_commands() {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
dotenv: ['.env']
vars:
  FLAGS:
    - {name: help, short: h, type: bool, desc: "Show help"}
    - {name: verbose, short: v, type: bool, desc: "Verbose output"}
    - {name: quiet, short: q, type: bool, desc: "Suppress output"}
    - {name: no-color, type: bool, desc: "Disable color"}
    - {name: version, type: bool, desc: "Show version"}
includes:
  deploy:
    taskfile: ./cmds/deploy
  status:
    taskfile: ./cmds/status
  # User commands
tasks:
  default:
    cmd: echo root
YAML

  cat > "$TEST_DIR/.env" <<ENV
CLI_NAME=$CLI_NAME
CLI_VERSION=$CLI_VERSION
CLI_DIR=$TEST_DIR
FRAMEWORK_DIR=$FRAMEWORK_DIR
CLIFT_MODE=standard
LOG_THEME=minimal
ENV

  mkdir -p "$TEST_DIR/cmds/deploy"
  cat > "$TEST_DIR/cmds/deploy/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS: []
tasks:
  default:
    desc: "Deploy the app"
    vars:
      FLAGS: []
    cmd: echo deploy
  prod:
    desc: "Deploy to production"
    vars:
      FLAGS: []
    cmd: echo deploy-prod
YAML

  mkdir -p "$TEST_DIR/cmds/status"
  cat > "$TEST_DIR/cmds/status/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS: []
tasks:
  default:
    desc: "Show status"
    vars:
      FLAGS: []
    cmd: echo status
  pods:
    desc: "Show pod status"
    vars:
      FLAGS: []
    cmd: echo pods
YAML

  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$TEST_DIR"
}

@test "list.sh prints CLI name and version in header" {
  _setup_cli_with_commands
  run bash "$FRAMEWORK_DIR/lib/help/list.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"testcli"* ]]
  [[ "${lines[0]}" == *"2.0.0"* ]]
}

@test "list.sh shows subcommand names from namespaces" {
  _setup_cli_with_commands
  run bash "$FRAMEWORK_DIR/lib/help/list.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"deploy prod"* ]]
  [[ "$output" == *"status pods"* ]]
}

@test "list.sh shows command descriptions" {
  _setup_cli_with_commands
  run bash "$FRAMEWORK_DIR/lib/help/list.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Deploy to production"* ]]
  [[ "$output" == *"Show pod status"* ]]
}

@test "list.sh shows task mode help hint when CLIFT_MODE=task" {
  _setup_cli_with_commands
  export CLIFT_MODE=task
  run bash "$FRAMEWORK_DIR/lib/help/list.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *":help"* ]]
}

@test "list.sh renders Global Flags section" {
  _setup_cli_with_commands
  run bash "$FRAMEWORK_DIR/lib/help/list.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Global Flags:"* ]]
  [[ "$output" == *"--help"* ]]
  [[ "$output" == *"--verbose"* ]]
}

@test "list.sh shows (no commands found) for empty CLI" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
dotenv: ['.env']
vars:
  FLAGS:
    - {name: help, short: h, type: bool, desc: "Show help"}
includes:
tasks:
  default:
    cmd: echo root
YAML
  cat > "$TEST_DIR/.env" <<ENV
CLI_NAME=$CLI_NAME
CLI_VERSION=$CLI_VERSION
CLI_DIR=$TEST_DIR
FRAMEWORK_DIR=$FRAMEWORK_DIR
ENV
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$TEST_DIR"

  run bash "$FRAMEWORK_DIR/lib/help/list.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no commands found"* ]]
}

@test "list.sh requires taskfile path argument" {
  run bash "$FRAMEWORK_DIR/lib/help/list.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires taskfile path"* ]]
}

@test "list.sh works without tasks.json cache (falls back to task CLI)" {
  _setup_cli_with_commands
  rm -f "$TEST_DIR/.clift/tasks.json"
  run bash "$FRAMEWORK_DIR/lib/help/list.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"testcli"* ]]
}

@test "list.sh uses title-cased namespace as group name" {
  _setup_cli_with_commands
  run bash "$FRAMEWORK_DIR/lib/help/list.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  # "deploy" namespace → "Deploy:" group, "status" namespace → "Status:" group
  [[ "$output" == *"Deploy:"* ]]
  [[ "$output" == *"Status:"* ]]
}

@test "list.sh filters out _-prefixed namespaces" {
  _setup_cli_with_commands
  run bash "$FRAMEWORK_DIR/lib/help/list.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  # Internal framework tasks (if any) should not appear
  [[ "$output" != *"_"* ]] || {
    # OK if _ appears inside a description, just not as a command prefix
    local lines_with_underscore_cmd
    lines_with_underscore_cmd=$(echo "$output" | grep -cE '^\s+_' || true)
    [ "$lines_with_underscore_cmd" -eq 0 ]
  }
}

