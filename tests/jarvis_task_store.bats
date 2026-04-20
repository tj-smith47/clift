#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load jarvis_helper

setup() {
  jarvis_common_setup
  source "$CLIFT_JARVIS_DIR/lib/state/profile.sh"
  source "$CLIFT_JARVIS_DIR/lib/state/lock.sh"
  source "$CLIFT_JARVIS_DIR/lib/state/json.sh"
  source "$CLIFT_JARVIS_DIR/lib/task/store.sh"
  state_ensure_tree
}
teardown() { jarvis_common_teardown; }

@test "task_store_dir resolves under profile" {
  run task_store_dir
  [ "$status" -eq 0 ]
  [ "$output" = "$JARVIS_HOME/test/tasks" ]
}

@test "task_store_now_iso emits UTC YYYY-MM-DDTHH:MM:SSZ" {
  run task_store_now_iso
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "task_store_next_seq starts at 1 and increments monotonically" {
  run task_store_next_seq
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
  run task_store_next_seq
  [ "$output" = "2" ]
  run task_store_next_seq
  [ "$output" = "3" ]
}

@test "task_store_build emits valid JSON with all fields" {
  run task_store_build fix-k3s "Fix k3s etcd" med today inbox 7 null
  [ "$status" -eq 0 ]
  [ "$(jq -r '.slug' <<< "$output")" = "fix-k3s" ]
  [ "$(jq -r '.status' <<< "$output")" = "open" ]
  [ "$(jq -r '.priority' <<< "$output")" = "med" ]
  [ "$(jq -r '.due' <<< "$output")" = "today" ]
  [ "$(jq -r '.project' <<< "$output")" = "inbox" ]
  [ "$(jq -r '.seq' <<< "$output")" = "7" ]
  [ "$(jq -r '.jira_key' <<< "$output")" = "null" ]
  [ "$(jq -r '.done_at' <<< "$output")" = "null" ]
}

@test "task_store_put then task_store_get round-trips" {
  local payload
  payload="$(task_store_build foo "hello" low "" inbox 1 null)"
  task_store_put foo "$payload"
  [ -f "$JARVIS_HOME/test/tasks/foo.json" ]
  run task_store_get foo
  [ "$status" -eq 0 ]
  [ "$(jq -r '.desc' <<< "$output")" = "hello" ]
}

@test "task_store_exists reflects file presence" {
  run task_store_exists foo
  [ "$status" -ne 0 ]
  task_store_put foo "$(task_store_build foo "x" med "" inbox 1 null)"
  run task_store_exists foo
  [ "$status" -eq 0 ]
}

@test "task_store_delete removes file and lock sidecar" {
  task_store_put foo "$(task_store_build foo "x" med "" inbox 1 null)"
  : > "$JARVIS_HOME/test/tasks/foo.json.lock"
  task_store_delete foo
  [ ! -f "$JARVIS_HOME/test/tasks/foo.json" ]
  [ ! -f "$JARVIS_HOME/test/tasks/foo.json.lock" ]
}

@test "task_store_list orders by seq" {
  task_store_put a "$(task_store_build a "a" med "" inbox 2 null)"
  task_store_put b "$(task_store_build b "b" med "" inbox 1 null)"
  task_store_put c "$(task_store_build c "c" med "" inbox 3 null)"
  run task_store_list
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "b" ]
  [ "${lines[1]}" = "a" ]
  [ "${lines[2]}" = "c" ]
}

@test "task_store_list status=open excludes done" {
  task_store_put a "$(task_store_build a "a" med "" inbox 1 null)"
  local done_json
  done_json="$(task_store_build b "b" med "" inbox 2 null \
    | jq '.status = "done" | .done_at = "2026-04-20T00:00:00Z"')"
  task_store_put b "$done_json"
  run task_store_list open
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [ "${lines[0]}" = "a" ]
}

@test "task_store_set_done flips status and sets done_at" {
  task_store_put foo "$(task_store_build foo "x" med "" inbox 1 null)"
  task_store_set_done foo
  run task_store_get foo
  [ "$(jq -r '.status' <<< "$output")" = "done" ]
  [ "$(jq -r '.done_at' <<< "$output")" != "null" ]
}

@test "task_store_mutate applies jq filter and bumps updated_at" {
  task_store_put foo "$(task_store_build foo "x" med "" inbox 1 null)"
  sleep 1   # ensure updated_at monotonic
  task_store_mutate foo '.priority = "high"'
  run task_store_get foo
  [ "$(jq -r '.priority' <<< "$output")" = "high" ]
  [ "$(jq -r '.created_at != .updated_at' <<< "$output")" = "true" ]
}
