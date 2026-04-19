#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load jarvis_helper

setup() {
  jarvis_common_setup
  source "$CLIFT_JARVIS_DIR/lib/state/profile.sh"
  source "$CLIFT_JARVIS_DIR/lib/state/lock.sh"
  source "$CLIFT_JARVIS_DIR/lib/state/json.sh"
  state_ensure_tree
}
teardown() { jarvis_common_teardown; }

@test "state_json_write writes valid JSON atomically" {
  local f="$JARVIS_HOME/test/tasks/foo.json"
  state_json_write "$f" '{"slug":"foo","status":"open"}'
  [ -f "$f" ]
  jq -e '.slug == "foo"' "$f" >/dev/null
}

@test "state_json_write rejects invalid JSON" {
  local f="$JARVIS_HOME/test/tasks/bad.json"
  run state_json_write "$f" 'not json{'
  [ "$status" -ne 0 ]
  [ ! -f "$f" ]
}

@test "state_json_read returns contents" {
  local f="$JARVIS_HOME/test/tasks/foo.json"
  state_json_write "$f" '{"slug":"foo"}'
  run state_json_read "$f"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.slug' <<< "$output")" = "foo" ]
}

@test "state_json_read exits 1 on missing file" {
  run state_json_read "$JARVIS_HOME/test/tasks/nope.json"
  [ "$status" -eq 1 ]
}

@test "state_json_write is atomic (no partial file on jq failure)" {
  local f="$JARVIS_HOME/test/tasks/atomic.json"
  state_json_write "$f" '{"seq":1}'
  # Attempt to overwrite with invalid content
  run state_json_write "$f" 'garbage'
  [ "$status" -ne 0 ]
  # Original must still be intact
  [ "$(jq -r '.seq' "$f")" = "1" ]
}
