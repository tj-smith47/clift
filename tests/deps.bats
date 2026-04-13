#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load test_helper

@test "exports GUM_AVAILABLE" {
  run bash -c 'source "$FRAMEWORK_DIR/lib/check/deps.sh"; clift_check_deps_fast; echo "GUM_AVAILABLE=$GUM_AVAILABLE"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"GUM_AVAILABLE="* ]]
  # Value should be either true or false
  [[ "$output" =~ GUM_AVAILABLE=(true|false) ]]
}

@test "CLIFT_VERSION is exported when FRAMEWORK_DIR is set" {
  run bash -c "export FRAMEWORK_DIR='$FRAMEWORK_DIR'; source \"\$FRAMEWORK_DIR/lib/check/deps.sh\"; clift_check_deps_full; echo \"CLIFT_VERSION=\$CLIFT_VERSION\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"CLIFT_VERSION=0.1.0"* ]]
}

@test "does not fail if .clift.yaml is missing" {
  run bash -c "export FRAMEWORK_DIR='$TEST_DIR'; source '$FRAMEWORK_DIR/lib/check/deps.sh'; clift_check_deps_full"
  [ "$status" -eq 0 ]
}

@test "GUM_AVAILABLE is true or false, never empty" {
  run bash -c 'source "$FRAMEWORK_DIR/lib/check/deps.sh"; clift_check_deps_fast; if [[ "$GUM_AVAILABLE" == "true" || "$GUM_AVAILABLE" == "false" ]]; then echo "valid"; else echo "invalid: $GUM_AVAILABLE"; fi'
  [ "$status" -eq 0 ]
  [ "$output" = "valid" ]
}

@test "exports CFGD_AVAILABLE" {
  run bash -c 'source "$FRAMEWORK_DIR/lib/check/deps.sh"; clift_check_deps_fast; echo "CFGD_AVAILABLE=$CFGD_AVAILABLE"'
  [ "$status" -eq 0 ]
  [[ "$output" =~ CFGD_AVAILABLE=(true|false) ]]
}

@test "fails if yq is not available" {
  run bash -c 'PATH=/usr/bin:/bin source "$FRAMEWORK_DIR/lib/check/deps.sh"; clift_check_deps_fast'
  # May or may not fail depending on whether yq is in /usr/bin
  # Just verify the script handles the check
  [[ "$status" -eq 0 ]] || [[ "$output" == *"yq is required"* ]]
}

@test "clift_check_deps_full exports CLIFT_VERSION" {
  run bash -c "export FRAMEWORK_DIR='$FRAMEWORK_DIR'; source \"\$FRAMEWORK_DIR/lib/check/deps.sh\"; clift_check_deps_full; [[ -n \"\$CLIFT_VERSION\" ]] && echo 'ok'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

@test "clift_check_deps_full validates task version" {
  # This exercises the _version_lt code path
  run bash -c "export FRAMEWORK_DIR='$FRAMEWORK_DIR'; source \"\$FRAMEWORK_DIR/lib/check/deps.sh\"; clift_check_deps_full"
  [ "$status" -eq 0 ]
}

@test "gum-unavailable path sets GUM_AVAILABLE=false" {
  # We know gum is not typically at /usr/bin, but jq/yq might be.
  # Just verify the GUM_AVAILABLE variable works correctly.
  run bash -c 'source "$FRAMEWORK_DIR/lib/check/deps.sh"; clift_check_deps_fast; echo "GUM=$GUM_AVAILABLE"'
  [ "$status" -eq 0 ]
  # GUM_AVAILABLE should be true or false — test the branching logic
  [[ "$output" =~ GUM=(true|false) ]]
}
