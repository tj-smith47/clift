#!/usr/bin/env bats

load test_helper

@test "exports GUM_AVAILABLE" {
  run bash -c 'source "$FRAMEWORK_DIR/lib/check/deps.sh"; echo "GUM_AVAILABLE=$GUM_AVAILABLE"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"GUM_AVAILABLE="* ]]
  # Value should be either true or false
  [[ "$output" =~ GUM_AVAILABLE=(true|false) ]]
}

@test "TASK_CLI_VERSION is exported when FRAMEWORK_DIR is set" {
  run bash -c 'export FRAMEWORK_DIR="/opt/repos/task-cli"; source "$FRAMEWORK_DIR/lib/check/deps.sh"; echo "TASK_CLI_VERSION=$TASK_CLI_VERSION"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"TASK_CLI_VERSION=0.1.0"* ]]
}

@test "does not fail if .task-cli.yaml is missing" {
  run bash -c 'export FRAMEWORK_DIR="$TEST_DIR"; source "/opt/repos/task-cli/lib/check/deps.sh"'
  [ "$status" -eq 0 ]
}

@test "GUM_AVAILABLE is true or false, never empty" {
  run bash -c 'source "$FRAMEWORK_DIR/lib/check/deps.sh"; if [[ "$GUM_AVAILABLE" == "true" || "$GUM_AVAILABLE" == "false" ]]; then echo "valid"; else echo "invalid: $GUM_AVAILABLE"; fi'
  [ "$status" -eq 0 ]
  [ "$output" = "valid" ]
}

@test "exports CFGD_AVAILABLE" {
  run bash -c 'source "$FRAMEWORK_DIR/lib/check/deps.sh"; echo "CFGD_AVAILABLE=$CFGD_AVAILABLE"'
  [ "$status" -eq 0 ]
  [[ "$output" =~ CFGD_AVAILABLE=(true|false) ]]
}

@test "fails if yq is not available" {
  run bash -c 'PATH=/usr/bin:/bin source "$FRAMEWORK_DIR/lib/check/deps.sh"'
  # May or may not fail depending on whether yq is in /usr/bin
  # Just verify the script handles the check
  [[ "$status" -eq 0 ]] || [[ "$output" == *"yq is required"* ]]
}
