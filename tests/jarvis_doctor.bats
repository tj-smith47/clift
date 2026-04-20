#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load jarvis_helper
setup() { jarvis_common_setup; }
teardown() { jarvis_common_teardown; }

@test "debug command directory no longer exists" {
  [ ! -d "$CLIFT_JARVIS_DIR/cmds/debug" ]
}

@test "debug not referenced in root Taskfile.yaml" {
  ! grep -qE '^\s*debug:' "$CLIFT_JARVIS_DIR/Taskfile.yaml"
}
