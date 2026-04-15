#!/usr/bin/env bats
# Task 3.1 — override loader foundation.
#
# Exercises lib/runtime/overrides.sh directly, without the full router path.
# Loader resolves two tiers (per-command → CLI-global), first-hit wins.

bats_require_minimum_version 1.5.0

load test_helper

# Source overrides.sh in a fresh sub-shell, ensuring the source guard is
# unset first so the test controls loading. `run` captures stdout from the
# helper script inside a bash -c subshell.
_run_loader() {
  local body="$1"
  run bash -c "
set -euo pipefail
export CLI_DIR='$CLI_DIR'
source '$FRAMEWORK_DIR/lib/runtime/overrides.sh'
$body
"
}

@test "_clift_load_override sources CLI-global file when present" {
  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/help_list.sh" <<'SH'
echo "global-loaded"
SH

  _run_loader '_clift_load_override help_list'
  [ "$status" -eq 0 ]
  [ "$output" = "global-loaded" ]
}

@test "_clift_load_override is a no-op when no override file exists" {
  _run_loader '_clift_load_override help_list; echo done'
  [ "$status" -eq 0 ]
  [ "$output" = "done" ]
}

@test "per-command override wins over CLI-global (global not loaded)" {
  mkdir -p "$CLI_DIR/.clift/overrides"
  mkdir -p "$CLI_DIR/cmds/deploy/overrides"
  cat > "$CLI_DIR/.clift/overrides/help_list.sh" <<'SH'
echo "global"
SH
  cat > "$CLI_DIR/cmds/deploy/overrides/help_list.sh" <<'SH'
echo "per-cmd"
SH

  _run_loader '_clift_load_override help_list deploy:prod'
  [ "$status" -eq 0 ]
  # Per-command file loaded, CLI-global file NOT loaded — output is a single
  # line from the per-cmd file only.
  [ "$output" = "per-cmd" ]
}

@test "_clift_load_override without task skips per-command tier" {
  mkdir -p "$CLI_DIR/.clift/overrides"
  mkdir -p "$CLI_DIR/cmds/deploy/overrides"
  cat > "$CLI_DIR/.clift/overrides/help_list.sh" <<'SH'
echo "global"
SH
  cat > "$CLI_DIR/cmds/deploy/overrides/help_list.sh" <<'SH'
echo "per-cmd"
SH

  # No task arg: only CLI-global is considered.
  _run_loader '_clift_load_override help_list'
  [ "$status" -eq 0 ]
  [ "$output" = "global" ]
}

@test "clift_call_override invokes default_fn when no override defined" {
  _run_loader '
_default_help() { echo "default:$*"; }
clift_call_override help_list _default_help a b c
'
  [ "$status" -eq 0 ]
  [ "$output" = "default:a b c" ]
}

@test "clift_call_override passes default_fn as \$1 to override" {
  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/help_list.sh" <<'SH'
clift_override_help_list() {
  echo "override-got-default:$1"
  echo "override-args:${@:2}"
}
SH

  _run_loader '
_default_help() { echo "default-ran"; }
clift_call_override help_list _default_help x y
'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "override-got-default:_default_help" ]
  [ "${lines[1]}" = "override-args:x y" ]
}

@test "override can delegate back to default via \$1" {
  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/help_list.sh" <<'SH'
clift_override_help_list() {
  echo "before"
  "$1" "${@:2}"
  echo "after"
}
SH

  _run_loader '
_default_help() { echo "default:$*"; }
clift_call_override help_list _default_help hello
'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "before" ]
  [ "${lines[1]}" = "default:hello" ]
  [ "${lines[2]}" = "after" ]
}

@test "sourcing overrides.sh twice is a no-op (source guard)" {
  run bash -c "
set -euo pipefail
export CLI_DIR='$CLI_DIR'
source '$FRAMEWORK_DIR/lib/runtime/overrides.sh'
# Mutate the functions to distinctive sentinels; a second source must NOT
# reset them (guard short-circuits).
_clift_load_override() { echo 'mutated-load'; }
clift_call_override() { echo 'mutated-call'; }
source '$FRAMEWORK_DIR/lib/runtime/overrides.sh'
_clift_load_override
clift_call_override
"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "mutated-load" ]
  [ "${lines[1]}" = "mutated-call" ]
}

