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

# --- Listing-shape assertion helpers ---------------------------------------

# A command is "listed" when it appears as the first column of a
# command-table row. `lib/help/list.sh` renders rows as
# `  <name>[, alias1, …]  <desc>` — the `sed 's/^/  /'` pass at
# list.sh:265 fixes the leading indent at EXACTLY two spaces, and
# `column -t -s $'\t'` rebuilds the name/desc separator with ≥2 spaces.
# The regex below anchors to that exact shape:
#
#   (line-start) + "  " (exactly 2 spaces) + needle + (space|comma|EOL)
#
# Width-anchoring the indent to two spaces (vs. the earlier
# `[[:space:]]+`) closes the false-positive case where a description
# line wrapped with different leading whitespace and happened to start
# with the needle word. Comma handles the `name, alias1, alias2`
# alias-joined form.
#
# Caller contract: `needle` is interpolated raw into a bash `=~` regex,
# so it must be a regex-literal with no metacharacters. Current callers
# use bare identifiers (`deploy`, `internal`); a future caller with a
# dotted, starred, or bracketed name must escape first.
_assert_listed() {
  local needle="$1" haystack="$2"
  # Caller must pass a regex-literal needle (no metachars).
  if [[ "$haystack" =~ (^|$'\n')"  "${needle}(" "|","|$) ]]; then
    return 0
  fi
  echo "expected '$needle' in command listing; got:" >&2
  echo "$haystack" >&2
  return 1
}

_refute_listed() {
  local needle="$1" haystack="$2"
  # Caller must pass a regex-literal needle (no metachars).
  if [[ "$haystack" =~ (^|$'\n')"  "${needle}(" "|","|$) ]]; then
    echo "hidden command '$needle' leaked into listing; got:" >&2
    echo "$haystack" >&2
    return 1
  fi
  return 0
}

# --- Fixture ---------------------------------------------------------------

