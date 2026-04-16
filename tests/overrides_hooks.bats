#!/usr/bin/env bats
# Task 3.5 — command_pre / command_post override slots.
#
# Exercises the pre-/post-command hook dispatch wired into:
#   - lib/router/router.sh          (pre-hook before exec on both paths)
#   - lib/runtime/exec.sh           (post-hook via EXIT trap)

bats_require_minimum_version 1.5.0

load test_helper

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# Parsed command fixture: greet with one flag declared.
setup_parsed_cli() {
  create_test_cli "greet" "- {name: who, short: w, type: string, default: world, desc: 'Who to greet'}"
  # Replace the default task command with a real script invocation.
  cat > "$CLI_DIR/cmds/greet/greet.sh" <<'SH'
#!/usr/bin/env bash
echo "SCRIPT-RAN who=${CLIFT_FLAG_WHO:-}"
SH
  chmod +x "$CLI_DIR/cmds/greet/greet.sh"
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR" >/dev/null 2>&1 || true
  build_test_wrapper
}

# Passthrough command fixture: no vars.FLAGS block at all.
setup_passthrough_cli() {
  # Start from the standard fixture so most env is set up, then overwrite
  # the command Taskfile with a FLAGS-less (passthrough) version.
  create_test_cli "raw"
  # Remove vars.FLAGS to mark the task as passthrough in the index.
  cat > "$CLI_DIR/cmds/raw/Taskfile.yaml" <<YAML
version: '3'
tasks:
  default:
    cmd: "CLI_ARGS='{{.CLI_ARGS}}' '{{.FRAMEWORK_DIR}}/lib/router/router.sh' '{{.TASK}}'"
YAML
  cat > "$CLI_DIR/cmds/raw/raw.sh" <<'SH'
#!/usr/bin/env bash
echo "PASSTHROUGH-RAN args=$*"
SH
  chmod +x "$CLI_DIR/cmds/raw/raw.sh"
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR" >/dev/null 2>&1 || true
  build_test_wrapper
}

setup() {
  common_setup
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Pre-hook
# ---------------------------------------------------------------------------

@test "command_pre fires before the script with the task name" {
  setup_parsed_cli
  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/command_pre.sh" <<'SH'
clift_override_command_pre() {
  # $1 default_fn, $2 task_name
  echo "PRE:$2"
}
SH

  run "$CLI_DIR/bin/$CLI_NAME" greet
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE:greet"* ]]
  [[ "$output" == *"SCRIPT-RAN"* ]]
  pre_line="$(printf '%s\n' "$output" | grep -n 'PRE:greet' | head -1 | cut -d: -f1)"
  script_line="$(printf '%s\n' "$output" | grep -n 'SCRIPT-RAN' | head -1 | cut -d: -f1)"
  [ "$pre_line" -lt "$script_line" ]
}

@test "command_pre non-zero exit aborts the command and skips post-hook" {
  setup_parsed_cli
  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/command_pre.sh" <<'SH'
clift_override_command_pre() {
  echo "PRE-ABORT"
  exit 9
}
SH
  cat > "$CLI_DIR/.clift/overrides/command_post.sh" <<'SH'
clift_override_command_post() {
  echo "POST-SENTINEL-SHOULD-NOT-APPEAR"
}
SH

  # Drive the router directly to get the real exit code. The wrapper path
  # goes through `task`, which remaps all non-zero exits to 201.
  CLIFT_ARG_COUNT=0 run bash "$FRAMEWORK_DIR/lib/router/router.sh" "greet"
  [ "$status" -eq 9 ]
  [[ "$output" == *"PRE-ABORT"* ]]
  [[ "$output" != *"SCRIPT-RAN"* ]]
  [[ "$output" != *"POST-SENTINEL-SHOULD-NOT-APPEAR"* ]]
}

@test "command_pre non-zero return (no exit) aborts the command with that code" {
  # Covers the `return N` abort path — distinct from `exit N` because a
  # function return lets the caller's if/||/$? plumbing see the code.
  setup_parsed_cli
  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/command_pre.sh" <<'SH'
clift_override_command_pre() {
  echo "PRE-RETURN"
  return 11
}
SH

  CLIFT_ARG_COUNT=0 run bash "$FRAMEWORK_DIR/lib/router/router.sh" "greet"
  [ "$status" -eq 11 ]
  [[ "$output" == *"PRE-RETURN"* ]]
  [[ "$output" != *"SCRIPT-RAN"* ]]
}

# ---------------------------------------------------------------------------
# Post-hook
# ---------------------------------------------------------------------------

@test "command_post fires after the script with the exit code" {
  setup_parsed_cli
  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/command_post.sh" <<'SH'
clift_override_command_post() {
  # $1 default_fn, $2 task_name, $3 exit_code
  echo "POST:$3"
}
SH

  run "$CLI_DIR/bin/$CLI_NAME" greet
  [ "$status" -eq 0 ]
  [[ "$output" == *"SCRIPT-RAN"* ]]
  [[ "$output" == *"POST:0"* ]]
  script_line="$(printf '%s\n' "$output" | grep -n 'SCRIPT-RAN' | head -1 | cut -d: -f1)"
  post_line="$(printf '%s\n' "$output" | grep -n 'POST:0' | head -1 | cut -d: -f1)"
  [ "$script_line" -lt "$post_line" ]
}

@test "command_post sees a non-zero exit code and preserves it" {
  setup_parsed_cli
  # Rewrite the script to exit 7 after producing output.
  cat > "$CLI_DIR/cmds/greet/greet.sh" <<'SH'
#!/usr/bin/env bash
echo "SCRIPT-RAN-THEN-FAILS"
exit 7
SH
  chmod +x "$CLI_DIR/cmds/greet/greet.sh"

  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/command_post.sh" <<'SH'
clift_override_command_post() {
  echo "POST:$3"
}
SH

  # Drive the router directly to get the real exit code (7, not task's 201).
  CLIFT_ARG_COUNT=0 run bash "$FRAMEWORK_DIR/lib/router/router.sh" "greet"
  [ "$status" -eq 7 ]
  [[ "$output" == *"SCRIPT-RAN-THEN-FAILS"* ]]
  [[ "$output" == *"POST:7"* ]]
}

@test "command_post does not change the final exit code" {
  setup_parsed_cli
  # Script exits 3; override's exit attempt must not win.
  cat > "$CLI_DIR/cmds/greet/greet.sh" <<'SH'
#!/usr/bin/env bash
exit 3
SH
  chmod +x "$CLI_DIR/cmds/greet/greet.sh"

  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/command_post.sh" <<'SH'
clift_override_command_post() {
  # Attempting to mutate exit status — must not take effect.
  return 0
}
SH

  # Drive the router directly to get the real exit code (3, not task's 201).
  CLIFT_ARG_COUNT=0 run bash "$FRAMEWORK_DIR/lib/router/router.sh" "greet"
  [ "$status" -eq 3 ]
}

@test "command_post fires via SIGINT" {
  if ! command -v timeout >/dev/null 2>&1; then
    skip "timeout not available"
  fi
  setup_parsed_cli
  cat > "$CLI_DIR/cmds/greet/greet.sh" <<'SH'
#!/usr/bin/env bash
echo "SLEEP-START"
sleep 5
echo "SLEEP-END-SHOULD-NOT-APPEAR"
SH
  chmod +x "$CLI_DIR/cmds/greet/greet.sh"

  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/command_post.sh" <<'SH'
clift_override_command_post() {
  echo "POST-SIGINT:$3"
}
SH

  run timeout --signal=INT 0.5 "$CLI_DIR/bin/$CLI_NAME" greet
  # Exit code on SIGINT is 130 (128 + SIGINT); timeout itself exits 124 or
  # forwards the signal-based exit. Accept either as long as the post-hook
  # fired.
  [[ "$output" == *"SLEEP-START"* ]]
  [[ "$output" == *"POST-SIGINT:"* ]]
  [[ "$output" != *"SLEEP-END-SHOULD-NOT-APPEAR"* ]]
}

@test "post-hook sees CLIFT_FLAGS" {
  setup_parsed_cli
  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/command_post.sh" <<'SH'
clift_override_command_post() {
  echo "FLAG:${CLIFT_FLAGS[who]:-UNSET}"
}
SH

  run "$CLI_DIR/bin/$CLI_NAME" greet --who alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"FLAG:alice"* ]]
}

