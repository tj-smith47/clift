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
  export LOG_THEME="minimal"

  # Create a root Taskfile with standard framework-global flags so the parser
  # path fires for the existing tests (--version, --verbose, --quiet, --no-color).
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
dotenv: ['.env']
vars:
  FLAGS: []
includes:
  hello:
    taskfile: ./cmds/hello
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

  # Create a minimal hello command
  mkdir -p "$TEST_DIR/cmds/hello"
  cat > "$TEST_DIR/cmds/hello/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS: []
tasks:
  default:
    vars:
      FLAGS: []
    cmd: echo hello
YAML

  cat > "$TEST_DIR/cmds/hello/hello.sh" << 'SCRIPT'
#!/usr/bin/env bash
echo "hello output"
echo "VERBOSE=${VERBOSE:-unset}"
echo "QUIET=${QUIET:-unset}"
echo "NO_COLOR=${NO_COLOR:-unset}"
for arg in "$@"; do echo "arg=$arg"; done
SCRIPT
  chmod +x "$TEST_DIR/cmds/hello/hello.sh"

  # Precompile the flag cache
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$TEST_DIR"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "--version flag prints version" {
  CLI_ARGS="--version" run bash "$FRAMEWORK_DIR/lib/router/router.sh" "hello"
  [ "$status" -eq 0 ]
  [[ "$output" == *"testcli version 1.0.0"* ]]
}

@test "--version short flag -V prints version" {
  CLI_ARGS="-V" run bash "$FRAMEWORK_DIR/lib/router/router.sh" "hello"
  [ "$status" -eq 0 ]
  [[ "$output" == *"testcli version 1.0.0"* ]]
}

@test "--no-color sets NO_COLOR=1" {
  CLI_ARGS="--no-color" run bash "$FRAMEWORK_DIR/lib/router/router.sh" "hello"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NO_COLOR=1"* ]]
}

@test "--verbose sets VERBOSE=true" {
  CLI_ARGS="--verbose" run bash "$FRAMEWORK_DIR/lib/router/router.sh" "hello"
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERBOSE=true"* ]]
}

@test "-v sets VERBOSE=true" {
  CLI_ARGS="-v" run bash "$FRAMEWORK_DIR/lib/router/router.sh" "hello"
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERBOSE=true"* ]]
}

@test "--quiet sets QUIET=true" {
  CLI_ARGS="--quiet" run bash "$FRAMEWORK_DIR/lib/router/router.sh" "hello"
  [ "$status" -eq 0 ]
  [[ "$output" == *"QUIET=true"* ]]
}

@test "-q sets QUIET=true" {
  CLI_ARGS="-q" run bash "$FRAMEWORK_DIR/lib/router/router.sh" "hello"
  [ "$status" -eq 0 ]
  [[ "$output" == *"QUIET=true"* ]]
}

@test "unknown command shows error" {
  run -127 bash "$FRAMEWORK_DIR/lib/router/router.sh" "nonexistent" 2>&1
  [[ "$output" == *"Unknown command"* ]] || [[ "$output" == *"script not found"* ]]
}

@test "router without task name exits with error" {
  run bash "$FRAMEWORK_DIR/lib/router/router.sh" 2>&1
  [ "$status" -eq 1 ]
  [[ "$output" == *"error"* ]]
}

@test "hello command produces expected output" {
  run bash "$FRAMEWORK_DIR/lib/router/router.sh" "hello"
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello output"* ]]
}

@test "global flags are stripped from command args" {
  CLI_ARGS="--verbose --no-color" run bash "$FRAMEWORK_DIR/lib/router/router.sh" "hello"
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERBOSE=true"* ]]
  [[ "$output" == *"NO_COLOR=1"* ]]
  [[ "$output" == *"hello output"* ]]
}

@test "unknown flags rejected by parser in parsed mode" {
  CLI_ARGS="--name=test" run bash "$FRAMEWORK_DIR/lib/router/router.sh" "hello"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown flag"* ]]
}

# ── New contract tests ─────────────────────────────────────────────

