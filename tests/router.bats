#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export FRAMEWORK_DIR="/opt/repos/task-cli"
  export CLI_DIR="$TEST_DIR"
  export CLI_NAME="testcli"
  export CLI_VERSION="1.0.0"
  export LOG_THEME="minimal"

  # Create a minimal command
  mkdir -p "$TEST_DIR/cmds/hello"
  cat > "$TEST_DIR/cmds/hello/hello.sh" << 'SCRIPT'
#!/usr/bin/env bash
echo "hello output"
echo "VERBOSE=${VERBOSE:-unset}"
echo "QUIET=${QUIET:-unset}"
echo "NO_COLOR=${NO_COLOR:-unset}"
SCRIPT
  chmod +x "$TEST_DIR/cmds/hello/hello.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "--version flag prints version" {
  run bash "$FRAMEWORK_DIR/lib/router/router.sh" "hello" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"testcli version 1.0.0"* ]]
}

@test "--version short flag -V prints version" {
  run bash "$FRAMEWORK_DIR/lib/router/router.sh" "hello" -V
  [ "$status" -eq 0 ]
  [[ "$output" == *"testcli version 1.0.0"* ]]
}

@test "--no-color sets NO_COLOR=1" {
  run bash "$FRAMEWORK_DIR/lib/router/router.sh" "hello" --no-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"NO_COLOR=1"* ]]
}

@test "--verbose sets VERBOSE=true" {
  run bash "$FRAMEWORK_DIR/lib/router/router.sh" "hello" --verbose
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERBOSE=true"* ]]
}

@test "-v sets VERBOSE=true" {
  run bash "$FRAMEWORK_DIR/lib/router/router.sh" "hello" -v
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERBOSE=true"* ]]
}

@test "--quiet sets QUIET=true" {
  run bash "$FRAMEWORK_DIR/lib/router/router.sh" "hello" --quiet
  [ "$status" -eq 0 ]
  [[ "$output" == *"QUIET=true"* ]]
}

@test "-q sets QUIET=true" {
  run bash "$FRAMEWORK_DIR/lib/router/router.sh" "hello" -q
  [ "$status" -eq 0 ]
  [[ "$output" == *"QUIET=true"* ]]
}

@test "unknown command shows error" {
  run -127 bash "$FRAMEWORK_DIR/lib/router/router.sh" "nonexistent" 2>&1
  [[ "$output" == *"Unknown command"* ]]
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
  run bash "$FRAMEWORK_DIR/lib/router/router.sh" "hello" --verbose --no-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERBOSE=true"* ]]
  [[ "$output" == *"NO_COLOR=1"* ]]
  [[ "$output" == *"hello output"* ]]
}
