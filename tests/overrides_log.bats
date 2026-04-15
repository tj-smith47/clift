#!/usr/bin/env bats
# Task 3.4 — log.sh override slot.
#
# Unlike the other Phase 3 slots (help_list, help_detail, version_print,
# command_pre/post), the log slot is SHADOW-BASED, not callback-based.
# The prelude sources $CLI_DIR/.clift/overrides/log.sh AFTER lib/log/log.sh,
# and bash's "last-defined-wins" semantics let the user redefine log_info /
# log_error / log_warn / log_success / log_debug to transparently shadow the
# framework defaults. This avoids per-call callback indirection on the hot
# path (logging is called hundreds-to-thousands of times per command).

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  common_setup
  create_test_cli "greet" ""
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR" >/dev/null 2>&1 || true
  build_test_wrapper

  # User script that emits one log_info line. Sourced by exec.sh after
  # prelude.sh has loaded log.sh + the log override (if any).
  cat > "$CLI_DIR/cmds/greet/greet.sh" <<'SH'
log_info "hello from greet"
SH
  chmod +x "$CLI_DIR/cmds/greet/greet.sh"
}

teardown() {
  common_teardown
}

# --- 1. CLI-global override shadows the framework default --------------------

@test "log: CLI-global override of log_info shadows framework default" {
  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/log.sh" <<'SH'
log_info() { printf 'PREFIX-CUSTOM: %s\n' "$*"; }
SH

  run "$CLI_DIR/bin/$CLI_NAME" greet
  [ "$status" -eq 0 ]
  [[ "$output" == *"PREFIX-CUSTOM: hello from greet"* ]]
  # Framework default's "minimal" theme would emit just "hello from greet"
  # on its own line — the override replaces that path entirely.
  [[ "$output" != $'hello from greet' ]]
}

# --- 2. Framework default remains when no override file exists ---------------

@test "log: framework default remains when no override file exists" {
  run "$CLI_DIR/bin/$CLI_NAME" greet
  [ "$status" -eq 0 ]
  # minimal theme: log_info has no prefix, just the message.
  [[ "$output" == *"hello from greet"* ]]
  [[ "$output" != *"PREFIX-CUSTOM"* ]]
}

# --- 3. Per-command override beats CLI-global --------------------------------

@test "log: per-command override beats CLI-global" {
  mkdir -p "$CLI_DIR/.clift/overrides"
  mkdir -p "$CLI_DIR/cmds/greet/overrides"
  cat > "$CLI_DIR/.clift/overrides/log.sh" <<'SH'
log_info() { printf 'GLOBAL: %s\n' "$*"; }
SH
  cat > "$CLI_DIR/cmds/greet/overrides/log.sh" <<'SH'
log_info() { printf 'PER-CMD: %s\n' "$*"; }
SH

  run "$CLI_DIR/bin/$CLI_NAME" greet
  [ "$status" -eq 0 ]
  [[ "$output" == *"PER-CMD: hello from greet"* ]]
  [[ "$output" != *"GLOBAL:"* ]]
}

# --- 4a. Subshell inheritance — override that re-exports propagates ---------

@test "log: override that re-exports log_info reaches subshells" {
  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/log.sh" <<'SH'
log_info() { printf 'EXPORTED-OVERRIDE: %s\n' "$*"; }
export -f log_info
SH

  cat > "$CLI_DIR/cmds/greet/greet.sh" <<'SH'
bash -c 'log_info subshell-msg'
SH

  run "$CLI_DIR/bin/$CLI_NAME" greet
  [ "$status" -eq 0 ]
  [[ "$output" == *"EXPORTED-OVERRIDE: subshell-msg"* ]]
}

# --- 4b. Subshell inheritance — implicit re-export of redefined functions ---

@test "log: redefining an already-exported log_info implicitly re-exports for subshells" {
  # Bash semantics gotcha: once ANY version of a function has been export -f'd
  # (which the framework does in lib/log/log.sh), every subsequent redefinition
  # in the same shell automatically updates the exported BASH_FUNC_<name>%%
  # env var. So an "unexported" user override actually DOES propagate to
  # subshells — the framework's prior export is doing the work.
  #
  # We lock this in a test so future refactors don't accidentally drop the
  # framework's export -f and silently break this convenience (which would
  # surprise CLI authors who expect their override to be visible everywhere).
  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/log.sh" <<'SH'
log_info() { printf 'IMPLICIT: %s\n' "$*"; }
SH

  cat > "$CLI_DIR/cmds/greet/greet.sh" <<'SH'
log_info parent-msg
bash -c 'log_info subshell-msg'
SH

  run "$CLI_DIR/bin/$CLI_NAME" greet
  [ "$status" -eq 0 ]
  [[ "$output" == *"IMPLICIT: parent-msg"* ]]
  [[ "$output" == *"IMPLICIT: subshell-msg"* ]]
}

# --- 5. Calling the framework default via the rename idiom -------------------

@test "log: override can delegate to the framework default via rename idiom" {
  mkdir -p "$CLI_DIR/.clift/overrides"
  # Idiom: copy the framework's log_info into a new name BEFORE redefining
  # log_info, then call the saved copy from the override body.
  cat > "$CLI_DIR/.clift/overrides/log.sh" <<'SH'
eval "_orig_log_info() $(declare -f log_info | tail -n +2)"
log_info() {
  printf 'BEFORE\n'
  _orig_log_info "$@"
  printf 'AFTER\n'
}
SH

  run "$CLI_DIR/bin/$CLI_NAME" greet
  [ "$status" -eq 0 ]
  [[ "$output" == *"BEFORE"* ]]
  [[ "$output" == *"hello from greet"* ]]
  [[ "$output" == *"AFTER"* ]]
  before_line="$(printf '%s\n' "$output" | grep -n '^BEFORE$' | head -1 | cut -d: -f1)"
  msg_line="$(printf '%s\n' "$output" | grep -n 'hello from greet' | head -1 | cut -d: -f1)"
  after_line="$(printf '%s\n' "$output" | grep -n '^AFTER$' | head -1 | cut -d: -f1)"
  [ "$before_line" -lt "$msg_line" ]
  [ "$msg_line" -lt "$after_line" ]
}