# Build the multi-feature fixture at $CLI_DIR. We write the files inline
# instead of calling create_test_cli because the latter is too narrow for a
# CLI that needs persistent flags + aliases + hidden cmd + overrides all
# stitched together.
#
# Hidden commands are distinguished by `vars.HIDDEN: true` (per
# hidden.bats), NOT by an `_`-prefixed include name — the wrapper's task
# index filter at wrapper.sh.tmpl line 314 drops every `^_|:_` entry, so
# an `_internal`-named include would not be dispatchable at all.
# The root heredoc is unquoted so ${FRAMEWORK_DIR} expands inline — same
# trick create_test_cli uses for .env.
_setup_parity_cli() {
  # Root Taskfile — includes the framework's `_help` namespace so
  # `mycli --help` can dispatch to `_help:list` (wrapper line 200 / 516).
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
    # Re-declared on tasks.default to match test_helper.bash:107-121
    # convention; the compiler walks both layers and the router sees the
    # per-task list when it routes the default task.
    vars:
      FLAGS:
        - {name: json,   type: bool,   group: format, exclusive: true, desc: "JSON output"}
        - {name: yaml,   type: bool,   group: format, exclusive: true, desc: "YAML output"}
        - {name: region, type: string, desc: "Region"}
    cmd: "CLI_ARGS='{{.CLI_ARGS}}' '{{.FRAMEWORK_DIR}}/lib/router/router.sh' '{{.TASK}}'"
YAML

  # deploy script — writes an observable marker to BOTH stdout (for
  # grouped-output assertions) and a marker file (for "ran vs didn't run"
  # assertions that don't depend on go-task's output grouping).
  cat > "$CLI_DIR/cmds/deploy/deploy.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
line="deploy: profile=${CLIFT_FLAG_PROFILE:-unset} json=${CLIFT_FLAG_JSON:-unset} region=${CLIFT_FLAG_REGION:-unset}"
echo "$line"
echo "$line" >> "${CLI_DIR}/deploy.out"
SH
  chmod +x "$CLI_DIR/cmds/deploy/deploy.sh"

  # Hidden command — `vars.HIDDEN: true`. Name is 'internal', not
  # '_internal' — see the top-of-file fixture comment.
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

  # Overrides — help_list banner, command_pre marker, dynamic completer
  # for deploy's --region flag.
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

  # command_pre writes PRE to stderr. go-task's `output: group` config on
  # the root Taskfile merges stderr onto stdout from the test runner's
  # view, so PRE is observable in $output — asserting on stream separation
  # at this seam would fight the framework, not reveal bugs. The marker
  # file below does the "ran vs didn't run" job independently.
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
# `--profile` binds from the post-command position (covered here), the
# group-valid mutex pick (only `--json`) passes the group check, and the
# command_pre hook fires before the script. The pre-command persistent
# binding path is exercised separately in Test 6.
@test "alias + persistent(post) + group-valid + pre-hook compose end-to-end" {
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
# same output, the hidden `internal` command must not appear as a listing
# row, but the visible `deploy` command must. Listing-shape assertions
# (via _assert_listed / _refute_listed) anchor the check to indented
# leading-column rows so that banner/description text containing the
# substring "internal" or "deploy" can't drive false passes or failures.
@test "help list: banner present, hidden filtered, deploy present" {
  _setup_parity_cli
  run "$CLI_DIR/bin/$CLI_NAME" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"=== BANNER ==="* ]]
  [[ "$output" == *"=== /BANNER ==="* ]]
  _assert_listed "deploy" "$output"
  _refute_listed "internal" "$output"
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

# --- 6. pre-command persistent flag + alias (I3) ---------------------------

# Test 1 exercises the POST-command persistent binding path. The wrapper
# has a dedicated PRE-command early-bind loop (wrapper.sh.tmpl:552-610)
# that fires only when a persistent flag appears BEFORE the first
# non-flag token. That loop runs alongside alias resolution, and the seam
# between the two is exactly the kind of compose-bug single-feature
# suites can't reach. `mycli --profile=staging d --json` must:
#   - bind --profile via the pre-command path
#   - resolve alias `d` to canonical `deploy` after the persistent flag
#   - still parse --json as a deploy-level flag post-command
@test "pre-command persistent flag + alias: --profile=staging d --json resolves both" {
  _setup_parity_cli
  run "$CLI_DIR/bin/$CLI_NAME" --profile=staging d --json
  [ "$status" -eq 0 ] \
    || { echo "exit=$status output=$output"; false; }
  [[ "$output" == *"profile=staging"* ]] \
    || { echo "expected profile=staging; got: $output"; false; }
  [[ "$output" == *"json=true"* ]] \
    || { echo "expected json=true; got: $output"; false; }
  [[ -f "$CLI_DIR/deploy.out" ]] \
    || { echo "deploy.out marker missing"; false; }
}

# --- 7. alias --help resolves to canonical (S1) ----------------------------

# `mycli d --help` must render the DEPLOY detail page, not a "d" page.
# The wrapper substitutes alias → canonical at the first token of the
# longest-prefix walk (mirrors tests/aliases_cmd.bats line 145+); if that
# substitution moves downstream of --help interception this test fails.
#
# Anchor the header match to line-start: plain `*"$CLI_NAME deploy"*`
# also accepts a trailing `Run 'testcli deploy <cmd> --help'` hint, so
# a regression that drops the header but keeps the hint would pass.
# Prepending $'\n' to `$output` lets us use glob matching to anchor on
# either line-start or string-start without dropping into regex.
@test "command alias --help resolves to canonical deploy command" {
  _setup_parity_cli
  run "$CLI_DIR/bin/$CLI_NAME" d --help
  [ "$status" -eq 0 ]
  [[ $'\n'"$output" == *$'\n'"$CLI_NAME deploy "* ]] \
    || { echo "expected line-start '$CLI_NAME deploy ' header; got: $output"; false; }
  # Detail page must still advertise the command's flags.
  [[ "$output" == *"--json"* ]]
  [[ "$output" == *"--yaml"* ]]
  [[ "$output" == *"--region"* ]]
}

# --- 8. --task:dry passthrough (S2) ----------------------------------------

# `--task:*` flags are consumed by the wrapper's passthrough scan
# (wrapper.sh.tmpl:21-120) and forwarded to `task` with the prefix
# stripped. `--task:dry` drives go-task's dry-run mode: the task graph
# is walked but no command runs, so the deploy.sh script must NOT
# produce its marker file even though the full parser/group-check
# pipeline has fired.
#
# Positive assertion (guarding the "wrapper silently swallowed the flag"
# failure mode the reviewer flagged): the complementary invocation of
# the SAME fixture WITHOUT --task:dry DOES create the marker. That pins
# --task:dry as the observable differentiator — if the wrapper dropped
# the flag, the "dry" run would execute and the marker would appear,
# making it indistinguishable from the baseline run. (Note: under the
# fixture's `silent: true` + `output: group` root-Taskfile config,
# go-task emits no visible dry-run trace, so asserting on stdout
# shape is not viable; the marker-file contrast is the strongest
# observable signal available.)
@test "--task:dry passthrough does not execute deploy script" {
  _setup_parity_cli
  # Dry-run: pipeline fires, exec suppressed, no marker.
  run "$CLI_DIR/bin/$CLI_NAME" --task:dry d --json
  [ "$status" -eq 0 ] \
    || { echo "dry-run exit=$status output=$output"; false; }
  [[ ! -f "$CLI_DIR/deploy.out" ]] \
    || { echo "deploy.out created — dry-run should not execute"; false; }
  # Baseline: same invocation minus the dry flag runs the script and
  # DOES create the marker. Proves the flag is the only differentiator.
  run "$CLI_DIR/bin/$CLI_NAME" d --json
  [ "$status" -eq 0 ] \
    || { echo "baseline exit=$status output=$output"; false; }
  [[ -f "$CLI_DIR/deploy.out" ]] \
    || { echo "deploy.out missing from baseline run — fixture is broken"; false; }
}

# --- 9. persistent flag visible in CLIFT_FLAGS on PASSTHROUGH (I1) ---------

# `internal` is a passthrough command (vars.FLAGS: []). Without the router's
# passthrough-side CLIFT_FLAGS_FILE emit, the wrapper's persistent-flag
# bind exports CLIFT_FLAG_PROFILE but the prelude's CLIFT_FLAGS assoc array
# stays empty, contradicting docs/flags.md ("Persistent flags are accessible
# via the same CLIFT_FLAG_<NAME> / ${CLIFT_FLAGS[name]} machinery as
# per-command flags"). This test pins the assoc-array exposure.
@test "persistent flag visible in CLIFT_FLAGS on passthrough command (I1)" {
  _setup_parity_cli
  # Replace internal.sh with one that asserts on CLIFT_FLAGS[profile].
  cat > "$CLI_DIR/cmds/internal/internal.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "CLIFT_FLAGS[profile]=${CLIFT_FLAGS[profile]:-UNSET}"
echo "CLIFT_FLAG_PROFILE=${CLIFT_FLAG_PROFILE:-UNSET}"
SH
  chmod +x "$CLI_DIR/cmds/internal/internal.sh"

  run "$CLI_DIR/bin/$CLI_NAME" --profile=staging internal
  [ "$status" -eq 0 ] \
    || { echo "exit=$status output=$output"; false; }
  [[ "$output" == *"CLIFT_FLAGS[profile]=staging"* ]] \
    || { echo "expected CLIFT_FLAGS[profile]=staging on passthrough; got: $output"; false; }
  # Belt-and-suspenders: legacy env var path keeps working too.
  [[ "$output" == *"CLIFT_FLAG_PROFILE=staging"* ]] \
    || { echo "expected CLIFT_FLAG_PROFILE=staging; got: $output"; false; }
}
