#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load test_helper

@test "GUM_AVAILABLE is true or false, never empty" {
  run bash -c 'source "$FRAMEWORK_DIR/lib/check/deps.sh"; clift_check_deps_fast; if [[ "$GUM_AVAILABLE" == "true" || "$GUM_AVAILABLE" == "false" ]]; then echo "valid"; else echo "invalid: $GUM_AVAILABLE"; fi'
  [ "$status" -eq 0 ]
  [ "$output" = "valid" ]
}

@test "CFGD_AVAILABLE is true or false, never empty" {
  run bash -c 'source "$FRAMEWORK_DIR/lib/check/deps.sh"; clift_check_deps_fast; if [[ "$CFGD_AVAILABLE" == "true" || "$CFGD_AVAILABLE" == "false" ]]; then echo "valid"; else echo "invalid: $CFGD_AVAILABLE"; fi'
  [ "$status" -eq 0 ]
  [ "$output" = "valid" ]
}

@test "clift_check_deps_full exports CLIFT_VERSION from .clift.yaml" {
  run bash -c "export FRAMEWORK_DIR='$FRAMEWORK_DIR'; source \"\$FRAMEWORK_DIR/lib/check/deps.sh\"; clift_check_deps_full; echo \"CLIFT_VERSION=\$CLIFT_VERSION\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"CLIFT_VERSION=0.1.0"* ]]
}

@test "clift_check_deps_full succeeds when .clift.yaml is missing" {
  run bash -c "export FRAMEWORK_DIR='$TEST_DIR'; source '$FRAMEWORK_DIR/lib/check/deps.sh'; clift_check_deps_full"
  [ "$status" -eq 0 ]
}

@test "clift_check_deps_full exercises task version comparison" {
  run bash -c "export FRAMEWORK_DIR='$FRAMEWORK_DIR'; source \"\$FRAMEWORK_DIR/lib/check/deps.sh\"; clift_check_deps_full"
  [ "$status" -eq 0 ]
}
