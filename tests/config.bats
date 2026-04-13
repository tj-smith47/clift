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
  export PROMPT="false"

  # Create a test .env file
  cat > "$TEST_DIR/.env" << 'EOF'
# Test config
APP_NAME=testcli
LOG_LEVEL=info
EOF
}

@test "get.sh reads existing key" {
  run bash "$FRAMEWORK_DIR/lib/config/get.sh" "$CLI_DIR" "APP_NAME"
  [ "$status" -eq 0 ]
  [ "$output" = "testcli" ]
}

@test "get.sh reads second key" {
  run bash "$FRAMEWORK_DIR/lib/config/get.sh" "$CLI_DIR" "LOG_LEVEL"
  [ "$status" -eq 0 ]
  [ "$output" = "info" ]
}

@test "get.sh exits 1 on missing key" {
  run bash "$FRAMEWORK_DIR/lib/config/get.sh" "$CLI_DIR" "NONEXISTENT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "set.sh creates new key" {
  run bash "$FRAMEWORK_DIR/lib/config/set.sh" "$CLI_DIR" "$FRAMEWORK_DIR" "NEW_KEY" "new_value"
  [ "$status" -eq 0 ]

  # Verify it was written
  run bash "$FRAMEWORK_DIR/lib/config/get.sh" "$CLI_DIR" "NEW_KEY"
  [ "$status" -eq 0 ]
  [ "$output" = "new_value" ]
}

@test "set.sh updates existing key" {
  run bash "$FRAMEWORK_DIR/lib/config/set.sh" "$CLI_DIR" "$FRAMEWORK_DIR" "APP_NAME" "updated"
  [ "$status" -eq 0 ]

  run bash "$FRAMEWORK_DIR/lib/config/get.sh" "$CLI_DIR" "APP_NAME"
  [ "$status" -eq 0 ]
  [ "$output" = "updated" ]
}

@test "set.sh rejects non-uppercase keys" {
  run bash "$FRAMEWORK_DIR/lib/config/set.sh" "$CLI_DIR" "$FRAMEWORK_DIR" "lowercase" "val"
  [ "$status" -eq 1 ]
  [[ "$output" == *"uppercase"* ]]
}

@test "set.sh rejects keys with dashes" {
  run bash "$FRAMEWORK_DIR/lib/config/set.sh" "$CLI_DIR" "$FRAMEWORK_DIR" "MY-KEY" "val"
  [ "$status" -eq 1 ]
  [[ "$output" == *"uppercase"* ]]
}

@test "show.sh displays all config" {
  run bash "$FRAMEWORK_DIR/lib/config/show.sh" "$CLI_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"APP_NAME"* ]]
  [[ "$output" == *"testcli"* ]]
  [[ "$output" == *"LOG_LEVEL"* ]]
  [[ "$output" == *"info"* ]]
}

@test "show.sh includes Configuration header" {
  run bash "$FRAMEWORK_DIR/lib/config/show.sh" "$CLI_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Configuration"* ]]
}

@test "set.sh preserves value with equals sign" {
  run bash "$FRAMEWORK_DIR/lib/config/set.sh" "$CLI_DIR" "$FRAMEWORK_DIR" "MY_URL" "host=localhost:5432"
  [ "$status" -eq 0 ]

  run bash "$FRAMEWORK_DIR/lib/config/get.sh" "$CLI_DIR" "MY_URL"
  [ "$status" -eq 0 ]
  [ "$output" = "host=localhost:5432" ]
}

@test "set.sh does not corrupt other keys when updating" {
  bash "$FRAMEWORK_DIR/lib/config/set.sh" "$CLI_DIR" "$FRAMEWORK_DIR" "APP_NAME" "updated"
  run bash "$FRAMEWORK_DIR/lib/config/get.sh" "$CLI_DIR" "LOG_LEVEL"
  [ "$status" -eq 0 ]
  [ "$output" = "info" ]
}

@test "show.sh skips comment lines" {
  run bash "$FRAMEWORK_DIR/lib/config/show.sh" "$CLI_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" != *"# Test config"* ]]
}

@test "get.sh errors on missing .env" {
  run bash "$FRAMEWORK_DIR/lib/config/get.sh" "$TEST_DIR/nope" "KEY"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "show.sh errors on missing .env" {
  run bash "$FRAMEWORK_DIR/lib/config/show.sh" "$TEST_DIR/nope"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "set.sh errors on missing .env" {
  run bash "$FRAMEWORK_DIR/lib/config/set.sh" "$TEST_DIR/nope" "$FRAMEWORK_DIR" "KEY" "val"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "set.sh requires all arguments" {
  run bash "$FRAMEWORK_DIR/lib/config/set.sh" "$CLI_DIR" "$FRAMEWORK_DIR" "" ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage"* ]]
}

@test "get.sh requires arguments" {
  run bash "$FRAMEWORK_DIR/lib/config/get.sh" "" ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage"* ]]
}

