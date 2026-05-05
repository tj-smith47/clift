#!/usr/bin/env bats
# Tests for lib/version/check.sh — version comparison output.

bats_require_minimum_version 1.5.0

load 'test_helper'

setup() {
  common_setup
  CLI="${TEST_DIR}/cli"
  FW="${BATS_TEST_DIRNAME}/.."
  mkdir -p "$CLI"

  cat > "${CLI}/.clift.yaml" <<EOF
name: testcli
version: 0.1.0
description: A test CLI for check
EOF

  ( cd "$CLI"
    git init -q -b master
    git config user.email 'test@example.com'
    git config user.name 'test'
    git add .
    git commit -q -m 'init' )
}

teardown() {
  common_teardown
}

@test "no remote tags, local matches -> 'up to date'" {
  ( cd "$CLI" && git tag v0.1.0 )
  run bash "${FW}/lib/version/check.sh" "$CLI" "$FW"
  [ "$status" -eq 0 ]
  [[ "$output" == *"up to date"* ]]
  [[ "$output" == *"v0.1.0"* ]]
}

@test "newer tag exists -> 'available'" {
  ( cd "$CLI" && git tag v0.1.0 && git tag v0.2.0 )
  run bash "${FW}/lib/version/check.sh" "$CLI" "$FW"
  [ "$status" -eq 0 ]
  [[ "$output" == *"v0.1.0 → v0.2.0 available"* ]]
}

@test "no tags at all -> 'up to date' (treats empty as no upgrade)" {
  run bash "${FW}/lib/version/check.sh" "$CLI" "$FW"
  [ "$status" -eq 0 ]
  [[ "$output" == *"up to date"* ]]
}

@test "local ahead of latest tag -> 'up to date'" {
  ( cd "$CLI" && git tag v0.0.5 )   # older than .clift.yaml's 0.1.0
  run bash "${FW}/lib/version/check.sh" "$CLI" "$FW"
  [ "$status" -eq 0 ]
  [[ "$output" == *"up to date"* ]]
}

@test "nested-module tag convention recognized (testcli/v0.2.0 > v0.1.0)" {
  ( cd "$CLI" && git tag v0.1.0 && git tag testcli/v0.2.0 )
  run bash "${FW}/lib/version/check.sh" "$CLI" "$FW"
  [ "$status" -eq 0 ]
  [[ "$output" == *"v0.1.0 → v0.2.0 available"* ]]
}

@test "--quiet suppresses 'up to date' output" {
  ( cd "$CLI" && git tag v0.1.0 )
  run bash "${FW}/lib/version/check.sh" "$CLI" "$FW" --quiet
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "--quiet still prints 'available' line" {
  ( cd "$CLI" && git tag v0.2.0 )
  run bash "${FW}/lib/version/check.sh" "$CLI" "$FW" -q
  [ "$status" -eq 0 ]
  [[ "$output" == *"available"* ]]
}

@test "--json shape contains name, mode, local, latest, up_to_date" {
  ( cd "$CLI" && git tag v0.1.0 )
  run bash "${FW}/lib/version/check.sh" "$CLI" "$FW" --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '
    .name == "testcli"
    and .mode == "standalone"
    and .local == "v0.1.0"
    and .latest == "v0.1.0"
    and .up_to_date == true
  ' >/dev/null
}

@test "--json reports up_to_date=false when newer available" {
  ( cd "$CLI" && git tag v0.2.0 )
  run bash "${FW}/lib/version/check.sh" "$CLI" "$FW" --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '
    .local == "v0.1.0"
    and .latest == "v0.2.0"
    and .up_to_date == false
  ' >/dev/null
}

@test "--help exits 0 with usage" {
  run bash "${FW}/lib/version/check.sh" "$CLI" "$FW" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "missing .clift.yaml -> exit 1" {
  rm "${CLI}/.clift.yaml"
  run bash "${FW}/lib/version/check.sh" "$CLI" "$FW"
  [ "$status" -ne 0 ]
  [[ "$output" == *".clift.yaml not found"* ]]
}
