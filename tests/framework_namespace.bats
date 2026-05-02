#!/usr/bin/env bats
# Tests for tier 3G — framework_namespace mode.
#
# When `.clift.yaml` declares `framework_namespace: <ns>`, the CLI's root
# Taskfile includes the framework via the `_framework_aggregate.yaml`
# aggregator under `<ns>:`. Built-in commands then resolve as
# `mycli <ns>:config show`, `mycli <ns>:version`, etc., and the top
# level stays free of framework collisions.
#
# These tests assert task-name resolution only — they do not invoke the
# framework commands' bodies (which would touch real config dirs).

bats_require_minimum_version 1.5.0

load test_helper

# Build a CLI under $CLI_DIR/mycli that opts into `framework_namespace: clift`.
# The root Taskfile uses the aggregator include pattern; the user's top
# level stays free for its own commands.
_setup_namespaced_cli() {
  local ns="${1:-clift}"
  local cli_root="$CLI_DIR/mycli"
  mkdir -p "$cli_root"

  cat > "$cli_root/.clift.yaml" <<YAML
name: mycli
version: 0.1.0
description: ""
framework_namespace: ${ns}
dependencies:
  required: []
  optional: []
YAML

  # Root Taskfile — mounts the aggregator under <ns>:, leaves the top
  # level free for user commands.
  cat > "$cli_root/Taskfile.yaml" <<YAML
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

tasks:
  default:
    cmd: echo root
YAML

  cat > "$cli_root/.env" <<ENV
CLI_NAME=mycli
CLI_VERSION=0.1.0
CLI_DIR=$cli_root
FRAMEWORK_DIR=$FRAMEWORK_DIR
CLIFT_MODE=standard
LOG_THEME=minimal
ENV
}

# Build a baseline CLI without framework_namespace — no aggregator
# include, framework commands stay top-level via per-command includes.
# Used to assert the legacy shape still works alongside the new mode.
_setup_legacy_cli() {
  local cli_root="$CLI_DIR/legacy"
  mkdir -p "$cli_root"

  cat > "$cli_root/.clift.yaml" <<YAML
name: legacy
version: 0.1.0
description: ""
dependencies:
  required: []
  optional: []
YAML

  cat > "$cli_root/Taskfile.yaml" <<YAML
version: '3'
silent: true
dotenv: ['.env']

includes:
  config:
    taskfile: '${FRAMEWORK_DIR}/lib/config'
  version:
    taskfile: '${FRAMEWORK_DIR}/lib/version'

tasks:
  default:
    cmd: echo root
YAML

  cat > "$cli_root/.env" <<ENV
CLI_NAME=legacy
CLI_VERSION=0.1.0
CLI_DIR=$cli_root
FRAMEWORK_DIR=$FRAMEWORK_DIR
CLIFT_MODE=standard
LOG_THEME=minimal
ENV
}

@test "aggregator file is parseable by yq" {
  run yq -e '.includes' "$FRAMEWORK_DIR/lib/_framework_aggregate.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"config"* ]]
  [[ "$output" == *"version"* ]]
  [[ "$output" == *"update"* ]]
  [[ "$output" == *"completion"* ]]
  [[ "$output" == *"new"* ]]
}

@test "aggregator file declares version 3" {
  run yq -e '.version' "$FRAMEWORK_DIR/lib/_framework_aggregate.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == "3"* || "$output" == "'3'" ]]
}

@test "framework_namespace=clift mounts framework commands under clift:*" {
  _setup_namespaced_cli clift

  run task --list-all --taskfile "$CLI_DIR/mycli/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"clift:config:show"* ]]
  [[ "$output" == *"clift:version"* ]]
  [[ "$output" == *"clift:update"* ]]
  [[ "$output" == *"clift:completion:bash"* ]]
}

@test "framework_namespace=clift leaves top-level config unbound" {
  _setup_namespaced_cli clift

  # Top-level `config` must NOT exist when only the aggregator is mounted.
  run task --list-all --taskfile "$CLI_DIR/mycli/Taskfile.yaml"
  [ "$status" -eq 0 ]
  # Look for a literal "* config:" entry (the list-all format) — would
  # indicate a top-level config task. A `clift:config:*` entry is fine.
  ! [[ "$output" =~ \*\ config: ]]
  ! [[ "$output" =~ \*\ version: ]]
  ! [[ "$output" =~ \*\ update: ]]
}

@test "framework_namespace=clift makes clift:version task reachable" {
  _setup_namespaced_cli clift

  # --summary resolves the task without running it; proves the name is
  # bound and the include chain works without invoking the cmd body
  # (which would touch real config dirs).
  run task --summary --taskfile "$CLI_DIR/mycli/Taskfile.yaml" 'clift:version'
  [ "$status" -eq 0 ]
  [[ "$output" == *"version"* ]]
}

@test "framework_namespace=clift makes clift:config:show task reachable" {
  _setup_namespaced_cli clift

  run task --summary --taskfile "$CLI_DIR/mycli/Taskfile.yaml" 'clift:config:show'
  [ "$status" -eq 0 ]
  [[ "$output" == *"config"* ]]
}

@test "top-level version task is unbound when framework_namespace is set" {
  _setup_namespaced_cli clift

  run task --taskfile "$CLI_DIR/mycli/Taskfile.yaml" version
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]] || [[ "$output" == *"not found"* ]] || [[ "$output" == *"No tasks"* ]]
}

@test "top-level config task is unbound when framework_namespace is set" {
  _setup_namespaced_cli clift

  run task --taskfile "$CLI_DIR/mycli/Taskfile.yaml" config
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]] || [[ "$output" == *"not found"* ]] || [[ "$output" == *"No tasks"* ]]
}

@test "framework_namespace honors arbitrary namespace name" {
  # Prove the aggregator works under any chosen namespace, not just `clift`.
  _setup_namespaced_cli fw

  run task --list-all --taskfile "$CLI_DIR/mycli/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fw:config:show"* ]]
  [[ "$output" == *"fw:version"* ]]
}

@test "CLI without framework_namespace continues to expose top-level commands" {
  _setup_legacy_cli

  run task --list-all --taskfile "$CLI_DIR/legacy/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"config:show"* ]]
  [[ "$output" == *"version:default"* || "$output" == *"version "* ]]
  # No clift:* entries.
  ! [[ "$output" == *"clift:"* ]]
}

@test ".clift.yaml.tmpl surfaces framework_namespace as commented schema" {
  run grep -E '^# framework_namespace:' "$FRAMEWORK_DIR/templates/cli/.clift.yaml.tmpl"
  [ "$status" -eq 0 ]
}
