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

@test "doctor prints profile line with resolved path" {
  mkdir -p "$JARVIS_HOME/test"
  printf '1\n' > "$JARVIS_HOME/test/state.version"
  run bash "$CLIFT_JARVIS_DIR/cmds/doctor/doctor.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"profile"* ]]
  [[ "$output" == *"$JARVIS_HOME/test"* ]]
}

@test "doctor prints state schema line" {
  mkdir -p "$JARVIS_HOME/test"
  printf '1\n' > "$JARVIS_HOME/test/state.version"
  run bash "$CLIFT_JARVIS_DIR/cmds/doctor/doctor.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"state schema"* ]]
  [[ "$output" == *"v1"* ]]
}

@test "doctor --path prints resolved state dir and exits" {
  mkdir -p "$JARVIS_HOME/test"
  # doctor.sh reads CLIFT_FLAGS[path]; bats subshell needs explicit declaration.
  run bash -c 'declare -A CLIFT_FLAGS=([path]=true); source "$1"' _ "$CLIFT_JARVIS_DIR/cmds/doctor/doctor.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "$JARVIS_HOME/test" ]
}
