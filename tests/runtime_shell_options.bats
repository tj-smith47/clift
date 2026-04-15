#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load test_helper

# Locks the behavioral contract that follows from Task 2.1 (source-based
# auto-load via lib/runtime/exec.sh):
#
#   1. User scripts run under `set -euo pipefail` by default (inherited
#      from exec.sh because `source` shares shell options).
#   2. Users can still opt out locally via `set +e` mid-script — `source`
#      semantics keep option changes confined to the script's execution.
#   3. `${BASH_SOURCE[0]}` resolves to the user script path; `$0` does
#      not — scripts that need to self-locate must use BASH_SOURCE.

setup() {
  common_setup

  cat > "$CLI_DIR/Taskfile.yaml" <<'YAML'
version: '3'
dotenv: ['.env']
vars:
  FLAGS: []
includes:
  run:
    taskfile: ./cmds/run
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

  mkdir -p "$CLI_DIR/cmds/run"
  cat > "$CLI_DIR/cmds/run/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS: []
tasks:
  default:
    vars:
      FLAGS: []
    cmd: echo run
YAML

  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
}

teardown() {
  common_teardown
}

@test "user script inherits errexit from exec.sh (no explicit set -e)" {
  # Script does NOT set -e itself. A failing command after the echo should
  # abort the script — proving errexit was inherited from the boot wrapper.
  cat > "$CLI_DIR/cmds/run/run.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "before"
false
echo "after"
SCRIPT
  chmod +x "$CLI_DIR/cmds/run/run.sh"

  run bash "$FRAMEWORK_DIR/lib/router/router.sh" "run"
  [ "$status" -ne 0 ]
  [[ "$output" == *"before"* ]]
  [[ "$output" != *"after"* ]]
}

@test "user script can opt out of errexit with set +e mid-flight" {
  # `source` semantics keep option changes confined to the current shell —
  # the user script can flip errexit off to tolerate a known-failing command
  # and then still run to completion.
  cat > "$CLI_DIR/cmds/run/run.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "start"
set +e
false
rc=$?
set -e
echo "rc=${rc}"
echo "end"
SCRIPT
  chmod +x "$CLI_DIR/cmds/run/run.sh"

  run bash "$FRAMEWORK_DIR/lib/router/router.sh" "run"
  [ "$status" -eq 0 ]
  [[ "$output" == *"start"* ]]
  [[ "$output" == *"rc=1"* ]]
  [[ "$output" == *"end"* ]]
}

@test "BASH_SOURCE[0] inside user script equals the script path" {
  # `$0` resolves to the boot wrapper because exec.sh sources the user
  # script; scripts that self-locate must use BASH_SOURCE instead.
  cat > "$CLI_DIR/cmds/run/run.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "BASH_SOURCE=${BASH_SOURCE[0]}"
SCRIPT
  chmod +x "$CLI_DIR/cmds/run/run.sh"

  run bash "$FRAMEWORK_DIR/lib/router/router.sh" "run"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BASH_SOURCE=${CLI_DIR}/cmds/run/run.sh"* ]]
}
