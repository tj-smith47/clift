#!/usr/bin/env bats
# Tests for Task 4.2: `mycli watch <cmd>` shorthand for `mycli --task:watch <cmd>`.
#
# The `watch` token, when it appears as the first argv element, is rewritten
# into `--task:watch` and the wrapper re-execs itself. The reservation only
# fires for the literal bare word "watch"; nested `watch:foo` is left alone.

bats_require_minimum_version 1.5.0
load test_helper

setup() {
  common_setup
  if ! command -v task >/dev/null 2>&1; then
    skip "go-task binary not on PATH"
  fi
}
teardown() { common_teardown; }

@test "mycli watch <cmd> enters watch mode (process runs until killed)" {
  # The watch token rewrites into --task:watch, which puts go-task into a
  # blocking loop. We prove the rewrite happened by observing that the
  # invocation does NOT exit on its own — it gets killed by `timeout`,
  # producing exit status 124 (or 137 from SIGKILL). A non-watching dispatch
  # would print GREET_RAN=yes and exit 0 immediately.
  create_test_cli "greet"
  cat > "$CLI_DIR/cmds/greet/greet.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "GREET_RAN=yes"
SH
  chmod +x "$CLI_DIR/cmds/greet/greet.sh"
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR" >/dev/null 2>&1 || true
  build_test_wrapper
  run timeout --signal=KILL 2 "$CLI_DIR/bin/$CLI_NAME" watch greet
  # Killed by timeout (137 = SIGKILL), or SIGTERM (143), or 124 (graceful).
  # The fact it didn't exit cleanly proves watch mode took hold.
  [ "$status" -ne 0 ]
  # The script DID run at least once (watch executes the body before polling).
  [[ "$output" == *"GREET_RAN=yes"* ]]
}

@test "mycli watch with no following command errors helpfully" {
  create_test_cli "greet"
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR" >/dev/null 2>&1 || true
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" watch
  [ "$status" -ne 0 ]
  [[ "$output" == *"watch requires a command"* ]]
}

@test "mycli watch <nonexistent> errors via normal unknown-command path" {
  # After the `watch` rewrite, the second wrapper invocation sees
  # `--task:watch bogusssss`, the --task:watch is consumed by the passthrough
  # scan, and `bogusssss` falls through to the longest-prefix walk where it
  # surfaces as the wrapper's standard unknown-command error.
  create_test_cli "greet"
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR" >/dev/null 2>&1 || true
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" watch bogusssss
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown command"* ]] || [[ "$output" == *"bogusssss"* ]]
}

@test "mycli watch preserves extra flags after the command" {
  # `mycli watch greet --who bob` must become `--task:watch greet --who bob`,
  # so the user-flag still reaches the script. We use a 2s timeout to bound
  # the watch loop; the first iteration runs the script before polling, so
  # WHO=bob will appear in the captured output even though the process is
  # killed before exiting cleanly.
  create_test_cli "greet" "- {name: who, type: string, default: world, desc: Who}"
  cat > "$CLI_DIR/cmds/greet/greet.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "WHO=${CLIFT_FLAG_WHO:-}"
SH
  chmod +x "$CLI_DIR/cmds/greet/greet.sh"
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR" >/dev/null 2>&1 || true
  build_test_wrapper
  run timeout --signal=KILL 2 "$CLI_DIR/bin/$CLI_NAME" watch greet --who bob
  # Watch mode persisted past initial run.
  [ "$status" -ne 0 ]
  [[ "$output" == *"WHO=bob"* ]]
  [[ "$output" != *"unknown flag"* ]]
  [[ "$output" != *"unknown command"* ]]
}

@test "nested watch:foo command still works (reserved only applies to first token)" {
  # Create a CLI whose cmds/ includes a `watch:foo` subcommand namespace.
  # Invoking it via `mycli watch:foo` (single token containing a colon) does
  # NOT trip the rewrite — the reservation only matches the bare word "watch".
  create_test_cli "greet"
  mkdir -p "$CLI_DIR/cmds/watch"
  cat > "$CLI_DIR/cmds/watch/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS: []
tasks:
  foo:
    vars:
      FLAGS: []
    cmd: "echo WATCH_FOO_RAN"
YAML
  # Wire the include into the root Taskfile (portable awk; no GNU sed -i).
  awk 'BEGIN{done=0} {print} /^includes:$/ && !done {print "  watch:"; print "    taskfile: ./cmds/watch"; done=1}' \
    "$CLI_DIR/Taskfile.yaml" > "$CLI_DIR/Taskfile.yaml.new"
  mv "$CLI_DIR/Taskfile.yaml.new" "$CLI_DIR/Taskfile.yaml"
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR" >/dev/null 2>&1 || true
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" watch:foo
  [ "$status" -eq 0 ]
  [[ "$output" == *"WATCH_FOO_RAN"* ]]
}
