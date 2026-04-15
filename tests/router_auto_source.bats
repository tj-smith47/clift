#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load test_helper

# Task 2.1 — The router should boot user scripts through
# lib/runtime/exec.sh, which sources lib/runtime/prelude.sh (which in turn
# sources log.sh). A command script that never sources log.sh itself must
# still be able to call log_info / log_error / etc.

setup() {
  common_setup

  cat > "$CLI_DIR/Taskfile.yaml" <<'YAML'
version: '3'
dotenv: ['.env']
vars:
  FLAGS: []
includes:
  greet:
    taskfile: ./cmds/greet
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

  mkdir -p "$CLI_DIR/cmds/greet"
  cat > "$CLI_DIR/cmds/greet/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS: []
tasks:
  default:
    vars:
      FLAGS: []
    cmd: echo greet
YAML

  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
}

teardown() {
  common_teardown
}

@test "user script can call log_info without sourcing log.sh (parsed path)" {
  # No explicit `source ${FRAMEWORK_DIR}/lib/log/log.sh` — the prelude should
  # have provided it before this script was sourced.
  cat > "$CLI_DIR/cmds/greet/greet.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
log_info "hello from greet"
log_success "done"
SCRIPT
  chmod +x "$CLI_DIR/cmds/greet/greet.sh"

  run bash "$FRAMEWORK_DIR/lib/router/router.sh" "greet"
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello from greet"* ]]
  [[ "$output" == *"done"* ]]
}

@test "user script log_error writes to stderr (parsed path)" {
  cat > "$CLI_DIR/cmds/greet/greet.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
log_error "boom"
SCRIPT
  chmod +x "$CLI_DIR/cmds/greet/greet.sh"

  run bash "$FRAMEWORK_DIR/lib/router/router.sh" "greet"
  [ "$status" -eq 0 ]
  [[ "$output" == *"boom"* ]]
}

@test "die from user script exits non-zero with message" {
  cat > "$CLI_DIR/cmds/greet/greet.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
die "fatal condition" 7
SCRIPT
  chmod +x "$CLI_DIR/cmds/greet/greet.sh"

  run bash "$FRAMEWORK_DIR/lib/router/router.sh" "greet"
  [ "$status" -eq 7 ]
  [[ "$output" == *"fatal condition"* ]]
}

@test "BASH_ENV is not set by the framework during script execution" {
  cat > "$CLI_DIR/cmds/greet/greet.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
echo "BASH_ENV=${BASH_ENV:-UNSET}"
SCRIPT
  chmod +x "$CLI_DIR/cmds/greet/greet.sh"

  unset BASH_ENV
  run bash "$FRAMEWORK_DIR/lib/router/router.sh" "greet"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BASH_ENV=UNSET"* ]]
}

@test "framework never assigns BASH_ENV (grep invariant)" {
  # Complementary to the runtime check above: statically assert no file under
  # lib/ assigns BASH_ENV. Comments that mention BASH_ENV (lines like
  # `# note BASH_ENV=…`) are allowed; only real assignments are flagged.
  # `grep` returns 1 when there are no matches, which is the success case.
  run bash -c "grep -rnE 'BASH_ENV=' '$FRAMEWORK_DIR/lib/' --include='*.sh' --include='*.tmpl' | grep -vE '^[^:]*:[^:]*:[[:space:]]*#'"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "explicit source of log.sh in user script still works (back-compat)" {
  # Existing scripts that explicitly source log.sh must keep working; the
  # source guard in log.sh makes the second sourcing a no-op.
  cat > "$CLI_DIR/cmds/greet/greet.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
source "\${FRAMEWORK_DIR}/lib/log/log.sh"
log_info "double-sourced"
SCRIPT
  chmod +x "$CLI_DIR/cmds/greet/greet.sh"

  run bash "$FRAMEWORK_DIR/lib/router/router.sh" "greet"
  [ "$status" -eq 0 ]
  [[ "$output" == *"double-sourced"* ]]
}
