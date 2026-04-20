#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load jarvis_helper

setup() {
  jarvis_common_setup
  source "$CLIFT_JARVIS_DIR/lib/state/profile.sh"
  source "$CLIFT_JARVIS_DIR/lib/state/lock.sh"
  source "$CLIFT_JARVIS_DIR/lib/state/json.sh"
  source "$CLIFT_JARVIS_DIR/lib/frontmatter.sh"
  source "$CLIFT_JARVIS_DIR/lib/note/resolve.sh"
  source "$CLIFT_JARVIS_DIR/lib/note/index.sh"
  source "$CLIFT_JARVIS_DIR/lib/note/store.sh"
  state_ensure_tree
}
teardown() { jarvis_common_teardown; }

@test "note_store_new creates file with merged frontmatter + empty body" {
  run note_store_new inbox audit-flock "Audit Flock Path"
  [ "$status" -eq 0 ]
  [ "$output" = "inbox/audit-flock" ]
  local f="$(note_path inbox/audit-flock)"
  [ -f "$f" ]
  run fm_get "$f" "title" ""
  [ "$output" = "Audit Flock Path" ]
  run fm_get "$f" "kind" ""
  [ "$output" = "inbox" ]
  run fm_get "$f" "slug" ""
  [ "$output" = "audit-flock" ]
}

@test "note_store_new with --tags merges into frontmatter" {
  note_store_new ref etcd-restore "Etcd Restore" --tags '["k3s","runbook"]'
  local f="$(note_path ref/etcd-restore)"
  run fm_get "$f" "tags.0" ""
  [ "$output" = "k3s" ]
}

@test "note_store_append writes timestamped tail by default" {
  note_store_new inbox foo "Foo"
  note_store_append inbox/foo "line one"
  local f="$(note_path inbox/foo)"
  grep -q '^## ' "$f"
  grep -q 'line one' "$f"
}

@test "note_store_append --no-timestamp skips the header" {
  note_store_new inbox bar "Bar"
  note_store_append inbox/bar "plain text" --no-timestamp
  local f="$(note_path inbox/bar)"
  grep -q 'plain text' "$f"
  ! grep -q '^## 20' "$f"
}

@test "note_store_append honors frontmatter append.timestamp = false" {
  note_store_new inbox baz "Baz"
  local f="$(note_path inbox/baz)"
  fm_set "$f" "append.timestamp" "false"
  note_store_append inbox/baz "body only"
  ! grep -q '^## 20' "$f"
}

@test "note_store_archive moves file and flips archived flag in index" {
  note_store_new inbox to-archive "To Archive"
  note_store_archive inbox/to-archive
  [ ! -f "$(note_path inbox/to-archive)" ]
  [ -f "$(note_root)/archive/to-archive.md" ]
  local idx="$(note_index_file)"
  run jq -r '."archive/to-archive".archived' "$idx"
  [ "$output" = "true" ]
  run jq -r '."archive/to-archive".original_kind' "$idx"
  [ "$output" = "inbox" ]
}

@test "note_store_delete removes file and index row" {
  note_store_new inbox goner "Goner"
  note_store_delete inbox/goner
  [ ! -f "$(note_path inbox/goner)" ]
  local idx="$(note_index_file)"
  run jq -r '."inbox/goner" // "absent"' "$idx"
  [ "$output" = "absent" ]
}
