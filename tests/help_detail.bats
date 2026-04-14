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
    - {name: quiet, short: q, type: bool, desc: "Suppress output"}
    - {name: no-color, type: bool, desc: "Disable color"}
    - {name: version, type: bool, desc: "Show version"}
includes:
  greet:
    taskfile: ./cmds/greet
  plain:
    taskfile: ./cmds/plain
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

  # Command with flags and summary
  mkdir -p "$TEST_DIR/cmds/greet"
  cat > "$TEST_DIR/cmds/greet/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: name, short: n, type: string, default: world, desc: "Name to greet"}
    - {name: loud, type: bool, desc: "Use uppercase"}
tasks:
  default:
    desc: "Greet someone"
    summary: |
      Greet someone by name.

      Examples:
        testcli greet --name Alice
        testcli greet --loud
    vars:
      FLAGS:
        - {name: name, short: n, type: string, default: world, desc: "Name to greet"}
        - {name: loud, type: bool, desc: "Use uppercase"}
    cmd: echo greet
YAML

  # Passthrough command (no FLAGS)
  mkdir -p "$TEST_DIR/cmds/plain"
  cat > "$TEST_DIR/cmds/plain/Taskfile.yaml" <<'YAML'
version: '3'
tasks:
  default:
    desc: "A plain passthrough command"
    cmd: echo plain
YAML

  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$TEST_DIR"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "detail.sh shows CLI name and command in header" {
  run bash "$FRAMEWORK_DIR/lib/help/detail.sh" "greet" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"testcli"* ]]
  [[ "${lines[0]}" == *"greet"* ]]
}

@test "detail.sh shows command description" {
  run bash "$FRAMEWORK_DIR/lib/help/detail.sh" "greet" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Greet someone"* ]]
}

@test "detail.sh shows summary text" {
  run bash "$FRAMEWORK_DIR/lib/help/detail.sh" "greet" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Greet someone by name"* ]]
  [[ "$output" == *"Examples:"* ]]
}

@test "detail.sh shows local Flags section" {
  run bash "$FRAMEWORK_DIR/lib/help/detail.sh" "greet" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Flags:"* ]]
  [[ "$output" == *"--name"* ]]
  [[ "$output" == *"--loud"* ]]
}

@test "detail.sh shows Global Flags section" {
  run bash "$FRAMEWORK_DIR/lib/help/detail.sh" "greet" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Global Flags:"* ]]
  [[ "$output" == *"--help"* ]]
  [[ "$output" == *"--verbose"* ]]
}

@test "detail.sh shows flag defaults" {
  run bash "$FRAMEWORK_DIR/lib/help/detail.sh" "greet" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"default: world"* ]]
}

@test "detail.sh shows 'no detailed help' for command without summary" {
  run bash "$FRAMEWORK_DIR/lib/help/detail.sh" "plain" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No detailed help"* ]]
}

@test "detail.sh exits with error for unknown command" {
  run bash "$FRAMEWORK_DIR/lib/help/detail.sh" "nonexistent" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown command"* ]]
}

@test "detail.sh falls back to task CLI when tasks.json cache is missing" {
  rm -f "$TEST_DIR/.clift/tasks.json"
  run bash "$FRAMEWORK_DIR/lib/help/detail.sh" "greet" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Greet someone"* ]]
}

@test "detail.sh exits with error when taskfile is unreadable by task CLI" {
  # Removing the cache AND corrupting the Taskfile forces the task CLI
  # fallback to fail — the error must be specific, not silent.
  rm -f "$TEST_DIR/.clift/tasks.json"
  echo "not valid yaml: [[[" > "$TEST_DIR/Taskfile.yaml"
  run bash "$FRAMEWORK_DIR/lib/help/detail.sh" "greet" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed to read task list"* ]]
}

@test "detail.sh requires both command and taskfile args" {
  run bash "$FRAMEWORK_DIR/lib/help/detail.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires"* ]]
}

@test "detail.sh converts colon to space in display for user commands" {
  # Add a subcommand task to the greet Taskfile
  cat >> "$TEST_DIR/cmds/greet/Taskfile.yaml" <<'YAML'

  loud:
    desc: "Greet loudly"
    vars:
      FLAGS: []
    cmd: echo greet-loud
YAML
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$TEST_DIR"

  run bash "$FRAMEWORK_DIR/lib/help/detail.sh" "greet:loud" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"testcli greet loud"* ]]
}

@test "detail.sh passthrough command shows desc without flag sections" {
  run bash "$FRAMEWORK_DIR/lib/help/detail.sh" "plain" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"plain"* ]]
  [[ "$output" == *"passthrough"* ]]
}

@test "detail.sh lists subcommands when command has children" {
  # Add subcommands to greet
  cat >> "$TEST_DIR/cmds/greet/Taskfile.yaml" <<'YAML'

  loud:
    desc: "Greet loudly"
    vars:
      FLAGS: []
    cmd: echo greet-loud
  quiet:
    desc: "Greet quietly"
    vars:
      FLAGS: []
    cmd: echo greet-quiet
YAML
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$TEST_DIR"

  run bash "$FRAMEWORK_DIR/lib/help/detail.sh" "greet" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Available commands:"* ]]
  [[ "$output" == *"greet loud"* ]]
  [[ "$output" == *"greet quiet"* ]]
  [[ "$output" == *"Greet loudly"* ]]
  [[ "$output" == *"Greet quietly"* ]]
}

@test "detail.sh omits subcommand listing for leaf commands" {
  run bash "$FRAMEWORK_DIR/lib/help/detail.sh" "greet" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  # No subcommands beyond default, so no "Available commands:" section
  [[ "$output" != *"Available commands:"* ]]
}

@test "render_flags formats flag with short alias and type hint" {
  source "$FRAMEWORK_DIR/lib/help/render_flags.sh"
  run clift_render_flags '[{"name":"target","short":"t","type":"string","default":"staging","desc":"Target env"}]'
  [ "$status" -eq 0 ]
  [[ "$output" == *"-t"* ]]
  [[ "$output" == *"--target"* ]]
  [[ "$output" == *"<string>"* ]]
  [[ "$output" == *"default: staging"* ]]
}

@test "render_flags shows required marker" {
  source "$FRAMEWORK_DIR/lib/help/render_flags.sh"
  run clift_render_flags '[{"name":"service","type":"string","required":true,"desc":"Service name"}]'
  [ "$status" -eq 0 ]
  [[ "$output" == *"--service"* ]]
  [[ "$output" == *"(required)"* ]]
}

@test "render_flags hides type hint for bool flags" {
  source "$FRAMEWORK_DIR/lib/help/render_flags.sh"
  run clift_render_flags '[{"name":"force","short":"f","type":"bool","desc":"Skip confirm"}]'
  [ "$status" -eq 0 ]
  [[ "$output" == *"--force"* ]]
  [[ "$output" != *"<bool>"* ]]
}

@test "render_flags handles flag without short alias" {
  source "$FRAMEWORK_DIR/lib/help/render_flags.sh"
  run clift_render_flags '[{"name":"no-color","type":"bool","desc":"Disable color"}]'
  [ "$status" -eq 0 ]
  [[ "$output" == *"--no-color"* ]]
}
