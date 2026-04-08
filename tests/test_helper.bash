# Common test helper
setup() {
  TEST_DIR="$(mktemp -d)"
  export FRAMEWORK_DIR="/opt/repos/task-cli"
  export CLI_DIR="$TEST_DIR"
  export CLI_NAME="testcli"
  export CLI_VERSION="1.0.0"
  export LOG_THEME="minimal"
  export PROMPT="false"
}

teardown() {
  rm -rf "$TEST_DIR"
}
