#!/usr/bin/env bats
# Regression guard: users must never see go-task's own logging (e.g.
# `task: [deploy] bash ...`) leak through any clift pathway. Every unique
# execution path deserves at least one assertion. If this file grows, that's
# a good sign — new dispatch paths should add their own silence check.

bats_require_minimum_version 1.5.0
load test_helper

setup() { common_setup; }
teardown() { common_teardown; }

# --- Helpers -----------------------------------------------------------

# Shared assertion: combined output (stdout+stderr) must not contain the
# task-logging prefix that go-task emits when not silenced.
_refute_task_prefix() {
  if [[ "$output" == *"task: ["* ]] || [[ "$output" == *"task:"*"] "* ]]; then
    printf 'unexpected task logging leaked:\n---\n%s\n---\n' "$output" >&2
    return 1
  fi
}

# Full noisy-output test: require task prefix ABSENT across stdout AND stderr
# combined (bats `run` collapses them unless `--separate-stderr` is set).

# --- Pathway: bare invocation (no args) --------------------------------
@test "silence: bare CLI invocation does not leak task prefix" {
  create_test_cli
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME"
  _refute_task_prefix
}

# --- Pathway: --help short-circuit at wrapper top level -----------------
@test "silence: --help at top level does not leak task prefix" {
  create_test_cli
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" --help
  _refute_task_prefix
}

# --- Pathway: -h short flag at top level --------------------------------
@test "silence: -h at top level does not leak task prefix" {
  create_test_cli
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" -h
  _refute_task_prefix
}

# --- Pathway: parsed command (FLAGS present) ----------------------------
@test "silence: parsed command execution does not leak task prefix" {
  create_test_cli "greet" '- {name: name, short: n, type: string, default: world}'
  cat > "$CLI_DIR/cmds/greet/greet.sh" <<'SH'
#!/usr/bin/env bash
echo "hello ${CLIFT_FLAG_NAME}"
SH
  chmod +x "$CLI_DIR/cmds/greet/greet.sh"
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" greet --name alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello alice"* ]]
  _refute_task_prefix
}

# --- Pathway: passthrough command (no FLAGS) ----------------------------
@test "silence: passthrough command does not leak task prefix" {
  create_test_cli "say"
  # Rewrite the cmd Taskfile WITHOUT vars.FLAGS to trigger the passthrough
  # code path (router execs the script with raw positional args, skipping
  # the parser entirely).
  cat > "$CLI_DIR/cmds/say/Taskfile.yaml" <<'YAML'
version: '3'
tasks:
  default:
    cmd: "CLI_ARGS='{{.CLI_ARGS}}' '{{.FRAMEWORK_DIR}}/lib/router/router.sh' '{{.TASK}}'"
YAML
  cat > "$CLI_DIR/cmds/say/say.sh" <<'SH'
#!/usr/bin/env bash
echo "$@"
SH
  chmod +x "$CLI_DIR/cmds/say/say.sh"
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" say hi there
  [ "$status" -eq 0 ]
  [[ "$output" == *"hi there"* ]]
  _refute_task_prefix
}

# --- Pathway: --version short-circuit -----------------------------------
@test "silence: --version does not leak task prefix" {
  create_test_cli
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" --version
  _refute_task_prefix
}

# --- Pathway: did-you-mean error path -----------------------------------
@test "silence: unknown command error does not leak task prefix" {
  create_test_cli "greet"
  cat > "$CLI_DIR/cmds/greet/greet.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$CLI_DIR/cmds/greet/greet.sh"
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" gret
  [ "$status" -ne 0 ]
  _refute_task_prefix
}

# --- Pathway: command --help (per-command help via wrapper intercept) ---
@test "silence: command --help does not leak task prefix" {
  create_test_cli "greet" '- {name: name, type: string}'
  cat > "$CLI_DIR/cmds/greet/greet.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$CLI_DIR/cmds/greet/greet.sh"
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" greet --help
  _refute_task_prefix
}

# --- Pathway: flag validation error (parser exits early) ----------------
@test "silence: parse-error output does not leak task prefix" {
  create_test_cli "widget" '- {name: count, type: int}'
  cat > "$CLI_DIR/cmds/widget/widget.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$CLI_DIR/cmds/widget/widget.sh"
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" widget --count notanint
  [ "$status" -ne 0 ]
  _refute_task_prefix
}
