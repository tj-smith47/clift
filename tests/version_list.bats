#!/usr/bin/env bats
# Tests for lib/version/list.sh — enumeration of available versions.

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
description: A test CLI for list
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

@test "no tags -> empty (info line, exit 0)" {
  run bash "${FW}/lib/version/list.sh" "$CLI" "$FW"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No versions"* ]]
}

@test "one tag -> single row, marked current" {
  ( cd "$CLI" && git tag v0.1.0 )
  run bash "${FW}/lib/version/list.sh" "$CLI" "$FW"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CURRENT"* ]]
  [[ "$output" == *"0.1.0"* ]]
  [[ "$output" == *"v0.1.0"* ]]
  [[ "$output" == *"*"* ]]
}

@test "multiple tags -> sorted descending, current marked correctly" {
  ( cd "$CLI"
    git tag v0.1.0
    git commit -q --allow-empty -m '1'
    git tag v0.2.0
    git commit -q --allow-empty -m '2'
    git tag v0.3.0 )
  run bash "${FW}/lib/version/list.sh" "$CLI" "$FW"
  [ "$status" -eq 0 ]
  rows="$(printf '%s\n' "$output" | grep -E '[0-9]\.[0-9]\.[0-9]')"
  [ "$(echo "$rows" | wc -l)" -eq 3 ]
  [[ "$(echo "$rows" | sed -n '1p')" == *"0.3.0"* ]]
  [[ "$(echo "$rows" | sed -n '2p')" == *"0.2.0"* ]]
  [[ "$(echo "$rows" | sed -n '3p')" == *"0.1.0"* ]]
  # Current marker (*) only on the row matching .clift.yaml's 0.1.0
  [[ "$(echo "$rows" | sed -n '3p')" == *"*"* ]]
  [[ "$(echo "$rows" | sed -n '1p')" != *"*"* ]]
  [[ "$(echo "$rows" | sed -n '2p')" != *"*"* ]]
}

@test "nested-module tag form (testcli/v0.2.0) recognized" {
  ( cd "$CLI" && git tag testcli/v0.1.0 && git tag testcli/v0.2.0 )
  run bash "${FW}/lib/version/list.sh" "$CLI" "$FW"
  [ "$status" -eq 0 ]
  [[ "$output" == *"testcli/v0.2.0"* ]]
  [[ "$output" == *"testcli/v0.1.0"* ]]
}

@test "mixed tag forms collapse to one row per semver" {
  ( cd "$CLI" && git tag v0.1.0 && git tag testcli/v0.1.0 )
  run bash "${FW}/lib/version/list.sh" "$CLI" "$FW"
  [ "$status" -eq 0 ]
  count="$(echo "$output" | grep -cE '[[:space:]]0\.1\.0[[:space:]]')"
  [ "$count" -eq 1 ]
}

@test "--limit caps row count" {
  ( cd "$CLI"
    for i in 0 1 2 3 4 5; do
      git commit -q --allow-empty -m "c$i"
      git tag "v0.${i}.0"
    done )
  run bash "${FW}/lib/version/list.sh" "$CLI" "$FW" --limit 2
  [ "$status" -eq 0 ]
  count="$(echo "$output" | grep -cE '[0-9]\.[0-9]\.[0-9]')"
  [ "$count" -eq 2 ]
  [[ "$output" == *"0.5.0"* ]]
  [[ "$output" == *"0.4.0"* ]]
  [[ "$output" != *"0.3.0"* ]]
}

@test "--since vX.Y.Z filters older versions" {
  ( cd "$CLI"
    git tag v0.1.0
    git commit -q --allow-empty -m '1'
    git tag v0.2.0
    git commit -q --allow-empty -m '2'
    git tag v0.3.0 )
  run bash "${FW}/lib/version/list.sh" "$CLI" "$FW" --since v0.2.0
  [ "$status" -eq 0 ]
  [[ "$output" == *"0.3.0"* ]]
  [[ "$output" == *"0.2.0"* ]]
  [[ "$output" != *"0.1.0"* ]]
}

@test "--quiet emits one version per line, no header, no marker" {
  ( cd "$CLI" && git tag v0.1.0 && git commit -q --allow-empty -m '1' && git tag v0.2.0 )
  run bash "${FW}/lib/version/list.sh" "$CLI" "$FW" -q
  [ "$status" -eq 0 ]
  [[ "$output" != *"CURRENT"* ]]
  [[ "$output" != *"*"* ]]
  [ "${lines[0]}" = "0.2.0" ]
  [ "${lines[1]}" = "0.1.0" ]
}

@test "--json shape: name, mode, versions array with current flag" {
  ( cd "$CLI" && git tag v0.1.0 && git commit -q --allow-empty -m '1' && git tag v0.2.0 )
  run bash "${FW}/lib/version/list.sh" "$CLI" "$FW" --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '
    .name == "testcli"
    and .mode == "standalone"
    and (.versions | length) == 2
    and .versions[0].version == "0.2.0"
    and .versions[0].current == false
    and .versions[1].version == "0.1.0"
    and .versions[1].current == true
  ' >/dev/null
}

@test "--json includes tag/commit/date fields" {
  ( cd "$CLI" && git tag v0.1.0 )
  run bash "${FW}/lib/version/list.sh" "$CLI" "$FW" --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '
    .versions[0].tag == "v0.1.0"
    and (.versions[0].commit | length) == 7
    and (.versions[0].date | test("^\\d{4}-\\d{2}-\\d{2}$"))
  ' >/dev/null
}

@test "--limit with non-integer rejected" {
  run bash "${FW}/lib/version/list.sh" "$CLI" "$FW" --limit abc
  [ "$status" -eq 2 ]
  [[ "$output" == *"non-negative integer"* ]]
}

@test "--since with invalid semver rejected" {
  run bash "${FW}/lib/version/list.sh" "$CLI" "$FW" --since notasemver
  [ "$status" -ne 0 ]
}

@test "--help prints usage and exits 0" {
  run bash "${FW}/lib/version/list.sh" "$CLI" "$FW" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"--limit"* ]]
  [[ "$output" == *"--since"* ]]
}

@test "unknown flag rejected with exit 2" {
  run bash "${FW}/lib/version/list.sh" "$CLI" "$FW" --bogus
  [ "$status" -eq 2 ]
}
