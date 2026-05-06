# Common test helper
#
# FILESYSTEM ISOLATION: every test must run with HOME redirected into
# TEST_DIR so nothing can write to the developer's real shell rc files,
# config dirs, or caches. Past test runs without this guard polluted the
# developer's real ~/.bashrc with stray alias entries pointing at /tmp dirs
# that no longer exist. Never remove the HOME redirect below.
#
# TRIPWIRE: HOME redirect is policy; the tripwire is enforcement. Every
# test snapshots a fixed list of "real-user files that must never change
# during a test run" at common_setup, then compares at common_teardown.
# If any drift, the test fails — even if every assertion in the test
# body passed. The list is real-$HOME paths captured BEFORE HOME is
# redirected. Tests that need to watch additional real-FS paths (e.g. a
# bin under /usr/local/bin) call `tripwire_watch <abs-path>` after
# common_setup. There is no opt-out — if a test legitimately needs to
# write under real $HOME (it shouldn't), it must be redesigned, not
# excluded.

# Default watchset — files under the developer's real $HOME that no test
# may touch. Add to this list when new shell rc / config conventions
# appear; do not remove entries.
_TRIPWIRE_DEFAULT_PATHS=(
  ".bashrc" ".bash_profile" ".bash_login" ".bash_aliases" ".bash_logout"
  ".profile" ".inputrc"
  ".zshrc" ".zprofile" ".zlogin" ".zshenv" ".zlogout"
  ".gitconfig" ".gitconfig.local"
  ".ssh/config" ".ssh/known_hosts" ".ssh/authorized_keys"
)

_tripwire_hash() {
  # Stream-hash a file via stdin so trailing-newline / sparse handling is
  # consistent with how the rest of the helper compares content. Prints
  # "MISSING" when the path doesn't exist so the snapshot distinguishes
  # absent-then-created from changed-content. Returns 0 always.
  local path="$1"
  if [[ -e "$path" ]]; then
    local sha
    sha="$(sha256sum < "$path" 2>/dev/null | awk '{print $1}')" || sha="UNREADABLE"
    local size
    size="$(stat -c '%s' "$path" 2>/dev/null || echo "UNREADABLE")"
    printf '%s\t%s' "$size" "$sha"
  else
    printf 'MISSING\tMISSING'
  fi
}

_tripwire_record() {
  # Append one snapshot line: "<absolute-path>\t<size>\t<sha256>"
  local path="$1"
  local rec
  rec="$(_tripwire_hash "$path")"
  printf '%s\t%s\n' "$path" "$rec" >> "$TRIPWIRE_SNAPSHOT"
}

