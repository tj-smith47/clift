#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load jarvis_helper

setup() {
  jarvis_common_setup
  export JARVIS_TODAY="2026-04-19"
  source "$CLIFT_JARVIS_DIR/lib/state/profile.sh"
  source "$CLIFT_JARVIS_DIR/lib/state/lock.sh"
  source "$CLIFT_JARVIS_DIR/lib/state/json.sh"
  source "$CLIFT_JARVIS_DIR/lib/frontmatter.sh"
  source "$CLIFT_JARVIS_DIR/lib/note/resolve.sh"
  source "$CLIFT_JARVIS_DIR/lib/note/index.sh"
  source "$CLIFT_JARVIS_DIR/lib/note/store.sh"
  state_ensure_tree
}
teardown() { jarvis_common_teardown; }

# Mirror note.new.bats's standalone-argv contract: the script parses raw
# argv when CLIFT_FLAGS isn't pre-populated. EDITOR is forced empty so the
# editor branch is never taken in tests (also covered by `[[ -t 1 ]]`).
run_daily() {
  local body="${CLIFT_POS_1:-}"
  env -i \
    HOME="$HOME" PATH="$PATH" \
    JARVIS_HOME="$JARVIS_HOME" \
    JARVIS_PROFILE="$JARVIS_PROFILE" \
    JARVIS_TODAY="$JARVIS_TODAY" \
    CLI_DIR="$CLIFT_JARVIS_DIR" \
    FRAMEWORK_DIR="$BATS_TEST_DIRNAME/.." \
    EDITOR="" \
    CLIFT_POS_1="$body" \
    bash "$CLIFT_JARVIS_DIR/cmds/note/note.daily.sh" "$@"
}

@test "daily missing + no body: creates from template (no-edit)" {
  run run_daily --no-edit
  [ "$status" -eq 0 ]
  local f
  f="$(note_path daily/2026-04-19)"
  [ -f "$f" ]
  # Template body landed in the file.
  grep -q '# Daily log' "$f"
  # Frontmatter: kind=daily, slug=date.
  [ "$(fm_get "$f" kind "")" = "daily" ]
  [ "$(fm_get "$f" slug "")" = "2026-04-19" ]
}

@test "daily missing + body: creates from template and appends" {
  CLIFT_POS_1="first entry" run run_daily --no-edit
  [ "$status" -eq 0 ]
  local f
  f="$(note_path daily/2026-04-19)"
  [ -f "$f" ]
  grep -q 'first entry' "$f"
  grep -q '# Daily log' "$f"
}

@test "daily exists + body: appends (single file, no rewrite)" {
  run run_daily --no-edit
  [ "$status" -eq 0 ]
  CLIFT_POS_1="second entry" run run_daily --no-edit
  [ "$status" -eq 0 ]
  local f
  f="$(note_path daily/2026-04-19)"
  grep -q 'second entry' "$f"
  # Only one daily file for this date.
  [ "$(find "$(note_root)/daily" -name '*.md' | wc -l)" -eq 1 ]
}

@test "daily exists + no body + no-edit: no-op (mtime unchanged)" {
  run run_daily --no-edit
  [ "$status" -eq 0 ]
  local f before after
  f="$(note_path daily/2026-04-19)"
  before="$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f")"
  sleep 1
  run run_daily --no-edit
  [ "$status" -eq 0 ]
  after="$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f")"
  [ "$before" = "$after" ]
}

@test "daily indexes the note (resolvable via .index.json)" {
  run run_daily --no-edit
  [ "$status" -eq 0 ]
  local idx
  idx="$(note_root)/.index.json"
  [ -f "$idx" ]
  [ "$(jq -r '."daily/2026-04-19".kind' "$idx")" = "daily" ]
}