@test "clift_call_override: --task without a value returns 2" {
  # log_error writes to stderr; call in a subshell so `run` captures combined.
  run bash -c "
set -uo pipefail
export CLI_DIR='$CLI_DIR'
source '$FRAMEWORK_DIR/lib/log/log.sh'
source '$FRAMEWORK_DIR/lib/runtime/overrides.sh'
_default() { echo default-ran; }
clift_call_override help_list _default --task
echo exit=\$?
" 2>&1
  [[ "$output" == *"--task requires a value"* ]]
  [[ "$output" == *"exit=2"* ]]
  # default_fn must NOT have run — we bailed before dispatch.
  [[ "$output" != *"default-ran"* ]]
}

@test "_clift_load_override: CLI_DIR unset yields a clear error (return 2)" {
  # Bash exits the subshell with 127 when `${X:?...}` triggers, because the
  # `echo exit=$?` line never runs (parameter error is treated as a fatal
  # command substitution failure). `run -127` pins that expectation so bats
  # doesn't emit a BW01 warning about an unexpected non-zero exit.
  run -127 bash -c "
set -uo pipefail
unset CLI_DIR
source '$FRAMEWORK_DIR/lib/log/log.sh'
source '$FRAMEWORK_DIR/lib/runtime/overrides.sh'
_clift_load_override help_list
echo exit=\$?
" 2>&1
  # The :? parameter expansion aborts the function with a clear message
  # mentioning CLI_DIR.
  [[ "$output" == *"CLI_DIR"* ]]
  [[ "$output" != *"exit=0"* ]]
}

@test "override file with a syntax error propagates failure (fail-loud)" {
  mkdir -p "$CLI_DIR/.clift/overrides"
  # Unterminated backtick is a parse error — bash refuses to source the file.
  cat > "$CLI_DIR/.clift/overrides/help_list.sh" <<'SH'
missing=`unterminated
SH

  run bash -c "
set -uo pipefail
export CLI_DIR='$CLI_DIR'
source '$FRAMEWORK_DIR/lib/log/log.sh'
source '$FRAMEWORK_DIR/lib/runtime/overrides.sh'
_clift_load_override help_list
echo exit=\$?
" 2>&1
  # Bash's own syntax-error message mentions the file and an error token.
  # We don't pin the exact wording (bash versions drift), but we require the
  # call to have failed (non-zero exit) and stderr to mention the issue.
  [[ "$output" == *"help_list.sh"* ]]
  [[ "$output" != *"exit=0"* ]]
}

@test "override that unsets clift_override_<slot> falls through to default_fn" {
  mkdir -p "$CLI_DIR/.clift/overrides"
  # Define the override, then immediately unset it. After sourcing,
  # `declare -F clift_override_help_list` must be empty — clift_call_override
  # falls back to the default.
  cat > "$CLI_DIR/.clift/overrides/help_list.sh" <<'SH'
clift_override_help_list() { echo "never-called"; }
unset -f clift_override_help_list
SH

  _run_loader '
_default_help() { echo "default:$*"; }
clift_call_override help_list _default_help a b
'
  [ "$status" -eq 0 ]
  [ "$output" = "default:a b" ]
}

@test "_clift_load_override rejects invalid slot names (path-traversal defense)" {
  run bash -c "
set -uo pipefail
export CLI_DIR='$CLI_DIR'
source '$FRAMEWORK_DIR/lib/log/log.sh'
source '$FRAMEWORK_DIR/lib/runtime/overrides.sh'
_clift_load_override '../../etc/passwd'
echo exit=\$?
" 2>&1
  [[ "$output" == *"invalid slot name"* ]]
  [[ "$output" == *"exit=2"* ]]
}

@test "_clift_load_override rejects uppercase / dash / dot slot names" {
  for bad in "Help_List" "help-list" "help.list" "1help" ""; do
    run bash -c "
set -uo pipefail
export CLI_DIR='$CLI_DIR'
source '$FRAMEWORK_DIR/lib/log/log.sh'
source '$FRAMEWORK_DIR/lib/runtime/overrides.sh'
_clift_load_override '$bad'
echo exit=\$?
" 2>&1
    [[ "$output" == *"invalid slot name"* ]] || {
      echo "slot '$bad' was not rejected; output=$output" >&2
      return 1
    }
    [[ "$output" == *"exit=2"* ]] || {
      echo "slot '$bad' did not return 2; output=$output" >&2
      return 1
    }
  done
}
