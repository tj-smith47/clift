#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load jarvis_helper

setup() {
  jarvis_common_setup
  source "$CLIFT_JARVIS_DIR/lib/slug.sh"
  TASKS_DIR="$JARVIS_HOME/test/tasks"
  mkdir -p "$TASKS_DIR"
}
teardown() { jarvis_common_teardown; }

@test "slug_from_desc lowercases and hyphenates" {
  run slug_from_desc "Fix k3s etcd restore"
  [ "$status" -eq 0 ]
  [ "$output" = "fix-k3s-etcd-restore" ]
}

@test "slug_from_desc uses only the first line" {
  run slug_from_desc $'Fix k3s etcd restore\nsecond line ignored'
  [ "$status" -eq 0 ]
  [ "$output" = "fix-k3s-etcd-restore" ]
}

@test "slug_from_desc strips punctuation and collapses hyphens" {
  run slug_from_desc "Review  auth PR -- urgent!!!"
  [ "$status" -eq 0 ]
  [ "$output" = "review-auth-pr-urgent" ]
}

@test "slug_from_desc trims leading/trailing hyphens" {
  run slug_from_desc "-- weirdly bracketed --"
  [ "$status" -eq 0 ]
  [ "$output" = "weirdly-bracketed" ]
}

@test "slug_from_desc fails on empty input" {
  run slug_from_desc ""
  [ "$status" -ne 0 ]
}

@test "slug_from_desc fails on whitespace-only input" {
  run slug_from_desc "   "
  [ "$status" -ne 0 ]
}

@test "slug_is_jira_key recognizes PLAT-123" {
  run slug_is_jira_key "PLAT-123"
  [ "$status" -eq 0 ]
}

@test "slug_is_jira_key rejects lowercase prefix" {
  run slug_is_jira_key "plat-123"
  [ "$status" -ne 0 ]
}

@test "slug_is_jira_key rejects normal slug" {
  run slug_is_jira_key "fix-k3s-etcd"
  [ "$status" -ne 0 ]
}

@test "slug_resolve_collision returns base when unused" {
  run slug_resolve_collision "fix-k3s" "$TASKS_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "fix-k3s" ]
}

@test "slug_resolve_collision appends -2 on first clash" {
  : > "$TASKS_DIR/fix-k3s.json"
  run slug_resolve_collision "fix-k3s" "$TASKS_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "fix-k3s-2" ]
}

@test "slug_resolve_collision walks -2, -3, … until free" {
  : > "$TASKS_DIR/fix-k3s.json"
  : > "$TASKS_DIR/fix-k3s-2.json"
  : > "$TASKS_DIR/fix-k3s-3.json"
  run slug_resolve_collision "fix-k3s" "$TASKS_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "fix-k3s-4" ]
}

@test "slug_resolve_prefix echoes exact match" {
  : > "$TASKS_DIR/fix-k3s.json"
  : > "$TASKS_DIR/fix-k3s-etcd.json"
  run slug_resolve_prefix "fix-k3s" "$TASKS_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "fix-k3s" ]
}

@test "slug_resolve_prefix echoes unique prefix match" {
  : > "$TASKS_DIR/fix-k3s-etcd.json"
  run slug_resolve_prefix "fix-k3" "$TASKS_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "fix-k3s-etcd" ]
}

@test "slug_resolve_prefix fails with exit 1 on no match" {
  run slug_resolve_prefix "nope" "$TASKS_DIR"
  [ "$status" -eq 1 ]
}

@test "slug_resolve_prefix fails with exit 1 and lists candidates on ambiguous" {
  : > "$TASKS_DIR/fix-a.json"
  : > "$TASKS_DIR/fix-b.json"
  run slug_resolve_prefix "fix" "$TASKS_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"fix-a"* ]] || [[ "$stderr" == *"fix-a"* ]]
  [[ "$output" == *"fix-b"* ]] || [[ "$stderr" == *"fix-b"* ]]
}

@test "slug_resolve_prefix emits candidates alphabetically on ambiguous" {
  : > "$TASKS_DIR/zebra-task.json"
  : > "$TASKS_DIR/alpha-task.json"
  : > "$TASKS_DIR/mango-task.json"
  run slug_resolve_prefix "" "$TASKS_DIR"   # empty prefix matches all
  [ "$status" -eq 1 ]
  # Find the alpha/mango/zebra lines in order (stderr merged into $output by default)
  local idx_a idx_m idx_z
  idx_a="$(printf '%s\n' "$output" | grep -n alpha-task | head -1 | cut -d: -f1)"
  idx_m="$(printf '%s\n' "$output" | grep -n mango-task | head -1 | cut -d: -f1)"
  idx_z="$(printf '%s\n' "$output" | grep -n zebra-task | head -1 | cut -d: -f1)"
  [ "$idx_a" -lt "$idx_m" ]
  [ "$idx_m" -lt "$idx_z" ]
}
