#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load jarvis_helper

setup() {
  jarvis_common_setup
  source "$CLIFT_JARVIS_DIR/lib/state/lock.sh"
  export LOCK_TARGET="$JARVIS_HOME/test/guarded.json"
  mkdir -p "$JARVIS_HOME/test"
}
teardown() { jarvis_common_teardown; }

@test "state_with_lock runs callback and releases lock" {
  state_with_lock "$LOCK_TARGET" 'printf hello > "$LOCK_TARGET"'
  [ "$(< "$LOCK_TARGET")" = "hello" ]
}

@test "state_with_lock serializes concurrent writers" {
  (state_with_lock "$LOCK_TARGET" 'sleep 0.2; printf A >> "$LOCK_TARGET"') &
  pid1=$!
  sleep 0.05
  (state_with_lock "$LOCK_TARGET" 'printf B >> "$LOCK_TARGET"') &
  pid2=$!
  wait "$pid1" "$pid2"
  # A must land before B due to serialization
  [ "$(< "$LOCK_TARGET")" = "AB" ]
}

@test "state_with_lock returns callback exit status" {
  run state_with_lock "$LOCK_TARGET" 'exit 7'
  [ "$status" -eq 7 ]
}