# ---------------------------------------------------------------------------
# Tiers & defaults
# ---------------------------------------------------------------------------

@test "per-command tier wins over CLI-global for command_pre" {
  setup_parsed_cli
  mkdir -p "$CLI_DIR/.clift/overrides"
  mkdir -p "$CLI_DIR/cmds/greet/overrides"
  cat > "$CLI_DIR/.clift/overrides/command_pre.sh" <<'SH'
clift_override_command_pre() {
  echo "PRE-GLOBAL"
}
SH
  cat > "$CLI_DIR/cmds/greet/overrides/command_pre.sh" <<'SH'
clift_override_command_pre() {
  echo "PRE-PERCMD"
}
SH

  run "$CLI_DIR/bin/$CLI_NAME" greet
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE-PERCMD"* ]]
  [[ "$output" != *"PRE-GLOBAL"* ]]
}

@test "passthrough path also fires pre and post hooks" {
  setup_passthrough_cli
  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/command_pre.sh" <<'SH'
clift_override_command_pre() {
  echo "PRE-PT:$2"
}
SH
  cat > "$CLI_DIR/.clift/overrides/command_post.sh" <<'SH'
clift_override_command_post() {
  echo "POST-PT:$3"
}
SH

  run "$CLI_DIR/bin/$CLI_NAME" raw foo bar
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE-PT:raw"* ]]
  [[ "$output" == *"PASSTHROUGH-RAN"* ]]
  [[ "$output" == *"POST-PT:0"* ]]
  pre_line="$(printf '%s\n' "$output" | grep -n 'PRE-PT' | head -1 | cut -d: -f1)"
  script_line="$(printf '%s\n' "$output" | grep -n 'PASSTHROUGH-RAN' | head -1 | cut -d: -f1)"
  post_line="$(printf '%s\n' "$output" | grep -n 'POST-PT' | head -1 | cut -d: -f1)"
  [ "$pre_line" -lt "$script_line" ]
  [ "$script_line" -lt "$post_line" ]
}

@test "defaults emit no output when no override is registered" {
  setup_parsed_cli
  run "$CLI_DIR/bin/$CLI_NAME" greet
  [ "$status" -eq 0 ]
  # Only the script's own line should be present.
  [[ "$output" == *"SCRIPT-RAN"* ]]
  [[ "$output" != *"PRE:"* ]]
  [[ "$output" != *"POST:"* ]]
}
