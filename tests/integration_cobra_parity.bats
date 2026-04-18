#!/usr/bin/env bats
# Task 6.2 — cobra-parity multi-feature seam integration smoke-test.
#
# Every case below wires up the SAME fixture and exercises a different
# seam where Phase 1–5 features must compose:
#
#   * command aliases  (Phase 5, Task 5.1)
#   * persistent flags (Phase 2, Task 2.1)
#   * flag groups (mutually exclusive)  (Phase 2, Task 2.2)
#   * hidden commands  (Phase 4, Task 4.1)
#   * help_list override (banner wrap)  (Phase 3, Task 3.2)
#   * command_pre override             (Phase 3, Task 3.5)
#   * dynamic flag-value completers    (Phase 5, Task 5.5)
#
# The unit test suites exercise each feature in isolation. This file is the
# cross-feature guardrail — fire a single fixture through multiple pipelines
# and assert they all still compose. Bugs at the seam between features hide
# from single-feature suites; catching them here is the point.

bats_require_minimum_version 1.5.0

load test_helper

setup() { common_setup; }
teardown() { common_teardown; }

# --- Fixture ---------------------------------------------------------------

# Build the multi-feature fixture at $CLI_DIR. We write the files inline
# instead of calling create_test_cli because the latter is too narrow for a
# CLI that needs persistent flags + aliases + hidden cmd + overrides all
# stitched together.
_setup_parity_cli() {
  # Root Taskfile — includes the framework's `_help` namespace so
  # `mycli --help` can dispatch to `_help:list` (wrapper line 200 / 516).
  # Hidden commands are distinguished by `vars.HIDDEN: true` (per
  # hidden.bats), NOT by an `_`-prefixed include name — the wrapper's task
  # index filter at wrapper.sh.tmpl line 314 drops every `^_|:_` entry, so
  # an `_internal`-named include would not be dispatchable at all.
  # The heredoc is unquoted so ${FRAMEWORK_DIR} expands inline — this is
  # the same trick create_test_cli uses for .env.
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
    - {name: no-cache, type: bool, desc: "Force-rebuild the .clift cache"}
    - {name: version, type: bool, desc: "Version"}
  PERSISTENT_FLAGS:
    - {name: profile, type: string, default: "dev", desc: "Profile"}
includes:
  _help:
    taskfile: '${FRAMEWORK_DIR}/lib/help'
  deploy:
    taskfile: ./cmds/deploy
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

  # deploy command — aliases + mutex group + string flag (no `complete:`
  # field: dynamic completion is convention-only, discovered via a function
  # in .clift/overrides/completion.sh, not declared in the flag schema).
  mkdir -p "$CLI_DIR/cmds/deploy"
  cat > "$CLI_DIR/cmds/deploy/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: json,   type: bool,   group: format, exclusive: true, desc: "JSON output"}
    - {name: yaml,   type: bool,   group: format, exclusive: true, desc: "YAML output"}
    - {name: region, type: string, desc: "Region"}
tasks:
  default:
    desc: "Deploy the app"
    aliases: [d, dep]
    vars:
      FLAGS:
        - {name: json,   type: bool,   group: format, exclusive: true, desc: "JSON output"}
        - {name: yaml,   type: bool,   group: format, exclusive: true, desc: "YAML output"}
        - {name: region, type: string, desc: "Region"}
    cmd: "CLI_ARGS='{{.CLI_ARGS}}' '{{.FRAMEWORK_DIR}}/lib/router/router.sh' '{{.TASK}}'"
YAML

  # deploy script — writes an observable marker file AND stdout so tests
  # can assert both via --separate-stderr (stdout only from the script; PRE
  # goes to stderr from the hook).
  cat > "$CLI_DIR/cmds/deploy/deploy.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
line="deploy: profile=${CLIFT_FLAG_PROFILE:-unset} json=${CLIFT_FLAG_JSON:-unset} region=${CLIFT_FLAG_REGION:-unset}"
echo "$line"
echo "$line" >> "${CLI_DIR}/deploy.out"
SH
  chmod +x "$CLI_DIR/cmds/deploy/deploy.sh"

  # Hidden command — marked HIDDEN at the task level (per hidden.bats
  # pattern: `vars.HIDDEN: true` on the command's root Taskfile). Command
  # name is `internal`, NOT `_internal`: the wrapper's dispatch filter
  # drops every `^_|:_` task entry before longest-prefix resolution, so
  # an underscore-prefixed name would be undispatchable — contradicting
  # the "hidden but still runnable" contract the test is pinning.
  mkdir -p "$CLI_DIR/cmds/internal"
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
set -euo pipefail
echo "internal-ran"
SH
  chmod +x "$CLI_DIR/cmds/internal/internal.sh"

  # Overrides — help_list banner, command_pre stderr marker, dynamic
  # completer for deploy's --region flag.
  mkdir -p "$CLI_DIR/.clift/overrides"

  cat > "$CLI_DIR/.clift/overrides/help_list.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
clift_override_help_list() {
  local default_fn="$1"; shift
  echo "=== BANNER ==="
  "$default_fn" "$@"
  echo "=== /BANNER ==="
}
SH

  # command_pre writes PRE to stderr so stdout tests that match the deploy
  # script's output line aren't polluted by the hook.
  cat > "$CLI_DIR/.clift/overrides/command_pre.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
clift_override_command_pre() {
  local default_fn="$1"; shift
  echo "PRE" >&2
  "$default_fn" "$@"
}
SH

  cat > "$CLI_DIR/.clift/overrides/completion.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
clift_complete_deploy_region() {
  printf '%s\n' us-east-1 us-west-2 eu-central-1
}
SH

  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
  build_test_wrapper
}

