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

@test "pre-hook sees CLIFT_TASK and CLIFT_FLAG_* env vars" {
  setup_parsed_cli
  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/command_pre.sh" <<'SH'
clift_override_command_pre() {
  echo "TASK:${CLIFT_TASK:-UNSET}"
  echo "WHO:${CLIFT_FLAG_WHO:-UNSET}"
}
SH

  run "$CLI_DIR/bin/$CLI_NAME" greet --who bob
  [ "$status" -eq 0 ]
  [[ "$output" == *"TASK:greet"* ]]
  [[ "$output" == *"WHO:bob"* ]]
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

@test "passthrough command_pre non-zero return aborts with that code and skips post-hook" {
  # Mirror of the parsed `return N` abort test for the passthrough path.
  # Guards against the `if ! fn; then exit $?; fi` regression where $?
  # reads as 0 inside the then-branch, silently dropping the abort code.
  setup_passthrough_cli
  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/command_pre.sh" <<'SH'
clift_override_command_pre() {
  echo "PRE-PT-RETURN"
  return 9
}
SH
  cat > "$CLI_DIR/.clift/overrides/command_post.sh" <<'SH'
clift_override_command_post() {
  echo "POST-PT-SENTINEL-SHOULD-NOT-APPEAR"
}
SH

  # Drive the router directly to get the real exit code. The wrapper path
  # goes through `task`, which remaps all non-zero exits to 201.
  CLIFT_ARG_COUNT=0 run bash "$FRAMEWORK_DIR/lib/router/router.sh" "raw"
  [ "$status" -eq 9 ]
  [[ "$output" == *"PRE-PT-RETURN"* ]]
  [[ "$output" != *"PASSTHROUGH-RAN"* ]]
  [[ "$output" != *"POST-PT-SENTINEL-SHOULD-NOT-APPEAR"* ]]
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

@test "command_post exit N does not change the final exit code" {
  # Regression: a user `exit N` inside command_post must NOT preempt the
  # trap's final `exit "$rc"`. Containment relies on the subshell wrap in
  # lib/runtime/exec.sh (the `( … ) || true` around clift_call_override).
  # `return N` is tested above; `exit N` is the complementary escape path.
  setup_parsed_cli
  cat > "$CLI_DIR/cmds/greet/greet.sh" <<'SH'
#!/usr/bin/env bash
exit 5
SH
  chmod +x "$CLI_DIR/cmds/greet/greet.sh"

  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/command_post.sh" <<'SH'
clift_override_command_post() {
  echo "POST-BEFORE-EXIT:$3"
  exit 99
}
SH

  # Drive the router directly to get the real exit code (5, not task's 201).
  CLIFT_ARG_COUNT=0 run bash "$FRAMEWORK_DIR/lib/router/router.sh" "greet"
  [ "$status" -eq 5 ]
  [[ "$output" == *"POST-BEFORE-EXIT:5"* ]]
}

@test "command_post fires via SIGINT with rc=130" {
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
  # SIGINT must propagate as 130 into the post-hook's $3. The wrapper's
  # outer exit code may differ (task-runner may remap), but the post-hook
  # output is load-bearing: it proves our INT handler stashed _clift_user_rc.
  [[ "$output" == *"SLEEP-START"* ]]
  [[ "$output" == *"POST-SIGINT:130"* ]]
  [[ "$output" != *"SLEEP-END-SHOULD-NOT-APPEAR"* ]]
}

@test "command_post fires via SIGTERM with rc=143" {
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
  echo "POST-SIGTERM:$3"
}
SH

  run timeout --signal=TERM 0.5 "$CLI_DIR/bin/$CLI_NAME" greet
  [[ "$output" == *"SLEEP-START"* ]]
  [[ "$output" == *"POST-SIGTERM:143"* ]]
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

# ---------------------------------------------------------------------------
# Wrap pattern — overrides call "$1" "${@:2}" to delegate
# ---------------------------------------------------------------------------

@test "command_pre wrap pattern: override delegates to default then continues" {
  # The default command_pre is a no-op, so "delegates" is tautological
  # output-wise — the assertion is that calling `"$1" "${@:2}"` from the
  # override does not error and the command completes successfully.
  setup_parsed_cli
  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/command_pre.sh" <<'SH'
clift_override_command_pre() {
  "$1" "${@:2}"
  echo "WRAPPED-PRE:$2"
}
SH

  run "$CLI_DIR/bin/$CLI_NAME" greet
  [ "$status" -eq 0 ]
  [[ "$output" == *"WRAPPED-PRE:greet"* ]]
  [[ "$output" == *"SCRIPT-RAN"* ]]
}

@test "command_post wrap pattern: override delegates to default then continues" {
  setup_parsed_cli
  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/command_post.sh" <<'SH'
clift_override_command_post() {
  "$1" "${@:2}"
  echo "WRAPPED-POST:$3"
}
SH

  run "$CLI_DIR/bin/$CLI_NAME" greet
  [ "$status" -eq 0 ]
  [[ "$output" == *"SCRIPT-RAN"* ]]
  [[ "$output" == *"WRAPPED-POST:0"* ]]
}

# ---------------------------------------------------------------------------
# post-hook return semantics (complement to the existing exit N test)
# ---------------------------------------------------------------------------

@test "command_post return N does not change the final exit code" {
  # Companion to "command_post exit N does not change the final exit code":
  # proves `return N` is contained by the function-return path (not the
  # subshell wrap). Script exits 3; override `return 77`; final rc stays 3.
  setup_parsed_cli
  cat > "$CLI_DIR/cmds/greet/greet.sh" <<'SH'
#!/usr/bin/env bash
exit 3
SH
  chmod +x "$CLI_DIR/cmds/greet/greet.sh"

  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/command_post.sh" <<'SH'
clift_override_command_post() {
  echo "POST-RETURN:$3"
  return 77
}
SH

  CLIFT_ARG_COUNT=0 run bash "$FRAMEWORK_DIR/lib/router/router.sh" "greet"
  [ "$status" -eq 3 ]
  [[ "$output" == *"POST-RETURN:3"* ]]
}

# ---------------------------------------------------------------------------
# Passthrough post-hook with non-zero script exit
# ---------------------------------------------------------------------------

@test "command_post on passthrough with non-zero script exit preserves rc" {
  # Locks the contract that the passthrough path and parsed path both
  # surface the script's real rc to the post-hook, not a remapped code.
  setup_passthrough_cli
  cat > "$CLI_DIR/cmds/raw/raw.sh" <<'SH'
#!/usr/bin/env bash
echo "PASSTHROUGH-RAN args=$*"
exit 4
SH
  chmod +x "$CLI_DIR/cmds/raw/raw.sh"

  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/command_post.sh" <<'SH'
clift_override_command_post() {
  echo "PASSTHROUGH-POST:$3"
}
SH

  # Drive the router directly to get the real exit code (4, not task's 201).
  CLIFT_ARG_COUNT=0 run bash "$FRAMEWORK_DIR/lib/router/router.sh" "raw"
  [ "$status" -eq 4 ]
  [[ "$output" == *"PASSTHROUGH-RAN"* ]]
  [[ "$output" == *"PASSTHROUGH-POST:4"* ]]
}

# ---------------------------------------------------------------------------
# Tier depth — nested cmds/<a>/<b>/overrides/ must NOT be consulted
# ---------------------------------------------------------------------------

@test "nested tier depth is NOT consulted for command_pre (only first segment)" {
  # Rule: cmds/<first-seg>/overrides/<slot>.sh applies — any deeper nesting
  # (cmds/deploy/prod/overrides/…) is ignored. Set up a fixture for the
  # deploy:prod task, place an override at both the valid first-seg path
  # and the disallowed nested path, and assert only the first-seg sentinel
  # appears in output.
  create_test_cli "deploy" "- {name: region, type: string, default: us, desc: 'Region'}"

  # Rename the scaffolded command to deploy:prod shape.
  rm -rf "$CLI_DIR/cmds/deploy"
  mkdir -p "$CLI_DIR/cmds/deploy/prod/overrides"
  mkdir -p "$CLI_DIR/cmds/deploy/overrides"

  cat > "$CLI_DIR/cmds/deploy/Taskfile.yaml" <<'YAML'
version: '3'
tasks:
  prod:
    vars:
      FLAGS: []
    cmd: "CLI_ARGS='{{.CLI_ARGS}}' '{{.FRAMEWORK_DIR}}/lib/router/router.sh' '{{.TASK}}'"
YAML

  cat > "$CLI_DIR/cmds/deploy/deploy.prod.sh" <<'SH'
#!/usr/bin/env bash
echo "DEPLOY-PROD-RAN"
SH
  chmod +x "$CLI_DIR/cmds/deploy/deploy.prod.sh"

  # Re-wire root Taskfile to include the deploy namespace.
  cat > "$CLI_DIR/Taskfile.yaml" <<'YAML'
version: '3'
includes:
  deploy: ./cmds/deploy
tasks:
  default:
    cmd: echo "root default"
YAML

  # Valid first-segment tier — SHOULD fire on `deploy:prod`.
  cat > "$CLI_DIR/cmds/deploy/overrides/command_pre.sh" <<'SH'
clift_override_command_pre() {
  echo "FIRST-SEG-FIRED:$2"
}
SH
  # Disallowed nested tier — must NOT fire.
  cat > "$CLI_DIR/cmds/deploy/prod/overrides/command_pre.sh" <<'SH'
clift_override_command_pre() {
  echo "NESTED-SHOULD-NOT-FIRE"
}
SH

  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR" >/dev/null 2>&1 || true
  build_test_wrapper

  run "$CLI_DIR/bin/$CLI_NAME" deploy prod
  [ "$status" -eq 0 ]
  [[ "$output" == *"FIRST-SEG-FIRED:deploy:prod"* ]]
  [[ "$output" == *"DEPLOY-PROD-RAN"* ]]
  [[ "$output" != *"NESTED-SHOULD-NOT-FIRE"* ]]
}
