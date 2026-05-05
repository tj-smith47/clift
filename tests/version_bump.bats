#!/usr/bin/env bats
# Tests for lib/version/bump.sh — atomic 3-file write + commit + tag.

bats_require_minimum_version 1.5.0

load 'test_helper'

setup() {
  common_setup

  # Fresh temp CLI with .clift.yaml + .env + git repo so bump has something
  # to operate on. No FRAMEWORK_DIR setup needed beyond pointing the script
  # at this repo's lib/log.
  CLI="${TEST_DIR}/cli"
  FW="${BATS_TEST_DIRNAME}/.."
  mkdir -p "$CLI"

  cat > "${CLI}/.clift.yaml" <<EOF
name: testcli
version: 0.1.0
description: A test CLI
EOF

  cat > "${CLI}/.env" <<EOF
CLI_NAME=testcli
CLI_VERSION=0.1.0
EOF

  # Initialize git, configure local user (never touch global config — see
  # feedback_tests_mutated_git_config in user memory). Initial commit so
  # bump's "dirty" check can pass on a clean tree.
  (
    cd "$CLI"
    git init -q -b master
    git config user.email 'test@example.com'
    git config user.name 'test'
    git add .
    git commit -q -m 'init'
  )
}

teardown() {
  common_teardown
}

# --- positive paths ----------------------------------------------------------

@test "bump patch: 0.1.0 -> 0.1.1, files updated, commit + tag" {
  run bash "${FW}/lib/version/bump.sh" "$CLI" "$FW" patch
  [ "$status" -eq 0 ]
  [[ "$output" == *"0.1.0 → 0.1.1"* ]]

  # .clift.yaml updated
  grep -q '^version: 0.1.1' "${CLI}/.clift.yaml"
  # .env updated
  grep -q '^CLI_VERSION=0.1.1' "${CLI}/.env"

  # commit exists
  ( cd "$CLI" && git log -1 --format=%s | grep -q '^release: v0.1.1' )
  # tag exists
  ( cd "$CLI" && git tag --list | grep -qx 'v0.1.1' )
}

@test "bump minor: 0.1.0 -> 0.2.0" {
  run bash "${FW}/lib/version/bump.sh" "$CLI" "$FW" minor
  [ "$status" -eq 0 ]
  grep -q '^version: 0.2.0' "${CLI}/.clift.yaml"
  ( cd "$CLI" && git tag --list | grep -qx 'v0.2.0' )
}

@test "bump major: 0.1.0 -> 1.0.0" {
  run bash "${FW}/lib/version/bump.sh" "$CLI" "$FW" major
  [ "$status" -eq 0 ]
  grep -q '^version: 1.0.0' "${CLI}/.clift.yaml"
  ( cd "$CLI" && git tag --list | grep -qx 'v1.0.0' )
}

@test "bump default level is patch" {
  run bash "${FW}/lib/version/bump.sh" "$CLI" "$FW"
  [ "$status" -eq 0 ]
  ( cd "$CLI" && git tag --list | grep -qx 'v0.1.1' )
}

# --- --dry-run ---------------------------------------------------------------

@test "--dry-run does not modify files, commit, or tag" {
  before_clift=$(cat "${CLI}/.clift.yaml")
  before_env=$(cat "${CLI}/.env")
  before_head=$( cd "$CLI" && git rev-parse HEAD )

  run bash "${FW}/lib/version/bump.sh" "$CLI" "$FW" patch --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"(dry-run)"* ]]

  [ "$(cat "${CLI}/.clift.yaml")" = "$before_clift" ]
  [ "$(cat "${CLI}/.env")" = "$before_env" ]
  [ "$( cd "$CLI" && git rev-parse HEAD )" = "$before_head" ]
  [ -z "$( cd "$CLI" && git tag --list )" ]
}

# --- failure modes -----------------------------------------------------------

@test "dirty tree without --allow-dirty -> exit 2" {
  echo "noise" > "${CLI}/dirty.txt"
  run bash "${FW}/lib/version/bump.sh" "$CLI" "$FW" patch
  [ "$status" -eq 2 ]
  [[ "$output" == *"dirty"* ]]
}