@test "CLIFT_FLAG_* exported from parser in standard mode" {
  rm -rf "$TEST_DIR"/*
  mkdir -p "$TEST_DIR/cmds/greeter"
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
dotenv: ['.env']
vars:
  FLAGS:
    - {name: trace, short: t, type: bool}
includes:
  greeter:
    taskfile: ./cmds/greeter
tasks:
  default:
    cmd: echo root
YAML
  cat > "$TEST_DIR/.env" <<ENV
CLI_NAME=testcli
CLI_VERSION=1.0.0
CLI_DIR=$TEST_DIR
FRAMEWORK_DIR=$FRAMEWORK_DIR
ENV
  cat > "$TEST_DIR/cmds/greeter/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: name, short: n, type: string, default: world}
tasks:
  default:
    vars:
      FLAGS: []
    cmd: echo greeter
YAML
  cat > "$TEST_DIR/cmds/greeter/greeter.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "FLAG_TRACE=${CLIFT_FLAG_TRACE:-unset}"
echo "FLAG_NAME=${CLIFT_FLAG_NAME:-unset}"
echo "POS_1=${CLIFT_POS_1:-unset}"
SCRIPT
  chmod +x "$TEST_DIR/cmds/greeter/greeter.sh"

  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$TEST_DIR"

  CLIFT_ARG_COUNT=3 \
  CLIFT_ARG_1=--trace \
  CLIFT_ARG_2=--name \
  CLIFT_ARG_3=alice \
  CLI_DIR="$TEST_DIR" \
  run bash "$FRAMEWORK_DIR/lib/router/router.sh" "greeter"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FLAG_TRACE=true"* ]]
  [[ "$output" == *"FLAG_NAME=alice"* ]]
}

@test "passthrough: no vars.FLAGS → CLI_ARGS path" {
  rm -rf "$TEST_DIR"/*
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
dotenv: ['.env']
includes:
  plain:
    taskfile: ./cmds/plain
tasks:
  default:
    cmd: echo root
YAML
  cat > "$TEST_DIR/.env" <<ENV
CLI_NAME=testcli
CLI_VERSION=1.0.0
CLI_DIR=$TEST_DIR
FRAMEWORK_DIR=$FRAMEWORK_DIR
ENV
  mkdir -p "$TEST_DIR/cmds/plain"
  cat > "$TEST_DIR/cmds/plain/Taskfile.yaml" <<'YAML'
version: '3'
tasks:
  default:
    cmd: echo plain
YAML
  cat > "$TEST_DIR/cmds/plain/plain.sh" <<'SCRIPT'
#!/usr/bin/env bash
for a in "$@"; do echo "arg=$a"; done
SCRIPT
  chmod +x "$TEST_DIR/cmds/plain/plain.sh"

  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$TEST_DIR"

  CLI_ARGS='--foo bar' \
  CLI_DIR="$TEST_DIR" \
  run bash "$FRAMEWORK_DIR/lib/router/router.sh" "plain"
  [ "$status" -eq 0 ]
  [[ "$output" == *"arg=--foo"* ]]
  [[ "$output" == *"arg=bar"* ]]
}

@test "--help flag dispatches to detail.sh" {
  CLI_ARGS="--help" run bash "$FRAMEWORK_DIR/lib/router/router.sh" "hello"
  [ "$status" -eq 0 ]
  [[ "$output" == *"testcli"* ]]
  [[ "$output" == *"hello"* ]]
}

@test "CLIFT_ARG_COUNT standard mode args are passed to parser" {
  CLIFT_ARG_COUNT=1 \
  CLIFT_ARG_1="--verbose" \
  run bash "$FRAMEWORK_DIR/lib/router/router.sh" "hello"
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERBOSE=true"* ]]
}

@test "router without FRAMEWORK_DIR exits with error" {
  local fw="$FRAMEWORK_DIR"
  run -1 bash -c "unset FRAMEWORK_DIR; bash '$fw/lib/router/router.sh' 'hello' 2>&1"
  [[ "$output" == *"FRAMEWORK_DIR is not set"* ]]
}

@test "missing script for parsed command shows error" {
  # Remove the script but keep the compiled cache
  rm -f "$TEST_DIR/cmds/hello/hello.sh"
  CLI_ARGS="" run bash "$FRAMEWORK_DIR/lib/router/router.sh" "hello"
  [ "$status" -ne 0 ]
  [[ "$output" == *"script not found"* ]]
}

@test "subcommand resolves to its own script file" {
  rm -rf "$TEST_DIR"/*
  mkdir -p "$TEST_DIR/cmds/deploy"
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
dotenv: ['.env']
includes:
  deploy:
    taskfile: ./cmds/deploy
tasks:
  default:
    cmd: echo root
YAML
  cat > "$TEST_DIR/.env" <<ENV
CLI_NAME=testcli
CLI_VERSION=1.0.0
CLI_DIR=$TEST_DIR
FRAMEWORK_DIR=$FRAMEWORK_DIR
ENV
  cat > "$TEST_DIR/cmds/deploy/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS: []
tasks:
  default:
    vars: {FLAGS: []}
    cmd: echo deploy-default
  prod:
    vars: {FLAGS: []}
    cmd: echo deploy-prod
YAML
  cat > "$TEST_DIR/cmds/deploy/deploy.sh" << 'SCRIPT'
#!/usr/bin/env bash
echo "default-script"
SCRIPT
  cat > "$TEST_DIR/cmds/deploy/deploy.prod.sh" << 'SCRIPT'
#!/usr/bin/env bash
echo "prod-script"
SCRIPT
  chmod +x "$TEST_DIR/cmds/deploy/deploy.sh" "$TEST_DIR/cmds/deploy/deploy.prod.sh"

  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$TEST_DIR"

  CLIFT_ARG_COUNT=0 CLI_DIR="$TEST_DIR" \
  run bash "$FRAMEWORK_DIR/lib/router/router.sh" "deploy:prod"
  [ "$status" -eq 0 ]
  [[ "$output" == *"prod-script"* ]]
}
