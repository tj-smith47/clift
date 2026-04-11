#!/usr/bin/env bats

load test_helper

setup() {
  if ! command -v task &>/dev/null; then
    skip "task not installed"
  fi
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR"
  export FRAMEWORK_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export CLI_DIR="$TEST_DIR"
  export CLI_NAME="testcli"
  export CLI_VERSION="1.0.0"
  export LOG_THEME="minimal"

  # Create a minimal Taskfile for completion to read
  cat > "$TEST_DIR/Taskfile.yaml" << 'EOF'
version: "3"
tasks:
  default:
    cmd: echo "default"
  hello:
    cmd: echo "hello"
  greet:
    cmd: echo "greet"
EOF
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "bash format outputs complete -F line" {
  run bash "$FRAMEWORK_DIR/lib/completion/completion.sh" bash "$TEST_DIR/Taskfile.yaml" testcli
  [ "$status" -eq 0 ]
  [[ "$output" == *"complete -F"* ]]
  [[ "$output" == *"testcli"* ]]
}

@test "zsh format outputs compdef line" {
  run bash "$FRAMEWORK_DIR/lib/completion/completion.sh" zsh "$TEST_DIR/Taskfile.yaml" testcli
  [ "$status" -eq 0 ]
  [[ "$output" == *"compdef"* ]]
  [[ "$output" == *"testcli"* ]]
}

@test "unknown format exits with error" {
  run bash "$FRAMEWORK_DIR/lib/completion/completion.sh" fish "$TEST_DIR/Taskfile.yaml" testcli
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown format"* ]]
}

@test "missing arguments exits with error" {
  run bash "$FRAMEWORK_DIR/lib/completion/completion.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"error"* ]]
}

@test "bash format includes function definition" {
  run bash "$FRAMEWORK_DIR/lib/completion/completion.sh" bash "$TEST_DIR/Taskfile.yaml" testcli
  [ "$status" -eq 0 ]
  [[ "$output" == *"_testcli_completions"* ]]
}

@test "zsh format includes compdef function" {
  run bash "$FRAMEWORK_DIR/lib/completion/completion.sh" zsh "$TEST_DIR/Taskfile.yaml" testcli
  [ "$status" -eq 0 ]
  [[ "$output" == *"_testcli()"* ]]
}
