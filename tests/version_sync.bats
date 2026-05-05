#!/usr/bin/env bats
# Tests for lib/version/sync.sh — module.yaml metadata refresh.

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
description: A test CLI for sync
EOF
}

teardown() {
  common_teardown
}

@test "no module.yaml -> exits 0 with hint" {
  run bash "${FW}/lib/version/sync.sh" "$CLI" "$FW"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not present"* ]]
  [[ "$output" == *"version:setup"* ]]
}

@test "module.yaml already in sync -> exits 0 'up to date'" {
  cat > "${CLI}/module.yaml" <<EOF
apiVersion: cfgd.io/v1alpha1
kind: Module
metadata:
  name: testcli
  description: A test CLI for sync
spec:
  packages: []
EOF
  run bash "${FW}/lib/version/sync.sh" "$CLI" "$FW"
  [ "$status" -eq 0 ]
  [[ "$output" == *"up to date"* ]]
}

@test "stale module.yaml -> regenerated, diff printed" {
  cat > "${CLI}/module.yaml" <<EOF
apiVersion: cfgd.io/v1alpha1
kind: Module
metadata:
  name: stale-name
  description: stale-desc
spec:
  packages: []
EOF
  run bash "${FW}/lib/version/sync.sh" "$CLI" "$FW"
  [ "$status" -eq 0 ]
  [[ "$output" == *"-  name: stale-name"* ]] || [[ "$output" == *"stale-name"* ]]
  grep -q 'name: testcli' "${CLI}/module.yaml"
  grep -q 'description: A test CLI for sync' "${CLI}/module.yaml"
}

@test "--dry-run prints diff but does not write" {
  cat > "${CLI}/module.yaml" <<EOF
apiVersion: cfgd.io/v1alpha1
kind: Module
metadata:
  name: stale-name
  description: stale
spec:
  packages: []
EOF
  before=$(cat "${CLI}/module.yaml")
  run bash "${FW}/lib/version/sync.sh" "$CLI" "$FW" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"stale-name"* ]]
  [ "$(cat "${CLI}/module.yaml")" = "$before" ]
}

@test "--help exits 0 with usage" {
  run bash "${FW}/lib/version/sync.sh" "$CLI" "$FW" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "missing .clift.yaml -> exit 1" {
  rm "${CLI}/.clift.yaml"
  run bash "${FW}/lib/version/sync.sh" "$CLI" "$FW"
  [ "$status" -ne 0 ]
  [[ "$output" == *".clift.yaml not found"* ]]
}
