#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR"
  export FRAMEWORK_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export PROMPT="false"
  export CLIFT_RC_FILE="$HOME/.bashrc"
  touch "$HOME/.bashrc"
  touch "$HOME/.zshrc"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "setup.sh creates CLI directory and .env" {
  run bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "1.0.0" "minimal" "standard"
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/mycli/.env" ]
  [ -d "$TEST_DIR/mycli/cmds" ]
}

@test "setup.sh creates Taskfile.yaml" {
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "1.0.0" "minimal" "standard"
  [ -f "$TEST_DIR/mycli/Taskfile.yaml" ]
}

@test "setup.sh creates .clift.yaml metadata" {
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "1.0.0" "minimal" "standard"
  [ -f "$TEST_DIR/mycli/.clift.yaml" ]
}

@test "setup.sh creates module.yaml" {
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "1.0.0" "minimal" "standard"
  [ -f "$TEST_DIR/mycli/module.yaml" ]
}

@test "setup.sh standard mode creates wrapper script" {
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "1.0.0" "minimal" "standard"
  [ -x "$TEST_DIR/mycli/bin/mycli" ]
}

@test "setup.sh standard mode adds PATH to rc file" {
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "1.0.0" "minimal" "standard"
  grep -q "export PATH" "$HOME/.bashrc"
}

@test "setup.sh task mode creates alias in rc file" {
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "1.0.0" "minimal" "task"
  grep -q "alias mycli=" "$HOME/.bashrc"
}

@test "setup.sh task mode does not create wrapper script" {
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "1.0.0" "minimal" "task"
  [ ! -f "$TEST_DIR/mycli/bin/mycli" ]
}

@test "setup.sh .env contains correct CLI_NAME" {
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "2.0.0" "brackets" "standard"
  grep -q "CLI_NAME=mycli" "$TEST_DIR/mycli/.env"
  grep -q "CLI_VERSION=2.0.0" "$TEST_DIR/mycli/.env"
  grep -q "LOG_THEME=brackets" "$TEST_DIR/mycli/.env"
}

@test "setup.sh rejects invalid CLI_NAME" {
  run bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "My-CLI!" "1.0.0" "minimal" "standard"
  [ "$status" -ne 0 ]
  [[ "$output" == *"lowercase"* ]]
}

@test "setup.sh rejects invalid CLIFT_MODE" {
  run bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "1.0.0" "minimal" "badmode"
  [ "$status" -eq 1 ]
  [[ "$output" == *"CLIFT_MODE"* ]]
}

@test "setup.sh defaults CLI_NAME to basename of target" {
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/myapp" "$FRAMEWORK_DIR" "" "1.0.0" "minimal" "standard"
  grep -q "CLI_NAME=myapp" "$TEST_DIR/myapp/.env"
}

@test "setup.sh requires TARGET_DIR and FRAMEWORK_DIR" {
  run bash "$FRAMEWORK_DIR/lib/setup/setup.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires"* ]]
}

@test "setup.sh strips Taskfile.yaml from path" {
  mkdir -p "$TEST_DIR/sub"
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/sub/Taskfile.yaml" "$FRAMEWORK_DIR" "sub" "1.0.0" "minimal" "standard"
  [ -f "$TEST_DIR/sub/.env" ]
}

@test "setup.sh reconfigure updates .env" {
  # First install
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "1.0.0" "minimal" "standard"
  grep -q "CLI_VERSION=1.0.0" "$TEST_DIR/mycli/.env"

  # Reconfigure — prompt.sh uses --var to check env, so set the vars
  export RECONFIGURE_YES=1
  export _RECONFIG_NAME="mycli"
  export _RECONFIG_VERSION="2.0.0"
  export _RECONFIG_THEME="brackets"
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "2.0.0" "brackets" "standard"
  grep -q "CLI_VERSION=2.0.0" "$TEST_DIR/mycli/.env"
}

@test "setup.sh mode switch from task to standard" {
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "1.0.0" "minimal" "task"
  grep -q "alias mycli=" "$HOME/.bashrc"

  export RECONFIGURE_YES=1
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "1.0.0" "minimal" "standard"
  # Alias should be gone, PATH should be there
  ! grep -q "alias mycli=" "$HOME/.bashrc"
  grep -q "export PATH" "$HOME/.bashrc"
}

@test "setup.sh copies CI workflow" {
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "1.0.0" "minimal" "standard"
  [ -f "$TEST_DIR/mycli/.github/workflows/ci.yml" ]
}

@test "setup.sh precompiles cache" {
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "1.0.0" "minimal" "standard"
  [ -d "$TEST_DIR/mycli/.clift" ]
}
