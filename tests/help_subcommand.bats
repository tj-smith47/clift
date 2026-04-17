#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

# Task 6.0 — `mycli help <cmd>` is sugar for `mycli <cmd> --help`.
# Cobra-parity ergonomic. Bare `mycli help` falls through to the global
# help renderer. A user-defined `help` task wins (no shadowing).

load test_helper

_setup_cli_with_help_alias() {
  cat > "$CLI_DIR/Taskfile.yaml" <<YAML
version: '3'
silent: true
vars:
  FLAGS:
    - {name: help, short: h, type: bool, desc: "Show help"}
    - {name: no-cache, type: bool, desc: "Force-rebuild the .clift cache"}
includes:
  _help:
    taskfile: '${FRAMEWORK_DIR}/lib/help'
  greet:
    taskfile: ./cmds/greet
tasks:
  default:
    cmd: task --taskfile {{.ROOT_TASKFILE}} _help:list
YAML

  cat > "$CLI_DIR/.env" <<ENV
CLI_NAME=$CLI_NAME
CLI_VERSION=$CLI_VERSION
CLI_DIR=$CLI_DIR
FRAMEWORK_DIR=$FRAMEWORK_DIR
CLIFT_MODE=standard
LOG_THEME=minimal
ENV

  mkdir -p "$CLI_DIR/cmds/greet"
  cat > "$CLI_DIR/cmds/greet/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS: []
tasks:
  default:
    desc: "Say hello"
    aliases: [g]
    vars:
      FLAGS: []
    cmd: echo greet-ran
YAML

  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
  build_test_wrapper
}

_setup_cli_with_real_help_command() {
  cat > "$CLI_DIR/Taskfile.yaml" <<YAML
version: '3'
silent: true
vars:
  FLAGS:
    - {name: help, short: h, type: bool, desc: "Show help"}
    - {name: no-cache, type: bool, desc: "Force-rebuild the .clift cache"}
includes:
  _help:
    taskfile: '${FRAMEWORK_DIR}/lib/help'
  help:
    taskfile: ./cmds/help
tasks:
  default:
    cmd: echo root
YAML

  cat > "$CLI_DIR/.env" <<ENV
CLI_NAME=$CLI_NAME
CLI_VERSION=$CLI_VERSION
CLI_DIR=$CLI_DIR
FRAMEWORK_DIR=$FRAMEWORK_DIR
CLIFT_MODE=standard
LOG_THEME=minimal
ENV

  mkdir -p "$CLI_DIR/cmds/help"
  cat > "$CLI_DIR/cmds/help/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS: []
tasks:
  default:
    desc: "User-defined help"
    vars:
      FLAGS: []
    cmd: echo user-help-ran
YAML

  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
  build_test_wrapper
}

@test "help <cmd> renders the canonical's detail page" {
  _setup_cli_with_help_alias
  run "$CLI_DIR/bin/$CLI_NAME" help greet
  [ "$status" -eq 0 ]
  # Detail-page header line: `<cli> <cmd> - <desc>`
  [[ "$output" == *"$CLI_NAME greet - Say hello"* ]]
}

@test "help <alias> resolves to the canonical's detail page" {
  _setup_cli_with_help_alias
  run "$CLI_DIR/bin/$CLI_NAME" help g
  [ "$status" -eq 0 ]
  [[ "$output" == *"$CLI_NAME greet - Say hello"* ]]
}

@test "bare 'help' falls through to the global help listing" {
  _setup_cli_with_help_alias
  run "$CLI_DIR/bin/$CLI_NAME" help
  [ "$status" -eq 0 ]
  # Global help shows the version header and the Commands section
  [[ "$output" == *"version"* ]]
  [[ "$output" == *"greet"* ]]
}

@test "user-defined 'help' command wins over the rewrite" {
  _setup_cli_with_real_help_command
  run "$CLI_DIR/bin/$CLI_NAME" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"user-help-ran"* ]]
}
