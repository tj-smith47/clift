#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load jarvis_helper

setup() {
  jarvis_common_setup
  mkdir -p "$JARVIS_HOME/test/tasks"
  printf '1\n' > "$JARVIS_HOME/test/state.version"
}
teardown() { jarvis_common_teardown; }

seed() {
  # usage: seed <slug> <desc> <priority> <status> <project> <due> <seq>
  local slug="$1" desc="$2" pri="$3" status="$4" proj="$5" due="$6" seq="$7"
  local due_json='null'
  [[ -n "$due" ]] && due_json="\"$due\""
  local done_at_json='null'
  [[ "$status" == "done" ]] && done_at_json='"2026-04-20T00:00:00Z"'
  jq -n \
    --arg slug "$slug" --arg desc "$desc" --arg pri "$pri" \
    --arg status "$status" --arg proj "$proj" --argjson due "$due_json" \
    --argjson seq "$seq" --argjson done_at "$done_at_json" '
    {
      slug: $slug, desc: $desc, status: $status, priority: $pri,
      due: $due, project: $proj,
      created_at: "2026-04-20T00:00:00Z", updated_at: "2026-04-20T00:00:00Z",
      done_at: $done_at, seq: $seq, jira_key: null
    }' > "$JARVIS_HOME/test/tasks/$slug.json"
}

run_list() {
  FRAMEWORK_DIR="$CLIFT_FRAMEWORK_DIR" \
  CLI_DIR="$CLIFT_JARVIS_DIR" \
  bash -c '
    set -euo pipefail
    declare -A CLIFT_FLAGS=(
      [all]="'"${1:-}"'"
      [priority]="'"${2:-}"'"
      [project]="'"${3:-}"'"
      [due]="'"${4:-}"'"
      [json]="'"${5:-}"'"
      [yaml]="'"${6:-}"'"
      [jira]=""
    )
    source "$1"
  ' _ "$CLIFT_JARVIS_DIR/cmds/task/task.list.sh"
}

@test "task list with no tasks prints 'no open tasks'" {
  run run_list
  [ "$status" -eq 0 ]
  [[ "$output" == *"no open tasks"* ]]
}

@test "task list shows open task rows" {
  seed fix-k3s "Fix k3s etcd" high open release today 1
  run run_list
  [ "$status" -eq 0 ]
  [[ "$output" == *"fix-k3s"* ]]
  [[ "$output" == *"Fix k3s etcd"* ]]
  [[ "$output" == *"today"* ]]
  [[ "$output" == *"release"* ]]
}

@test "task list hides done by default" {
  seed a "open one" med open inbox "" 1
  seed b "done one" med done inbox "" 2
  run run_list
  [[ "$output" == *"open one"* ]]
  [[ "$output" != *"done one"* ]]
}

@test "task list --all includes done" {
  seed a "open one" med open inbox "" 1
  seed b "done one" med done inbox "" 2
  run run_list true
  [[ "$output" == *"open one"* ]]
  [[ "$output" == *"done one"* ]]
}

@test "task list --priority high filters" {
  seed a "hi" high open inbox "" 1
  seed b "lo" low  open inbox "" 2
  run run_list "" high
  [[ "$output" == *"hi"* ]]
  [[ "$output" != *"lo"* ]]
}

@test "task list --project release filters" {
  seed a "rel" med open release "" 1
  seed b "inb" med open inbox "" 2
  run run_list "" "" release
  [[ "$output" == *"rel"* ]]
  [[ "$output" != *"inb"* ]]
}

@test "task list --due today filters" {
  seed a "due-today-task" med open inbox today 1
  seed b "due-tomorrow-task" med open inbox tomorrow 2
  run run_list "" "" "" today
  [[ "$output" == *"due-today-task"* ]]
  [[ "$output" != *"due-tomorrow-task"* ]]
}

@test "task list --json emits an array of records" {
  seed a "hello" med open inbox today 1
  seed b "world" high open inbox tomorrow 2
  run run_list "" "" "" "" true
  [ "$status" -eq 0 ]
  [ "$(jq -r 'length' <<< "$output")" = "2" ]
  [ "$(jq -r '.[0].slug' <<< "$output")" = "a" ]
  [ "$(jq -r '.[1].slug' <<< "$output")" = "b" ]
}

@test "task list orders by seq" {
  seed c "c" med open inbox "" 3
  seed a "a" med open inbox "" 1
  seed b "b" med open inbox "" 2
  run run_list "" "" "" "" true
  [ "$(jq -r '.[0].slug' <<< "$output")" = "a" ]
  [ "$(jq -r '.[1].slug' <<< "$output")" = "b" ]
  [ "$(jq -r '.[2].slug' <<< "$output")" = "c" ]
}
