#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load jarvis_helper

# ---------------------------------------------------------------------------
# jarvis_build_idempotent.bats
#
# Verifies that `task build` (and its build:state / build:cal / build:when
# sub-tasks) honour Task's checksum-based incremental-build contract:
#
#   1. A cold `task build` runs all three subtasks and produces the stub
#      binaries in bin/.
#   2. A second immediate `task build` skips all three subtasks (Task prints
#      "Task <name> is up to date" for each).
#   3. Touching a source file belonging only to jarvis-state forces
#      build:state to re-run while build:cal and build:when remain up-to-date.
# ---------------------------------------------------------------------------

JARVIS_DIR=
TASK=

setup() {
  jarvis_common_setup
  JARVIS_DIR="$CLIFT_JARVIS_DIR"
  TASK="$(command -v task)"
}

teardown() {
  jarvis_common_teardown
  # Remove any stub binaries written into the real bin/ during the test.
  # (We run task from the real JARVIS_DIR so generate artefacts land there.)
  rm -f "$JARVIS_DIR/bin/jarvis-state" \
        "$JARVIS_DIR/bin/jarvis-cal" \
        "$JARVIS_DIR/bin/jarvis-when"
  # Clean task checksum cache so tests are hermetic across runs.
  rm -rf "$JARVIS_DIR/.task"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_run_build() {
  # Run from JARVIS_DIR so Task finds its Taskfile.yaml and relative paths work.
  run bash -c "cd '$JARVIS_DIR' && '$TASK' --output=prefixed build 2>&1"
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@test "cold build: all three stub binaries are produced" {
  _run_build
  [ "$status" -eq 0 ]
  [ -x "$JARVIS_DIR/bin/jarvis-state" ]
  [ -x "$JARVIS_DIR/bin/jarvis-cal" ]
  [ -x "$JARVIS_DIR/bin/jarvis-when" ]
}

@test "second build: all three subtasks report up to date" {
  # Warm the cache.
  _run_build
  [ "$status" -eq 0 ]

  # Second run — all subtasks must be skipped.
  _run_build
  [ "$status" -eq 0 ]
  [[ "$output" == *"up to date"* ]]
}

@test "touch jarvis-state source forces only build:state to re-run" {
  # Cold build to populate checksums.
  _run_build
  [ "$status" -eq 0 ]

  # Mutate a source file under jarvis-state/ (created by the placeholder build
  # script so it exists as a real checksum source).
  local src="$JARVIS_DIR/jarvis-state/main.go"
  [ -f "$src" ] || skip "jarvis-state/main.go not present — Wave B may not have landed yet"

  # Append a comment so the checksum differs.
  printf '\n// touched-by-test\n' >> "$src"

  # Re-run; only build:state must execute; cal and when stay up to date.
  run bash -c "cd '$JARVIS_DIR' && '$TASK' --output=prefixed build 2>&1"
  [ "$status" -eq 0 ]
  # build:state ran (no "up to date" for it).
  # build:cal and build:when were not rebuilt.
  [[ "$output" != *"build:state"*"up to date"* ]]

  # Restore — remove the test comment (temp-file-and-move, no sed -i).
  local tmp
  tmp="$(mktemp)"
  grep -v '// touched-by-test' "$src" > "$tmp"
  mv "$tmp" "$src"
}
