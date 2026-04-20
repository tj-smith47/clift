#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load jarvis_helper

setup() {
  jarvis_common_setup
  mkdir -p "$JARVIS_HOME/test/tasks"
  printf '1\n' > "$JARVIS_HOME/test/state.version"
}
teardown() { jarvis_common_teardown; }

# Helper: run task.add.sh with a fake CLIFT_FLAGS/CLIFT_POS_1 env.
run_add() {
  local desc="$1"; shift
  local priority="${1:-med}"; shift || true
  local due="${1:-}"; shift || true
  local project="${1:-inbox}"; shift || true
  local urgency="${1:-}"; shift || true
  FRAMEWORK_DIR="$CLIFT_FRAMEWORK_DIR" \
  CLI_DIR="$CLIFT_JARVIS_DIR" \
  bash -c '
    set -euo pipefail
    declare -A CLIFT_FLAGS=(
      [priority]="'"$priority"'"
      [due]="'"$due"'"
      [project]="'"$project"'"
      [urgency]="'"$urgency"'"
    )
    export CLIFT_POS_1="'"$desc"'"
    source "$1"
  ' _ "$CLIFT_JARVIS_DIR/cmds/task/task.add.sh"
}

@test "task add creates tasks/<slug>.json and echoes slug" {
  run run_add "Fix k3s etcd"
  [ "$status" -eq 0 ]
  # Last stdout line is the slug (log_success goes to stderr via log.sh)
  local slug="${lines[-1]}"
  [ "$slug" = "fix-k3s-etcd" ]
  [ -f "$JARVIS_HOME/test/tasks/fix-k3s-etcd.json" ]
}

@test "task add persists all user-facing fields" {
  run run_add "Ship VHS demos" high today "release" ""
  [ "$status" -eq 0 ]
  local f="$JARVIS_HOME/test/tasks/ship-vhs-demos.json"
  [ "$(jq -r '.desc' "$f")" = "Ship VHS demos" ]
  [ "$(jq -r '.priority' "$f")" = "high" ]
  [ "$(jq -r '.due' "$f")" = "today" ]
  [ "$(jq -r '.project' "$f")" = "release" ]
  [ "$(jq -r '.status' "$f")" = "open" ]
  [ "$(jq -r '.seq' "$f")" = "1" ]
}

@test "task add without description exits 2" {
  run run_add ""
  [ "$status" -eq 2 ]
}

@test "task add rejects invalid --due with exit 2" {
  run run_add "foo" med "yesterdayish"
  [ "$status" -eq 2 ]
}

@test "task add accepts --due YYYY-MM-DD" {
  run run_add "foo" med "2026-05-01"
  [ "$status" -eq 0 ]
  local slug="${lines[-1]}"
  [ "$(jq -r '.due' "$JARVIS_HOME/test/tasks/$slug.json")" = "2026-05-01" ]
}

@test "task add collision appends -2 on second slug" {
  run_add "Fix k3s etcd" >/dev/null
  run run_add "Fix k3s etcd"
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "fix-k3s-etcd-2" ]
  [ -f "$JARVIS_HOME/test/tasks/fix-k3s-etcd.json" ]
  [ -f "$JARVIS_HOME/test/tasks/fix-k3s-etcd-2.json" ]
}

@test "task add with --urgency (no --priority) uses urgency value" {
  run run_add "Rotate creds" med "" inbox high
  [ "$status" -eq 0 ]
  local slug="${lines[-1]}"
  [ "$(jq -r '.priority' "$JARVIS_HOME/test/tasks/$slug.json")" = "high" ]
}

@test "task add increments seq per invocation" {
  run_add "one" >/dev/null
  run_add "two" >/dev/null
  run_add "three" >/dev/null
  [ "$(jq -r '.seq' "$JARVIS_HOME/test/tasks/one.json")" = "1" ]
  [ "$(jq -r '.seq' "$JARVIS_HOME/test/tasks/two.json")" = "2" ]
  [ "$(jq -r '.seq' "$JARVIS_HOME/test/tasks/three.json")" = "3" ]
}
