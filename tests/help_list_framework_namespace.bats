#!/usr/bin/env bats
# Tier 3H — help list rendering when `framework_namespace` is set in
# `.clift.yaml`. The framework's built-in commands (config, version,
# update, etc.) are mounted under the chosen namespace via
# `lib/_framework_aggregate.yaml` and the help listing collapses them
# into a single `<ns>:*` row instead of repeating each framework
# command at the top level.
#
# Control test verifies the legacy shape (no framework_namespace) is
# untouched.

bats_require_minimum_version 1.5.0

load test_helper

# Build a CLI under $CLI_DIR with `framework_namespace: <ns>` set in
# .clift.yaml plus an aggregator-style root Taskfile that mounts the
# framework under <ns>. Mirrors tier 3G's framework_namespace.bats
# fixture so the surface under test matches the real init output.
_setup_namespaced_cli_for_help() {
  local ns="${1:-clift}"

  cat > "$CLI_DIR/.clift.yaml" <<YAML
name: ${CLI_NAME}
version: ${CLI_VERSION}
description: ""
framework_namespace: ${ns}
dependencies:
  required: []
  optional: []
YAML

  cat > "$CLI_DIR/Taskfile.yaml" <<YAML
version: '3'
silent: true
dotenv: ['.env']

vars:
  FLAGS:
    - {name: help, short: h, type: bool, desc: "Show help"}
    - {name: verbose, short: v, type: bool, desc: "Verbose"}
    - {name: version, type: bool, desc: "Show version"}

includes:
  ${ns}:
    taskfile: '${FRAMEWORK_DIR}/lib/_framework_aggregate.yaml'
  build:
    taskfile: ./cmds/build

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

  mkdir -p "$CLI_DIR/cmds/build"
  cat > "$CLI_DIR/cmds/build/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS: []
tasks:
  default:
    desc: "Build the project"
    vars:
      FLAGS: []
    cmd: echo build
YAML

  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
}

# Baseline CLI without framework_namespace — framework lives at the top
# level via per-command includes. Used to assert the legacy render is
# unchanged.
_setup_legacy_cli_for_help() {
  cat > "$CLI_DIR/.clift.yaml" <<YAML
name: ${CLI_NAME}
version: ${CLI_VERSION}
description: ""
dependencies:
  required: []
  optional: []
YAML

  cat > "$CLI_DIR/Taskfile.yaml" <<YAML
version: '3'
silent: true
dotenv: ['.env']

vars:
  FLAGS:
    - {name: help, short: h, type: bool, desc: "Show help"}

includes:
  config:
    taskfile: '${FRAMEWORK_DIR}/lib/config'
  version:
    taskfile: '${FRAMEWORK_DIR}/lib/version'
  build:
    taskfile: ./cmds/build

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

  mkdir -p "$CLI_DIR/cmds/build"
  cat > "$CLI_DIR/cmds/build/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS: []
tasks:
  default:
    desc: "Build the project"
    vars:
      FLAGS: []
    cmd: echo build
YAML

  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
}

@test "list.sh collapses framework namespace into a single <ns>:* row" {
  _setup_namespaced_cli_for_help clift
  run bash "$FRAMEWORK_DIR/lib/help/list.sh" "$CLI_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"clift:*"* ]]
  [[ "$output" == *"Framework commands"* ]]
  [[ "$output" == *"run \`${CLI_NAME} clift\` to list"* ]]
}

@test "list.sh keeps user commands at top level under framework_namespace" {
  _setup_namespaced_cli_for_help clift
  run bash "$FRAMEWORK_DIR/lib/help/list.sh" "$CLI_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"build"* ]]
  [[ "$output" == *"Build the project"* ]]
}

@test "list.sh suppresses individual framework rows under framework_namespace" {
  _setup_namespaced_cli_for_help clift
  run bash "$FRAMEWORK_DIR/lib/help/list.sh" "$CLI_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  # No top-level `config` or `version` rows — they collapsed into clift:*.
  # Use anchored grep so a substring match in `clift:*` row description
  # (which contains the word "list" but not "config"/"version") cannot
  # produce a false positive.
  local config_rows version_rows update_rows
  config_rows=$(echo "$output"  | grep -cE '^\s+config\b'  || true)
  version_rows=$(echo "$output" | grep -cE '^\s+version\b' || true)
  update_rows=$(echo "$output"  | grep -cE '^\s+update\b'  || true)
  [ "$config_rows"  -eq 0 ]
  [ "$version_rows" -eq 0 ]
  [ "$update_rows"  -eq 0 ]
}

@test "list.sh honors arbitrary framework_namespace name" {
  _setup_namespaced_cli_for_help fw
  run bash "$FRAMEWORK_DIR/lib/help/list.sh" "$CLI_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fw:*"* ]]
  [[ "$output" == *"run \`${CLI_NAME} fw\` to list"* ]]
  [[ "$output" != *"clift:*"* ]]
}

@test "list.sh leaves legacy (no framework_namespace) render unchanged" {
  _setup_legacy_cli_for_help
  run bash "$FRAMEWORK_DIR/lib/help/list.sh" "$CLI_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  # Per-command rows still present at top level.
  [[ "$output" == *"build"* ]]
  [[ "$output" == *"config"* ]]
  [[ "$output" == *"version"* ]]
  # No collapsed clift:* row.
  [[ "$output" != *"clift:*"* ]]
  [[ "$output" != *"Framework commands (run"* ]]
}