@test "dirty tree with --allow-dirty -> succeeds" {
  echo "noise" > "${CLI}/dirty.txt"
  run bash "${FW}/lib/version/bump.sh" "$CLI" "$FW" patch --allow-dirty
  [ "$status" -eq 0 ]
}

@test "tag already exists -> exit 2 with suggestion" {
  ( cd "$CLI" && git tag v0.1.1 )
  run bash "${FW}/lib/version/bump.sh" "$CLI" "$FW" patch
  [ "$status" -eq 2 ]
  [[ "$output" == *"already exists"* ]]
  [[ "$output" == *"version:set"* ]]
}

@test "detached HEAD -> exit 2" {
  ( cd "$CLI" && git checkout -q --detach HEAD )
  run bash "${FW}/lib/version/bump.sh" "$CLI" "$FW" patch
  [ "$status" -eq 2 ]
  [[ "$output" == *"detached HEAD"* ]]
}

@test "missing .clift.yaml -> exit 1" {
  rm "${CLI}/.clift.yaml"
  run bash "${FW}/lib/version/bump.sh" "$CLI" "$FW" patch
  [ "$status" -ne 0 ]
  [[ "$output" == *".clift.yaml not found"* ]]
}

# --- --message ---------------------------------------------------------------

@test "--message overrides commit subject" {
  run bash "${FW}/lib/version/bump.sh" "$CLI" "$FW" patch --message "ship it"
  [ "$status" -eq 0 ]
  ( cd "$CLI" && git log -1 --format=%s | grep -qx 'ship it' )
}

@test "--message=VAL inline form" {
  run bash "${FW}/lib/version/bump.sh" "$CLI" "$FW" patch --message=inlined
  [ "$status" -eq 0 ]
  ( cd "$CLI" && git log -1 --format=%s | grep -qx 'inlined' )
}

# --- nested-module tag convention -------------------------------------------

@test "nested module (cfgd.yaml in parent) -> tag is <name>/vX.Y.Z" {
  # Make CLI a child of a fake cfgd config repo.
  parent="${TEST_DIR}/parent-config"
  mkdir -p "$parent"
  printf 'apiVersion: cfgd.io/v1alpha1\nkind: Config\n' > "${parent}/cfgd.yaml"
  mv "$CLI" "${parent}/testcli"
  CLI="${parent}/testcli"

  run bash "${FW}/lib/version/bump.sh" "$CLI" "$FW" patch
  [ "$status" -eq 0 ]
  ( cd "$CLI" && git tag --list | grep -qx 'testcli/v0.1.1' )
}

# --- module.yaml sync --------------------------------------------------------

@test "module.yaml metadata is synced from .clift.yaml on bump" {
  # Drop in a module.yaml with stale metadata.
  cat > "${CLI}/module.yaml" <<EOF
apiVersion: cfgd.io/v1alpha1
kind: Module
metadata:
  name: stale-name
  description: stale
spec:
  packages: []
EOF
  ( cd "$CLI" && git add module.yaml && git commit -q -m 'add module' )

  run bash "${FW}/lib/version/bump.sh" "$CLI" "$FW" patch
  [ "$status" -eq 0 ]
  grep -q 'name: testcli' "${CLI}/module.yaml"
  grep -q 'description: A test CLI' "${CLI}/module.yaml"
  # module.yaml is part of the release commit
  ( cd "$CLI" && git show --name-only HEAD | grep -qx 'module.yaml' )
}

# --- argument validation -----------------------------------------------------

@test "unexpected positional -> exit 2 with usage" {
  run bash "${FW}/lib/version/bump.sh" "$CLI" "$FW" foo
  [ "$status" -eq 2 ]
  [[ "$output" == *"unexpected argument: foo"* ]]
}

@test "two levels -> exit 2" {
  run bash "${FW}/lib/version/bump.sh" "$CLI" "$FW" patch minor
  [ "$status" -eq 2 ]
  [[ "$output" == *"specified twice"* ]]
}

@test "--help prints usage and exits 0" {
  run bash "${FW}/lib/version/bump.sh" "$CLI" "$FW" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"--push"* ]]
  [[ "$output" == *"--dry-run"* ]]
}
