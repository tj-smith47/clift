#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR"
  # Real framework for log.sh sourcing, but mirrored into a fixture dir we can mutate
  export FRAMEWORK_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export FIXTURE_DIR="$TEST_DIR/framework"
  mkdir -p "$FIXTURE_DIR/lib/log"
  cp "$FRAMEWORK_SRC/lib/log/log.sh" "$FIXTURE_DIR/lib/log/log.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "update errors when FRAMEWORK_DIR arg is missing" {
  run bash "$FRAMEWORK_SRC/lib/update/update.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FRAMEWORK_DIR required"* ]]
}

@test "update short-circuits when installation is cfgd-managed" {
  touch "$FIXTURE_DIR/.cfgd-managed"
  run bash "$FRAMEWORK_SRC/lib/update/update.sh" "$FIXTURE_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"managed by cfgd"* ]]
  [[ "$output" == *"cfgd module upgrade clift"* ]]
  [[ "$output" == *"cfgd apply"* ]]
}

@test "update errors when framework dir is not a git repo" {
  run bash "$FRAMEWORK_SRC/lib/update/update.sh" "$FIXTURE_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a git repository"* ]]
}

@test "update errors when remote branch does not exist" {
  # A repo with an origin URL but no matching remote branch to compare against.
  # This is a real failure mode for users on a rare local branch — the error
  # must be specific enough that they know to `git push -u origin <branch>`.
  mkdir "$TEST_DIR/upstream.git"
  git -C "$TEST_DIR/upstream.git" init --quiet --bare --initial-branch=main
  git clone --quiet "$TEST_DIR/upstream.git" "$FIXTURE_DIR/work" >/dev/null 2>&1
  git -C "$FIXTURE_DIR/work" -c user.email=t@t -c user.name=t commit --quiet --allow-empty -m init
  git -C "$FIXTURE_DIR/work" push --quiet origin main
  # Move to a branch that has no upstream
  git -C "$FIXTURE_DIR/work" checkout -q -b orphan
  rm -rf "$FIXTURE_DIR/lib"
  mkdir -p "$FIXTURE_DIR/work/lib/log"
  cp "$FRAMEWORK_SRC/lib/log/log.sh" "$FIXTURE_DIR/work/lib/log/log.sh"

  run bash "$FRAMEWORK_SRC/lib/update/update.sh" "$FIXTURE_DIR/work"
  [ "$status" -ne 0 ]
  [[ "$output" == *"remote branch"* ]]
  [[ "$output" == *"orphan"* ]]
}

@test "update reports 'already up to date' when HEAD matches origin" {
  # Set up a bare upstream and a clone of it, so origin/<branch> resolves locally
  mkdir "$TEST_DIR/upstream.git"
  git -C "$TEST_DIR/upstream.git" init --quiet --bare --initial-branch=main
  git clone --quiet "$TEST_DIR/upstream.git" "$FIXTURE_DIR/work" >/dev/null 2>&1
  git -C "$FIXTURE_DIR/work" -c user.email=t@t -c user.name=t commit --quiet --allow-empty -m init
  git -C "$FIXTURE_DIR/work" push --quiet origin main
  # Re-point FIXTURE_DIR at the clone (it needs .git and log.sh)
  rm -rf "$FIXTURE_DIR/lib"
  mkdir -p "$FIXTURE_DIR/work/lib/log"
  cp "$FRAMEWORK_SRC/lib/log/log.sh" "$FIXTURE_DIR/work/lib/log/log.sh"

  run bash "$FRAMEWORK_SRC/lib/update/update.sh" "$FIXTURE_DIR/work"
  [ "$status" -eq 0 ]
  [[ "$output" == *"up to date"* ]]
}
