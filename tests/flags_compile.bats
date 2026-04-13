#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR"
  export FRAMEWORK_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export CLI_DIR="$TEST_DIR"

  # Minimal CLI layout with one command
  # NOTE: cannot use `help`/`verbose` here — validate.sh reserves those as
  # framework globals. Use neutral root-level flags (`trace`, `debug`) that
  # still exercise the root -> command -> task merge path.
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
dotenv: ['.env']
vars:
  FLAGS:
    - {name: trace, short: t, type: bool, desc: "Trace mode"}
    - {name: debug, short: d, type: bool, desc: "Debug mode"}
includes:
  greet:
    taskfile: ./cmds/greet
tasks:
  default:
    cmd: echo hello
YAML
  echo "CLI_NAME=testcli" > "$TEST_DIR/.env"

  mkdir -p "$TEST_DIR/cmds/greet"
  cat > "$TEST_DIR/cmds/greet/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: name, short: n, type: string, default: world, desc: "Who to greet"}
tasks:
  default:
    vars:
      FLAGS:
        - {name: loud, short: l, type: bool, desc: "Shout"}
    cmd: "'{{.FRAMEWORK_DIR}}/lib/router/router.sh' '{{.TASK}}'"
YAML
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "fresh compile creates all three cache files" {
  run bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
  [ "$status" -eq 0 ]
  [ -f "$CLI_DIR/.clift/tasks.json" ]
  [ -f "$CLI_DIR/.clift/flags.json" ]
  [ -f "$CLI_DIR/.clift/checksum" ]
}

@test "tasks.json contains greet namespace" {
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
  run jq -r '[.. | .tasks? // empty | .[] | .name] | .[]' "$CLI_DIR/.clift/tasks.json"
  [[ "$output" == *"greet"* ]]
}

@test "flags.json merges root + command + task for greet" {
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
  run jq -r '(.["greet"] // .["greet:default"]) | map(.name) | .[]' "$CLI_DIR/.clift/flags.json"
  [[ "$output" == *"trace"* ]]      # from root
  [[ "$output" == *"debug"* ]]      # from root
  [[ "$output" == *"name"* ]]       # from command
  [[ "$output" == *"loud"* ]]       # from task
}

@test "checksum is max mtime across relevant taskfiles" {
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
  local checksum_before
  checksum_before="$(cat "$CLI_DIR/.clift/checksum")"

  # Touch the command Taskfile to bump its mtime forward
  sleep 1
  touch "$CLI_DIR/cmds/greet/Taskfile.yaml"

  # Recompute what the checksum *would* be without rebuilding
  local current_max
  source "$FRAMEWORK_DIR/lib/cache.sh"
  current_max="$(clift_max_mtime "$CLI_DIR/Taskfile.yaml" "$CLI_DIR/cmds/"*/Taskfile.yaml)"
  [ "$current_max" != "$checksum_before" ]
}

@test "compile emits warning when command shadows global short alias" {
  # Command declares -t for --target, shadowing the root-level -t for --trace
  cat > "$CLI_DIR/cmds/greet/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: target, short: t, type: string}
tasks:
  default:
    vars:
      FLAGS: []
    cmd: "'{{.FRAMEWORK_DIR}}/lib/router/router.sh' '{{.TASK}}'"
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"shadows global short -t"* ]]
}

@test "compile requires valid CLI directory" {
  run bash "$FRAMEWORK_DIR/lib/flags/compile.sh" ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires a valid CLI directory"* ]]
}

@test "compile fails when no Taskfile.yaml exists" {
  local empty_dir="$(mktemp -d)"
  run bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$empty_dir"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no Taskfile.yaml"* ]]
  rm -rf "$empty_dir"
}

@test "compile sources manifest lists all tracked files" {
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
  [ -f "$CLI_DIR/.clift/sources" ]
  # Should include root Taskfile and the command Taskfile
  grep -q "Taskfile.yaml" "$CLI_DIR/.clift/sources"
}

@test "compile with yq failure on command Taskfile exits non-zero" {
  # Create an invalid YAML file
  echo "{{{{invalid" > "$CLI_DIR/cmds/greet/Taskfile.yaml"
  run bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
  [ "$status" -ne 0 ]
}

@test "command without vars.FLAGS marked passthrough" {
  mkdir -p "$CLI_DIR/cmds/old"
  cat > "$CLI_DIR/cmds/old/Taskfile.yaml" <<'YAML'
version: '3'
tasks:
  default:
    cmd: echo old
YAML
  # Add the include in the root Taskfile
  _tmp="$(mktemp)"
  sed 's|includes:|includes:\n  old:\n    taskfile: ./cmds/old|' "$CLI_DIR/Taskfile.yaml" > "$_tmp"
  mv "$_tmp" "$CLI_DIR/Taskfile.yaml"

  run bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
  [ "$status" -eq 0 ]
  run jq -r '.["old:default"].passthrough // .["old"].passthrough // false' "$CLI_DIR/.clift/flags.json"
  [ "$output" = "true" ]
}
