#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load test_helper

@test "clift_max_mtime returns an integer for existing files" {
  source "$FRAMEWORK_DIR/lib/cache.sh"
  touch "$TEST_DIR/a.yaml"
  run clift_max_mtime "$TEST_DIR/a.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]
}

@test "clift_max_mtime returns the newest mtime across multiple files" {
  source "$FRAMEWORK_DIR/lib/cache.sh"
  touch "$TEST_DIR/a.yaml"
  sleep 1
  touch "$TEST_DIR/b.yaml"
  local mtime_a mtime_b
  mtime_a="$(clift_max_mtime "$TEST_DIR/a.yaml")"
  mtime_b="$(clift_max_mtime "$TEST_DIR/b.yaml")"
  local mtime_both
  mtime_both="$(clift_max_mtime "$TEST_DIR/a.yaml" "$TEST_DIR/b.yaml")"
  [ "$mtime_both" = "$mtime_b" ]
}

@test "clift_max_mtime handles glob expansion with no matches gracefully" {
  source "$FRAMEWORK_DIR/lib/cache.sh"
  touch "$TEST_DIR/root.yaml"
  # No cmds/ dir exists, glob expands to literal which stat skips
  run clift_max_mtime "$TEST_DIR/root.yaml" "$TEST_DIR"/cmds/*/Taskfile.yaml
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]
}

@test "clift_ensure_cache triggers rebuild when checksum missing" {
  source "$FRAMEWORK_DIR/lib/cache.sh"
  create_test_cli "greet"
  # No .clift/ dir yet — ensure_cache should create it
  clift_ensure_cache "$CLI_DIR" "$FRAMEWORK_DIR"
  [ -f "$CLI_DIR/.clift/tasks.json" ]
  [ -f "$CLI_DIR/.clift/flags.json" ]
  [ -f "$CLI_DIR/.clift/checksum" ]
}

@test "clift_ensure_cache skips rebuild when cache is fresh" {
  source "$FRAMEWORK_DIR/lib/cache.sh"
  create_test_cli "greet"
  clift_ensure_cache "$CLI_DIR" "$FRAMEWORK_DIR"
  local checksum_before
  checksum_before="$(cat "$CLI_DIR/.clift/checksum")"
  # Call again without changing anything
  clift_ensure_cache "$CLI_DIR" "$FRAMEWORK_DIR"
  local checksum_after
  checksum_after="$(cat "$CLI_DIR/.clift/checksum")"
  [ "$checksum_before" = "$checksum_after" ]
}
