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
  # on its own line — the override must fully REPLACE that path, not run
  # alongside it. A bare inequality check ([[ "$output" != "hello from greet" ]])
  # passes even if both paths fire, so we assert the default line is absent
  # on its own line specifically.
  ! grep -qE '^hello from greet$' <<<"$output"
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

# --- 4c. log_error shadow works on the stderr path ---------------------------

@test "log: CLI-global override of log_error shadows framework default (stderr)" {
  # Symmetry with test 1, but for the stderr-bound helper. log_error writes
  # to fd 2 — if a future refactor forgets to re-stamp the exported function
  # for helpers that redirect to stderr, only this test will catch it.
  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/log.sh" <<'SH'
log_error() { printf 'ERR-CUSTOM: %s\n' "$*" >&2; }
SH

  cat > "$CLI_DIR/cmds/greet/greet.sh" <<'SH'
log_error "boom from greet"
SH

  run "$CLI_DIR/bin/$CLI_NAME" greet
  [ "$status" -eq 0 ]
  # BATS merges stderr into $output for `run` by default.
  [[ "$output" == *"ERR-CUSTOM: boom from greet"* ]]
  # Framework default's "minimal" theme emits "error: boom from greet";
  # the override must replace that path entirely.
  ! grep -qE '^error: boom from greet$' <<<"$output"
}

# --- 4d. log_error override reaches subshells via implicit re-export --------

@test "log: redefining an already-exported log_error implicitly re-exports for subshells" {
  # Same mechanism as test 4b, but exercised on the stderr helper. Locks the
  # claim that implicit re-export works for every log_* helper, not just
  # log_info — so a future refactor that drops `export -f` on log_error
  # specifically cannot silently break this contract.
  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/log.sh" <<'SH'
log_error() { printf 'IMPLICIT-ERR: %s\n' "$*" >&2; }
SH

  cat > "$CLI_DIR/cmds/greet/greet.sh" <<'SH'
log_error parent-err
bash -c 'log_error subshell-err'
SH

  run "$CLI_DIR/bin/$CLI_NAME" greet
  [ "$status" -eq 0 ]
  [[ "$output" == *"IMPLICIT-ERR: parent-err"* ]]
  [[ "$output" == *"IMPLICIT-ERR: subshell-err"* ]]
}

# --- 4e. log_debug shadow works under the VERBOSE gate -----------------------

@test "log: CLI-global override of log_debug shadows framework default (verbose-gated)" {
  # log_debug short-circuits unless VERBOSE=true. The override should replace
  # the gated path too — and the caller enables verbose via --verbose, which
  # the prelude/router translate into the VERBOSE env var consumed by log.sh.
  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/log.sh" <<'SH'
log_debug() { printf 'DBG-CUSTOM: %s\n' "$*" >&2; }
SH

  cat > "$CLI_DIR/cmds/greet/greet.sh" <<'SH'
log_debug "trace from greet"
SH

  run "$CLI_DIR/bin/$CLI_NAME" greet --verbose
  [ "$status" -eq 0 ]
  [[ "$output" == *"DBG-CUSTOM: trace from greet"* ]]
  # Framework default's "minimal" theme emits "debug: trace from greet";
  # the override must replace that path entirely.
  ! grep -qE '^debug: trace from greet$' <<<"$output"
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
