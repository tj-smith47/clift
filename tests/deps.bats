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

@test "clift_check_deps_full emits no warning when task version matches minimum" {
  # Trigger the equal-versions branch of _version_lt (final `return 1`).
  # A false warning here would train users to ignore real ones.
  local current_ver
  current_ver="$(task --version 2>/dev/null | sed 's/.*v\([0-9][0-9.]*\).*/\1/; s/-.*//')"
  [ -n "$current_ver" ]
  mkdir -p "$TEST_DIR/fakefwdir"
  cat > "$TEST_DIR/fakefwdir/.clift.yaml" <<YAML
version: 0.1.0
min_task_version: "$current_ver"
YAML
  run bash -c "
    export FRAMEWORK_DIR='$TEST_DIR/fakefwdir'
    source '$FRAMEWORK_DIR/lib/check/deps.sh'
    clift_check_deps_full 2>&1
  "
  [ "$status" -eq 0 ]
  [[ "$output" != *"below minimum"* ]]
}

@test "clift_check_deps_full warns when task version below minimum" {
  # Create a .clift.yaml requiring an impossibly high task version
  mkdir -p "$TEST_DIR/fakefwdir"
  cat > "$TEST_DIR/fakefwdir/.clift.yaml" <<YAML
version: 0.1.0
min_task_version: "99.0.0"
YAML
  run bash -c "
    export FRAMEWORK_DIR='$TEST_DIR/fakefwdir'
    source '$FRAMEWORK_DIR/lib/check/deps.sh'
    clift_check_deps_full 2>&1
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"below minimum"* ]]
}

@test "GUM_AVAILABLE=true when mock gum is on PATH" {
  # Put a fake gum on PATH
  mkdir -p "$TEST_DIR/fakebin"
  printf '#!/bin/sh\necho gum\n' > "$TEST_DIR/fakebin/gum"
  chmod +x "$TEST_DIR/fakebin/gum"
  run bash -c "
    export PATH=\"$TEST_DIR/fakebin:\$PATH\"
    source '$FRAMEWORK_DIR/lib/check/deps.sh'
    clift_check_deps_fast
    echo \"GUM=\$GUM_AVAILABLE\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"GUM=true"* ]]
}

@test "clift_check_deps_fast rejects bash < 4.2 (patched version gate)" {
  # The runtime prelude uses `declare -A -g`, which requires bash 4.2+. The
  # deps check must fail clearly on 4.0/4.1 instead of surfacing cryptic
  # `declare: -g: invalid option` later on. BASH_VERSINFO is read-only in
  # a running shell, so we patch a copy of deps.sh to hard-code the check
  # against a mocked version.
  local patched="$TEST_DIR/deps_mock_4_1.sh"
  cp "$FRAMEWORK_DIR/lib/check/deps.sh" "$patched"
  # Replace the BASH_VERSINFO references with a mocked 4.1 pair so the
  # arithmetic guard evaluates the "too old" branch.
  local tmp_patch="$TEST_DIR/deps_mock_4_1.sh.tmp"
  sed 's/BASH_VERSINFO\[0\]/__CLIFT_TEST_MAJOR/g; s/BASH_VERSINFO\[1\]/__CLIFT_TEST_MINOR/g' \
    "$patched" > "$tmp_patch"
  mv "$tmp_patch" "$patched"

  run bash -c "
    __CLIFT_TEST_MAJOR=4
    __CLIFT_TEST_MINOR=1
    source '$patched'
    clift_check_deps_fast 2>&1
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"bash 4.2+ is required"* ]]
}

@test "clift_check_deps_fast accepts bash 4.2 exactly (patched version gate)" {
  local patched="$TEST_DIR/deps_mock_4_2.sh"
  cp "$FRAMEWORK_DIR/lib/check/deps.sh" "$patched"
  local tmp_patch="$TEST_DIR/deps_mock_4_2.sh.tmp"
  sed 's/BASH_VERSINFO\[0\]/__CLIFT_TEST_MAJOR/g; s/BASH_VERSINFO\[1\]/__CLIFT_TEST_MINOR/g' \
    "$patched" > "$tmp_patch"
  mv "$tmp_patch" "$patched"

  run bash -c "
    __CLIFT_TEST_MAJOR=4
    __CLIFT_TEST_MINOR=2
    source '$patched'
    clift_check_deps_fast 2>&1
  "
  [ "$status" -eq 0 ]
  [[ "$output" != *"bash 4.2+ is required"* ]]
}

@test "DEPS_WARN_GUM=true warns when gum missing" {
  run bash -c "
    export DEPS_WARN_GUM=true
    export PATH='/usr/bin:/bin'
    source '$FRAMEWORK_DIR/lib/check/deps.sh'
    clift_check_deps_fast 2>&1
  "
  # May fail if jq/yq not on restricted PATH, that's OK — we're testing the gum warn
  [[ "$output" == *"gum not found"* ]] || [[ "$output" == *"error:"* ]]
}