tripwire_watch() {
  # Public helper — tests call this with an absolute path after
  # common_setup to extend the watchset for that single test.
  local path="$1"
  [[ "$path" = /* ]] || {
    printf 'tripwire_watch: path must be absolute (got %q)\n' "$path" >&2
    return 64
  }
  _tripwire_record "$path"
}

_tripwire_init() {
  # Snapshot every default path under the captured real $HOME, plus any
  # caller-extended paths (via tripwire_watch). Idempotent — overwrites
  # the snapshot file referenced by $TRIPWIRE_SNAPSHOT (which the caller
  # MAY pre-set; common_setup falls back to TEST_DIR-default).
  TRIPWIRE_SNAPSHOT="${TRIPWIRE_SNAPSHOT:-$TEST_DIR/.tripwire-snapshot}"
  : > "$TRIPWIRE_SNAPSHOT"
  local p
  for p in "${_TRIPWIRE_DEFAULT_PATHS[@]}"; do
    _tripwire_record "$TRIPWIRE_REAL_HOME/$p"
  done
}

_tripwire_check() {
  # Re-hash every recorded path and fail loudly on drift. Called from
  # common_teardown. Returns 1 when any path drifted; in BATS 1.5+ a
  # non-zero return from teardown marks the test failed.
  [[ -f "${TRIPWIRE_SNAPSHOT:-}" ]] || return 0
  local violations=()
  local path before_size before_sha after_rec after_size after_sha
  while IFS=$'\t' read -r path before_size before_sha; do
    after_rec="$(_tripwire_hash "$path")"
    after_size="${after_rec%%$'\t'*}"
    after_sha="${after_rec##*$'\t'}"
    if [[ "$before_size" != "$after_size" || "$before_sha" != "$after_sha" ]]; then
      violations+=("$path: size ${before_size}->${after_size}  sha ${before_sha:0:12}->${after_sha:0:12}")
    fi
  done < "$TRIPWIRE_SNAPSHOT"
  if (( ${#violations[@]} > 0 )); then
    {
      printf '\n'
      printf '!!! FILESYSTEM TRIPWIRE — real-user files mutated by this test !!!\n'
      printf 'test:  %s\n' "${BATS_TEST_NAME:-unknown}"
      printf 'file:  %s\n' "${BATS_TEST_FILENAME:-unknown}"
      printf 'real $HOME: %s\n' "$TRIPWIRE_REAL_HOME"
      printf 'drift detected:\n'
      printf '  %s\n' "${violations[@]}"
      printf 'fix: tests must redirect HOME to TEST_DIR (common_setup does this).\n'
      printf '     if a child process restores HOME (env -i, sudo -E, etc), pass\n'
      printf '     HOME="$HOME" explicitly through that boundary.\n'
    } >&2
    return 1
  fi
  return 0
}

common_setup() {
  # Capture real $HOME BEFORE we mutate it — tripwire compares against
  # this anchor, not the redirected HOME.
  TRIPWIRE_REAL_HOME="${HOME:?HOME must be set before common_setup}"
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR"
  export FRAMEWORK_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export CLI_DIR="$TEST_DIR"
  export CLI_NAME="testcli"
  export CLI_VERSION="1.0.0"
  export LOG_THEME="minimal"
  export PROMPT="false"
  export SHELL=/bin/bash
  # Second line of defense for setup.sh rc-file writes (see setup.sh line 130)
  export CLIFT_RC_FILE="$HOME/.bashrc"
  touch "$HOME/.bashrc"
  touch "$HOME/.zshrc"
  # Per-test snapshot file inside TEST_DIR — explicit so tests that wrap
  # _tripwire_init for their own canary use can swap to a sibling path
  # without colliding with the parent snapshot common_teardown checks.
  TRIPWIRE_SNAPSHOT="$TEST_DIR/.tripwire-snapshot"
  _tripwire_init
}

common_teardown() {
  local tripwire_rc=0
  _tripwire_check || tripwire_rc=$?
  rm -rf "$TEST_DIR"
  return "$tripwire_rc"
}

setup() {
  common_setup
}

teardown() {
  common_teardown
}

# Create a minimal CLI fixture at $CLI_DIR with:
#   - Root Taskfile with dotenv, FLAGS, includes
#   - .env with standard vars
#   - Optional: command dirs under cmds/
#
# Usage: create_test_cli [cmd_name] [cmd_flags_yaml]
# Examples:
#   create_test_cli                          # bare CLI, no commands
#   create_test_cli "greet"                  # command with empty FLAGS
#   create_test_cli "greet" "- {name: name, short: n, type: string, default: world}"
#
# Optional env var:
#   CLIFT_TEST_PERSISTENT_BLOCK — YAML fragment (full `  PERSISTENT_FLAGS: ...`
#   block, including the two-space indent) injected under vars: so tests can
#   declare CLI-wide persistent flags without re-scaffolding the root Taskfile.
create_test_cli() {
  local cmd_name="${1:-}"
  local cmd_flags="${2:-}"

  cat > "$CLI_DIR/Taskfile.yaml" <<'YAML'
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
    - {name: no-cache, type: bool, desc: "Force-rebuild the .clift cache before this command"}
    - {name: version, type: bool, desc: "Version"}
YAML

  if [[ -n "${CLIFT_TEST_PERSISTENT_BLOCK:-}" ]]; then
    printf '%s\n' "$CLIFT_TEST_PERSISTENT_BLOCK" >> "$CLI_DIR/Taskfile.yaml"
  fi

  echo "includes:" >> "$CLI_DIR/Taskfile.yaml"

  cat > "$CLI_DIR/.env" <<ENV
CLI_NAME=$CLI_NAME
CLI_VERSION=$CLI_VERSION
CLI_DIR=$CLI_DIR
FRAMEWORK_DIR=$FRAMEWORK_DIR
CLIFT_MODE=standard
LOG_THEME=minimal
ENV

  if [[ -n "$cmd_name" ]]; then
    # Add include to root Taskfile
    echo "  ${cmd_name}:" >> "$CLI_DIR/Taskfile.yaml"
    echo "    taskfile: ./cmds/${cmd_name}" >> "$CLI_DIR/Taskfile.yaml"

    # Add default task
    cat >> "$CLI_DIR/Taskfile.yaml" <<'YAML'
tasks:
  default:
    cmd: echo root
YAML

    mkdir -p "$CLI_DIR/cmds/${cmd_name}"

    {
      echo "version: '3'"
      echo "vars:"
      if [[ -n "$cmd_flags" ]]; then
        echo "  FLAGS:"
        echo "    ${cmd_flags}"
      else
        echo "  FLAGS: []"
      fi
      echo "tasks:"
      echo "  default:"
      echo "    vars:"
      if [[ -n "$cmd_flags" ]]; then
        echo "      FLAGS:"
        echo "        ${cmd_flags}"
      else
        echo "      FLAGS: []"
      fi
      echo "    cmd: \"CLI_ARGS='{{.CLI_ARGS}}' '{{.FRAMEWORK_DIR}}/lib/router/router.sh' '{{.TASK}}'\""
    } > "$CLI_DIR/cmds/${cmd_name}/Taskfile.yaml"
  else
    cat >> "$CLI_DIR/Taskfile.yaml" <<'YAML'
tasks:
  default:
    cmd: echo root
YAML
  fi
}

# Build the cobra-parity multi-feature integration fixture at $CLI_DIR.
#
# Writes the files inline (not via create_test_cli) because the fixture
# needs persistent flags + aliases + hidden cmd + overrides all stitched
# together — a shape create_test_cli does not cover.
#
# Default fixture includes:
#   * root Taskfile with PERSISTENT_FLAGS: [profile]
#   * deploy command (aliases d/dep, mutex group json|yaml, string flag region)
#   * hidden 'internal' command (vars.HIDDEN: true; passthrough)
#   * .clift/overrides/help_list.sh     (banner wrap)
#   * .clift/overrides/command_pre.sh   (echoes "PRE" to stderr then delegates)
#   * .clift/overrides/completion.sh    (dynamic completer for deploy --region)
#
# Hidden commands are distinguished by `vars.HIDDEN: true` (per
# hidden.bats), NOT by an `_`-prefixed include name — the wrapper's task
# index filter at wrapper.sh.tmpl line 314 drops every `^_|:_` entry, so
# an `_internal`-named include would not be dispatchable at all.
# The root heredoc is unquoted so ${FRAMEWORK_DIR} expands inline — same
# trick create_test_cli uses for .env.
#
# After writing files, compiles the cache and builds the wrapper so the
# fixture is immediately dispatchable.
#
# Caller contract: CLI_DIR, CLI_NAME, CLI_VERSION, FRAMEWORK_DIR must be
# set (common_setup establishes these).
#
# Optional env var knobs:
#   CLIFT_PARITY_EXTRA_PERSISTENT — YAML list fragment (just the `- {…}`
#     lines) appended to the PERSISTENT_FLAGS block so tests can exercise
#     multi-persistent seams without re-inlining the fixture. Indent each
#     line with FOUR spaces to match the block's two-space-under-vars
#     indentation plus two-space list-item indent.
#   CLIFT_PARITY_EXTRA_OVERRIDE_LOG — bash script body written to
#     `.clift/overrides/log.sh` when set (composition seam for log-shadow
#     × other overrides).
#   CLIFT_PARITY_EXTRA_OVERRIDE_HELP_DETAIL — bash script body written to
#     `.clift/overrides/help_detail.sh` when set (composition seam when
#     log_info is shadowed AND help_detail wraps).
setup_parity_cli() {
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
${CLIFT_PARITY_EXTRA_PERSISTENT:-}
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
  # '_internal' — see the top-of-function fixture comment.
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

  # Optional overrides written only when the caller sets the knob env vars.
  # Body is passed verbatim so callers can include whatever override
  # functions they need (log shadow, help_detail wrap, etc.).
  if [[ -n "${CLIFT_PARITY_EXTRA_OVERRIDE_LOG:-}" ]]; then
    printf '%s\n' "$CLIFT_PARITY_EXTRA_OVERRIDE_LOG" \
      > "$CLI_DIR/.clift/overrides/log.sh"
  fi
  if [[ -n "${CLIFT_PARITY_EXTRA_OVERRIDE_HELP_DETAIL:-}" ]]; then
    printf '%s\n' "$CLIFT_PARITY_EXTRA_OVERRIDE_HELP_DETAIL" \
      > "$CLI_DIR/.clift/overrides/help_detail.sh"
  fi

  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
  build_test_wrapper
}

# Render wrapper.sh.tmpl into $CLI_DIR/bin/$CLI_NAME.
# Requires CLI_DIR, CLI_NAME, CLI_VERSION, FRAMEWORK_DIR to be set.
build_test_wrapper() {
  mkdir -p "$CLI_DIR/bin"
  sed \
    -e "s|%%FRAMEWORK_DIR%%|$FRAMEWORK_DIR|g" \
    -e "s|%%CLI_DIR%%|$CLI_DIR|g" \
    -e "s|%%CLI_NAME%%|$CLI_NAME|g" \
    -e "s|%%CLI_VERSION%%|$CLI_VERSION|g" \
    "$FRAMEWORK_DIR/lib/wrapper/wrapper.sh.tmpl" > "$CLI_DIR/bin/$CLI_NAME"
  chmod +x "$CLI_DIR/bin/$CLI_NAME"
}
