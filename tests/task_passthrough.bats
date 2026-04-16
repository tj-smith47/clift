#!/usr/bin/env bats
# Tests for Task 4.3: --task:* passthrough.
#
# The --task:* prefix forwards selected go-task runner flags from the clift
# wrapper into the final `exec task ...` invocation. Tokens are scanned
# BEFORE the longest-prefix walk so they don't pollute command resolution.
# The whitelist is small and validated before any value-token is consumed.

bats_require_minimum_version 1.5.0
load test_helper

setup() {
  common_setup
  if ! command -v task >/dev/null 2>&1; then
    skip "go-task binary not on PATH"
  fi
}
teardown() { common_teardown; }

# -----------------------------------------------------------------------------
# Task 4.3: --task:* passthrough
# -----------------------------------------------------------------------------

@test "--task:dry runs go-task in dry mode (user script does not execute)" {
  # --dry makes task print what it would run without executing it. The real
  # script's sentinel must therefore NOT appear in the output.
  create_test_cli "greet"
  cat > "$CLI_DIR/cmds/greet/greet.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "GREET_RAN=yes"
SH
  chmod +x "$CLI_DIR/cmds/greet/greet.sh"
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR" >/dev/null 2>&1 || true
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" --task:dry greet
  [ "$status" -eq 0 ]
  [[ "$output" != *"GREET_RAN=yes"* ]]
}

@test "--task:list-all works at the top level" {
  create_test_cli "greet"
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR" >/dev/null 2>&1 || true
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" --task:list-all
  [ "$status" -eq 0 ]
  # The root taskfile has a `default` task; list-all must see it.
  [[ "$output" == *"default"* ]] || [[ "$output" == *"greet"* ]]
}

@test "--task:interval 500ms two-token form forwards value" {
  # --interval drives watch-mode polling. We don't need watch mode itself here;
  # we only need to prove the value token was consumed correctly. If the value
  # didn't forward, task would reject it with an `unknown option value` error
  # or interpret `500ms` as a task name.
  create_test_cli "greet"
  cat > "$CLI_DIR/cmds/greet/greet.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "GREET_RAN=yes"
SH
  chmod +x "$CLI_DIR/cmds/greet/greet.sh"
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR" >/dev/null 2>&1 || true
  build_test_wrapper
  # Combine with --task:dry so the test stays hermetic (no lingering watcher).
  run "$CLI_DIR/bin/$CLI_NAME" --task:dry --task:interval 500ms greet
  [ "$status" -eq 0 ]
  # Value-flag was consumed, greet still resolved.
  [[ "$output" != *"500ms"* ]] || [[ "$output" != *"unknown"* ]]
}

@test "--task:interval=500ms inline form forwards value" {
  create_test_cli "greet"
  cat > "$CLI_DIR/cmds/greet/greet.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "GREET_RAN=yes"
SH
  chmod +x "$CLI_DIR/cmds/greet/greet.sh"
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR" >/dev/null 2>&1 || true
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" --task:dry --task:interval=500ms greet
  [ "$status" -eq 0 ]
}

@test "unknown --task:foo flag errors with whitelist" {
  create_test_cli "greet"
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR" >/dev/null 2>&1 || true
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" --task:foo greet
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown --task: flag"* ]]
  [[ "$output" == *"foo"* ]]
  # Error body must advertise at least a couple of legitimate flags.
  [[ "$output" == *"watch"* ]]
  [[ "$output" == *"dry"* ]]
}

@test "--task:dry is stripped before dispatch walk (doesn't affect command resolution)" {
  # The wrapper's longest-prefix walk is greedy; if a --task:* flag leaked
  # through it would look like an unknown flag BEFORE the command, triggering
  # the flag-before-command error. Asserting a successful dispatch proves the
  # strip happened. Use --task:dry — it short-circuits inside go-task so the
  # test doesn't need to wait on the script itself.
  create_test_cli "greet"
  cat > "$CLI_DIR/cmds/greet/greet.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "GREET_RAN=yes"
SH
  chmod +x "$CLI_DIR/cmds/greet/greet.sh"
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR" >/dev/null 2>&1 || true
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" --task:dry greet
  [ "$status" -eq 0 ]
  [[ "$output" != *"unknown flag"* ]]
  [[ "$output" != *"flags must come after the command"* ]]
}

@test "--task:watch after -- terminator is NOT consumed (treated as literal argv)" {
  create_test_cli "greet"
  cat > "$CLI_DIR/cmds/greet/greet.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
for v in $(compgen -v CLIFT_ARG_ || true); do
  printf '%s=%s\n' "$v" "${!v}"
done
SH
  chmod +x "$CLI_DIR/cmds/greet/greet.sh"
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR" >/dev/null 2>&1 || true
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" greet -- --task:watch
  [ "$status" -eq 0 ]
  [[ "$output" == *"--task:watch"* ]]
}

@test "--task:* flags appear in top-level help list rendering" {
  # Top-level --help dispatches to `_help:list` which is handled by a framework
  # task that invokes list.sh. Test fixtures don't ship _help:list, so we
  # invoke list.sh directly — same pattern used by tests/help_list.bats.
  create_test_cli "greet"
  run bash "$FRAMEWORK_DIR/lib/help/list.sh" "$CLI_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Task runner flags"* ]]
  [[ "$output" == *"--task:watch"* ]]
  [[ "$output" == *"--task:dry"* ]]
  [[ "$output" == *"--task:interval"* ]]
  [[ "$output" == *"--task:concurrency"* ]]
}

@test "--task:silent is forwarded and accepted" {
  create_test_cli "greet"
  cat > "$CLI_DIR/cmds/greet/greet.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "GREET_RAN=yes"
SH
  chmod +x "$CLI_DIR/cmds/greet/greet.sh"
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR" >/dev/null 2>&1 || true
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" --task:silent greet
  [ "$status" -eq 0 ]
  [[ "$output" == *"GREET_RAN=yes"* ]]
}
