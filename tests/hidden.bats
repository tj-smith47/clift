#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load test_helper

setup() { common_setup; }
teardown() { common_teardown; }

# -----------------------------------------------------------------------------
# Hidden flags: appear nowhere in help/completion but still parse normally.
# -----------------------------------------------------------------------------

@test "hidden flag is accepted by parser but absent from help listing" {
  create_test_cli "show" '- {name: secret, type: string, hidden: true, desc: "Secret flag"}'
  build_test_wrapper testcli

  # compile cache
  run bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
  [ "$status" -eq 0 ]

  # --help output must NOT mention the hidden flag
  run "$CLI_DIR/bin/testcli" show --help
  [ "$status" -eq 0 ]
  [[ "$output" != *"--secret"* ]]

  # Parser still accepts the hidden flag
  cat > "$CLI_DIR/cmds/show/show.sh" <<'SH'
#!/usr/bin/env bash
echo "SECRET=${CLIFT_FLAG_SECRET:-unset}"
SH
  chmod +x "$CLI_DIR/cmds/show/show.sh"

  run "$CLI_DIR/bin/testcli" show --secret=xyzzy
  [ "$status" -eq 0 ]
  [[ "$output" == *"SECRET=xyzzy"* ]]
}

@test "hidden flag absent from render_flags output" {
  run bash -c "
    source '$FRAMEWORK_DIR/lib/help/render_flags.sh'
    clift_render_flags '[{\"name\":\"visible\",\"type\":\"string\"},{\"name\":\"secret\",\"type\":\"string\",\"hidden\":true}]'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"--visible"* ]]
  [[ "$output" != *"--secret"* ]]
}

@test "generated bash completion script filters hidden flags in its jq pass" {
  CLIFT_MODE=standard run bash "$FRAMEWORK_DIR/lib/completion/completion.sh" bash
  [ "$status" -eq 0 ]
  # The jq expression inside the generated script must filter hidden flags.
  [[ "$output" == *"select(.hidden != true)"* ]]
}

@test "generated zsh completion script filters hidden flags and commands" {
  CLIFT_MODE=standard run bash "$FRAMEWORK_DIR/lib/completion/completion.sh" zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"select(.hidden != true)"* ]]
  [[ "$output" == *"select(.value.hidden == true)"* ]]
}

# -----------------------------------------------------------------------------
# Hidden commands: absent from --help and completion but still dispatchable.
# -----------------------------------------------------------------------------

# Build a test CLI with two commands — "visible" (normal) and "internal"
# (marked HIDDEN: true) — both dispatched through the router.
_setup_hidden_fixture() {
  cat > "$CLI_DIR/Taskfile.yaml" <<YAML
version: '3'
silent: true
output:
  group:
    begin: ''
    end: ''
set: [errexit, pipefail]
dotenv: ['.env']
vars:
  FLAGS:
    - {name: help, short: h, type: bool, desc: "Show help"}
    - {name: verbose, short: v, type: bool, desc: "Verbose"}
    - {name: quiet, short: q, type: bool, desc: "Quiet"}
    - {name: no-color, type: bool, desc: "No color"}
    - {name: version, type: bool, desc: "Version"}
includes:
  visible:
    taskfile: ./cmds/visible
  internal:
    taskfile: ./cmds/internal
tasks:
  default:
    cmd: echo root
YAML

  cat > "$CLI_DIR/.env" <<ENV
CLI_NAME=$CLI_NAME
CLI_VERSION=$CLI_VERSION
CLI_DIR=$CLI_DIR
FRAMEWORK_DIR=$FRAMEWORK_DIR
CLIFT_MODE=standard
LOG_THEME=minimal
ENV

  mkdir -p "$CLI_DIR/cmds/visible" "$CLI_DIR/cmds/internal"

  cat > "$CLI_DIR/cmds/visible/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS: []
tasks:
  default:
    vars:
      FLAGS: []
    cmd: "CLI_ARGS='{{.CLI_ARGS}}' '{{.FRAMEWORK_DIR}}/lib/router/router.sh' '{{.TASK}}'"
YAML
  cat > "$CLI_DIR/cmds/visible/visible.sh" <<'SH'
#!/usr/bin/env bash
echo "ran-visible"
SH
  chmod +x "$CLI_DIR/cmds/visible/visible.sh"

  cat > "$CLI_DIR/cmds/internal/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  HIDDEN: true
  FLAGS: []
tasks:
  default:
    vars:
      FLAGS: []
    cmd: "CLI_ARGS='{{.CLI_ARGS}}' '{{.FRAMEWORK_DIR}}/lib/router/router.sh' '{{.TASK}}'"
YAML
  cat > "$CLI_DIR/cmds/internal/internal.sh" <<'SH'
#!/usr/bin/env bash
echo "ran-internal"
SH
  chmod +x "$CLI_DIR/cmds/internal/internal.sh"
}

@test "hidden command is absent from --help listing" {
  _setup_hidden_fixture
  build_test_wrapper testcli
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"

  # Invoke the help renderer directly — the wrapper would route --help to
  # `_help:list` which requires the framework Taskfile includes. In-framework
  # tests skip that layer and call list.sh with the test CLI's Taskfile.
  CLIFT_MODE=standard run bash "$FRAMEWORK_DIR/lib/help/list.sh" "$CLI_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"visible"* ]]
  [[ "$output" != *"internal"* ]]
}

@test "hidden command remains executable when invoked directly" {
  _setup_hidden_fixture
  build_test_wrapper testcli
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"

  run "$CLI_DIR/bin/testcli" internal
  [ "$status" -eq 0 ]
  [[ "$output" == *"ran-internal"* ]]
}
