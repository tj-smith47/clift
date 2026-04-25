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
  source "$CLIFT_JARVIS_DIR/lib/note/current.sh"
  state_ensure_tree
}
teardown() { jarvis_common_teardown; }

# Restrict PATH to coreutils (cat) only so the script's renderer fallback
# chain (glow → bat → cat) deterministically lands on cat. Avoids leaking
# whatever the dev box happens to have installed into the test output.
run_show() {
  local q="${CLIFT_POS_1:-}"
  env -i \
    HOME="$HOME" \
    PATH="$(dirname "$(command -v cat)")" \
    JARVIS_HOME="$JARVIS_HOME" JARVIS_PROFILE="$JARVIS_PROFILE" \
    CLI_DIR="$CLIFT_JARVIS_DIR" FRAMEWORK_DIR="$BATS_TEST_DIRNAME/.." \
    CLIFT_POS_1="$q" \
    bash "$CLIFT_JARVIS_DIR/cmds/note/note.show.sh" "$@"
}

@test "show by slug prints file body" {
  note_store_new inbox hi "Hi" >/dev/null
  note_store_append inbox/hi "hello world"
  CLIFT_POS_1="hi" run run_show
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello world"* ]]
}

@test "show by title (case-insensitive)" {
  note_store_new ref runbook "Restore Runbook" >/dev/null
  note_store_append ref/runbook "step 1" --no-timestamp
  CLIFT_POS_1="restore runbook" run run_show
  [ "$status" -eq 0 ]
  [[ "$output" == *"step 1"* ]]
}

@test "show by explicit kind/slug literal" {
  note_store_new inbox foo "Foo" >/dev/null
  note_store_append inbox/foo "exact path body" --no-timestamp
  CLIFT_POS_1="inbox/foo" run run_show
  [ "$status" -eq 0 ]
  [[ "$output" == *"exact path body"* ]]
}

@test "show without arg uses current" {
  note_store_new inbox foo "Foo" >/dev/null
  note_store_append inbox/foo "current body" --no-timestamp
  note_current_write "slug=inbox/foo"
  run run_show
  [ "$status" -eq 0 ]
  [[ "$output" == *"current body"* ]]
}

@test "show with unknown slug → exit 1" {
  CLIFT_POS_1="nope" run --separate-stderr run_show
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"not found"* ]]
}

@test "show without arg and no current → exit 2" {
  run --separate-stderr run_show
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"current"* ]]
}
