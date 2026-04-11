#!/usr/bin/env bats

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