# --- 1. alias + persistent + group-valid + pre-hook ------------------------

# The full happy-path composition: alias resolves to `deploy`, persistent
# `--profile` binds from the pre-command position, the group-valid mutex
# pick (only `--json`) passes the group check, and the command_pre hook
# fires before the script. The hook writes PRE to stderr and the script
# writes its marker to stdout — both are observable. (go-task's
# `output: group` setting merges both streams onto stdout for the test
# runner, which is the intended framework behavior; the marker file proves
# the script ran, independent of stream routing.)
@test "alias + persistent + group-valid + pre-hook compose end-to-end" {
  _setup_parity_cli
  run "$CLI_DIR/bin/$CLI_NAME" d --profile=staging --json
  [ "$status" -eq 0 ]
  [[ "$output" == *"deploy: profile=staging json=true"* ]]
  [[ "$output" == *"PRE"* ]]
  # Marker file proves the script actually ran, not just that stdout had
  # the right string via some shortcut path.
  [[ -f "$CLI_DIR/deploy.out" ]]
  marker="$(<"$CLI_DIR/deploy.out")"
  [[ "$marker" == *"profile=staging"* ]]
  [[ "$marker" == *"json=true"* ]]
}

# --- 2. group mutex error --------------------------------------------------

# Violating the group's exclusivity must fire the mutex error (see
# lib/flags/errors.sh line 179: "mutually exclusive") and must abort
# BEFORE the deploy script runs — the marker file must not exist.
@test "group mutex: --json --yaml errors and deploy never runs" {
  _setup_parity_cli
  run "$CLI_DIR/bin/$CLI_NAME" d --json --yaml
  [ "$status" -ne 0 ]
  [[ "$output" == *"mutually exclusive"* ]]
  [[ "$output" == *"--json"* ]]
  [[ "$output" == *"--yaml"* ]]
  # Deploy script must not have fired.
  [ ! -f "$CLI_DIR/deploy.out" ]
}

# --- 3. help list: hidden filtered + banner wraps default ------------------

# The help_list override wraps the default renderer with a banner. In the
# same output, the hidden `internal` command must not appear, but the
# visible `deploy` command must. This is the composition of two independent
# filters (help list hidden-filter + override wrap) on the same render path.
@test "help list: banner present, hidden filtered, deploy present" {
  _setup_parity_cli
  run "$CLI_DIR/bin/$CLI_NAME" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"=== BANNER ==="* ]]
  [[ "$output" == *"=== /BANNER ==="* ]]
  [[ "$output" == *"deploy"* ]]
  [[ "$output" != *"internal"* ]]
}

# --- 4. hidden command still dispatchable ----------------------------------

# HIDDEN: true only filters help and completion candidates; the wrapper's
# dispatch layer must still route the name to the command. Regression
# guard for anyone tempted to make "hidden" mean "removed from the index".
@test "hidden command: absent from help list but still dispatchable" {
  _setup_parity_cli
  run "$CLI_DIR/bin/$CLI_NAME" internal
  [ "$status" -eq 0 ]
  [[ "$output" == *"internal-ran"* ]]
}

# --- 5. dynamic completer dispatch -----------------------------------------

# The hidden `_complete` subcommand (Task 5.5) sources the override file,
# builds the function name `clift_complete_<task>_<flag>`, and invokes it.
# Protocol matches tests/completion_dynamic.bats: one candidate per line,
# always exits 0.
@test "_complete deploy region: dynamic completer yields region list" {
  _setup_parity_cli
  run "$CLI_DIR/bin/$CLI_NAME" _complete deploy region
  [ "$status" -eq 0 ]
  [[ "$output" == *"us-east-1"* ]]
  [[ "$output" == *"us-west-2"* ]]
  [[ "$output" == *"eu-central-1"* ]]
}
