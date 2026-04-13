#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR"
  export FRAMEWORK_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export RC_FILE="$TEST_DIR/.bashrc"
  touch "$RC_FILE"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "write alias entry adds sentinel + alias line" {
  source "$FRAMEWORK_DIR/lib/setup/rc.sh"
  clift_rc_write "$RC_FILE" "mycli" "alias mycli='task --taskfile /path/Taskfile.yaml'"
  run grep -c "^# clift: mycli$" "$RC_FILE"
  [ "$output" = "1" ]
  run grep -c "^alias mycli=" "$RC_FILE"
  [ "$output" = "1" ]
}

@test "re-writing entry replaces old content, no duplication" {
  source "$FRAMEWORK_DIR/lib/setup/rc.sh"
  clift_rc_write "$RC_FILE" "mycli" "alias mycli='old'"
  clift_rc_write "$RC_FILE" "mycli" "alias mycli='new'"
  run grep -c "^# clift: mycli$" "$RC_FILE"
  [ "$output" = "1" ]
  run grep -c "old" "$RC_FILE"
  [ "$output" = "0" ]
  run grep -c "new" "$RC_FILE"
  [ "$output" = "1" ]
}

@test "scrub removes sentinel and following entry line" {
  source "$FRAMEWORK_DIR/lib/setup/rc.sh"
  clift_rc_write "$RC_FILE" "mycli" "alias mycli='x'"
  clift_rc_scrub "$RC_FILE" "mycli"
  run grep -c "^# clift: mycli$" "$RC_FILE"
  [ "$output" = "0" ]
  run grep -c "alias mycli" "$RC_FILE"
  [ "$output" = "0" ]
}

@test "scrub preserves unrelated entries" {
  source "$FRAMEWORK_DIR/lib/setup/rc.sh"
  echo 'alias other="x"' >> "$RC_FILE"
  clift_rc_write "$RC_FILE" "mycli" "alias mycli='y'"
  clift_rc_scrub "$RC_FILE" "mycli"
  run grep -c 'alias other' "$RC_FILE"
  [ "$output" = "1" ]
}

@test "scrub on nonexistent file returns 0 (no-op)" {
  source "$FRAMEWORK_DIR/lib/setup/rc.sh"
  run clift_rc_scrub "$TEST_DIR/doesnotexist" "mycli"
  [ "$status" -eq 0 ]
}

@test "write multiple CLIs coexist in same rc file" {
  source "$FRAMEWORK_DIR/lib/setup/rc.sh"
  clift_rc_write "$RC_FILE" "cli1" "alias cli1='x'"
  clift_rc_write "$RC_FILE" "cli2" "alias cli2='y'"
  run grep -c "^# clift:" "$RC_FILE"
  [ "$output" = "2" ]
  # Scrub one, other remains
  clift_rc_scrub "$RC_FILE" "cli1"
  run grep -c "^# clift:" "$RC_FILE"
  [ "$output" = "1" ]
  run grep -c "alias cli2" "$RC_FILE"
  [ "$output" = "1" ]
}

@test "write preserves file permissions" {
  source "$FRAMEWORK_DIR/lib/setup/rc.sh"
  chmod 600 "$RC_FILE"
  clift_rc_write "$RC_FILE" "mycli" "alias mycli='x'"
  local perms
  perms=$(stat -c '%a' "$RC_FILE" 2>/dev/null || stat -f '%Lp' "$RC_FILE")
  [ "$perms" = "600" ]
}

@test "switching from alias to path export scrubs alias first" {
  source "$FRAMEWORK_DIR/lib/setup/rc.sh"
  clift_rc_write "$RC_FILE" "mycli" "alias mycli='x'"
  clift_rc_scrub "$RC_FILE" "mycli"
  clift_rc_write "$RC_FILE" "mycli" 'export PATH="/cli/bin:$PATH"'
  run grep -c "^# clift: mycli$" "$RC_FILE"
  [ "$output" = "1" ]
  run grep -c 'alias mycli' "$RC_FILE"
  [ "$output" = "0" ]
  run grep -c 'export PATH=' "$RC_FILE"
  [ "$output" = "1" ]
}
