#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load test_helper

# Task 2.1 — log.sh uses `export -f` on log_info / log_error / log_warn /
# log_success / log_debug / die so that non-interactive bash subshells
# spawned by the user script (e.g. `$(bash -c '...')`) inherit the helpers
# without BASH_ENV and without re-sourcing log.sh.

setup() {
  common_setup

  cat > "$CLI_DIR/Taskfile.yaml" <<'YAML'
version: '3'
dotenv: ['.env']
vars:
  FLAGS: []
includes:
  sub:
    taskfile: ./cmds/sub
tasks:
  default:
    cmd: echo root
YAML

  cat > "$CLI_DIR/.env" <<ENV
CLI_NAME=$CLI_NAME
CLI_VERSION=$CLI_VERSION
CLI_DIR=$CLI_DIR
FRAMEWORK_DIR=$FRAMEWORK_DIR
ENV

  mkdir -p "$CLI_DIR/cmds/sub"
  cat > "$CLI_DIR/cmds/sub/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS: []
tasks:
  default:
    vars:
      FLAGS: []
    cmd: echo sub
YAML

  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
}

teardown() {
  common_teardown
}

@test "log_info is callable from a non-interactive bash subshell (\$(bash -c …))" {
  cat > "$CLI_DIR/cmds/sub/sub.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
result="$(bash -c 'log_info "from subshell"' 2>&1)"
echo "CAPTURED:${result}"
SCRIPT
  chmod +x "$CLI_DIR/cmds/sub/sub.sh"

  run bash "$FRAMEWORK_DIR/lib/router/router.sh" "sub"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CAPTURED:"*"from subshell"* ]]
}

@test "log_error is callable from a non-interactive bash subshell" {
  cat > "$CLI_DIR/cmds/sub/sub.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
bash -c 'log_error "subshell error"' 2>&1 | grep "subshell error"
SCRIPT
  chmod +x "$CLI_DIR/cmds/sub/sub.sh"

  run bash "$FRAMEWORK_DIR/lib/router/router.sh" "sub"
  [ "$status" -eq 0 ]
  [[ "$output" == *"subshell error"* ]]
}

@test "die is callable from a non-interactive bash subshell with proper exit code" {
  cat > "$CLI_DIR/cmds/sub/sub.sh" <<'SCRIPT'
#!/usr/bin/env bash
# errexit intentionally disabled so the non-zero subshell exit does not
# abort this script — we want to inspect $? afterward.
set +e
bash -c 'die "subshell die" 9' 2>&1
sub_rc=$?
echo "sub_status=${sub_rc}"
SCRIPT
  chmod +x "$CLI_DIR/cmds/sub/sub.sh"

  run bash "$FRAMEWORK_DIR/lib/router/router.sh" "sub"
  [ "$status" -eq 0 ]
  [[ "$output" == *"subshell die"* ]]
  [[ "$output" == *"sub_status=9"* ]]
}

@test "subshell inherits helpers without BASH_ENV (BASH_ENV must be unset)" {
  cat > "$CLI_DIR/cmds/sub/sub.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
# If BASH_ENV were how we load helpers, this subshell would still pick them
# up via that path. We assert (a) BASH_ENV is unset and (b) log_info still
# works — proving export -f is the delivery mechanism.
echo "BASH_ENV=${BASH_ENV:-UNSET}"
bash -c 'log_info "inherited without BASH_ENV"'
SCRIPT
  chmod +x "$CLI_DIR/cmds/sub/sub.sh"

  unset BASH_ENV
  run bash "$FRAMEWORK_DIR/lib/router/router.sh" "sub"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BASH_ENV=UNSET"* ]]
  [[ "$output" == *"inherited without BASH_ENV"* ]]
}
