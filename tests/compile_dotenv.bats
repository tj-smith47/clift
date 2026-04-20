#!/usr/bin/env bats
# Regression: compile.sh must produce a populated flags.json even when the
# CLI uses {{.FRAMEWORK_DIR}} include paths that depend on dotenv-loaded
# values. go-task 3.x does NOT expose dotenv as `{{.VAR}}` template vars —
# it loads them as process env only. wrapper.sh.tmpl exports FRAMEWORK_DIR
# before invoking task; compile.sh must do the same or it produces an
# empty `flags.json` whenever invoked without the wrapper (fresh install,
# new:cmd, stale-cache rebuild).

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  common_setup
}
teardown() {
  common_teardown
}

@test "compile.sh resolves {{.FRAMEWORK_DIR}} via .env pre-export (go-task 3.x)" {
  # Build a minimal CLI with a .env that mirrors the jarvis example layout:
  # FRAMEWORK_DIR is a RELATIVE path (`../..`) resolved from CLI_DIR, and
  # CLI_DIR=`.` (runtime relative-pathing for task). The fix under test
  # absolutizes FRAMEWORK_DIR and preserves the caller-supplied $CLI_DIR.
  local cli_dir="$TEST_DIR/mycli"
  mkdir -p "$cli_dir/cmds/hello"
  local fw="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

  cat > "$cli_dir/.env" <<EOF
CLI_NAME=mycli
CLI_VERSION=1.0.0
CLI_DIR=.
FRAMEWORK_DIR=${fw}
LOG_THEME=minimal
CLIFT_MODE=standard
EOF

  cat > "$cli_dir/Taskfile.yaml" <<'EOF'
version: '3'
silent: true
dotenv: ['.env']
vars:
  FLAGS:
    - {name: help, short: h, type: bool, desc: "Show help"}
    - {name: verbose, short: v, type: bool, desc: "Verbose"}
    - {name: quiet, short: q, type: bool, desc: "Quiet"}
    - {name: no-color, type: bool, desc: "No color"}
    - {name: version, type: bool, desc: "Version"}
includes:
  _help:
    taskfile: '{{.FRAMEWORK_DIR}}/lib/help'
  hello:
    taskfile: ./cmds/hello
tasks:
  default:
    cmd: "echo root"
EOF

  cat > "$cli_dir/cmds/hello/Taskfile.yaml" <<'EOF'
version: '3'
vars:
  FLAGS:
    - {name: shout, type: bool, desc: "Uppercase output"}
tasks:
  default:
    desc: "Say hello"
    vars:
      FLAGS:
        - {name: shout, type: bool, desc: "Uppercase output"}
    cmd: "echo hi"
EOF

  run bash "${BATS_TEST_DIRNAME}/../lib/flags/compile.sh" "$cli_dir"
  [ "$status" -eq 0 ]
  [ -f "$cli_dir/.clift/flags.json" ]
  # flags.json must contain the hello command (either bare `hello` or
  # `hello:default` — both valid index entries).
  local hello_entries
  hello_entries="$(jq -r '[keys[] | select(. == "hello" or . == "hello:default")] | length' "$cli_dir/.clift/flags.json")"
  [ "$hello_entries" -ge 1 ]
  # And the `shout` flag must be present on the hello record.
  local shout_hit
  shout_hit="$(jq -r '(.hello // .["hello:default"] // []) | map(select(.name == "shout")) | length' "$cli_dir/.clift/flags.json")"
  [ "$shout_hit" = "1" ]
}

@test "compile.sh absolutizes relative FRAMEWORK_DIR from .env" {
  # Dotenv sets FRAMEWORK_DIR=../.. (relative). compile.sh must resolve it
  # relative to CLI_DIR before exporting, so task's include-resolution sees
  # an absolute path that works regardless of compile.sh's CWD.
  local cli_dir="$TEST_DIR/mycli"
  mkdir -p "$cli_dir/cmds/hello"

  cat > "$cli_dir/.env" <<'EOF'
CLI_NAME=mycli
CLI_VERSION=1.0.0
CLI_DIR=.
FRAMEWORK_DIR=%%FW%%
LOG_THEME=minimal
CLIFT_MODE=standard
EOF
  # Compute a path relative from $cli_dir → $FRAMEWORK_DIR (the real framework).
  local fw_abs
  fw_abs="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  # Build a relative path: .env lives at $cli_dir which is $TEST_DIR/mycli.
  # From $cli_dir, the real framework is `$fw_abs` absolute — pass a relative
  # form that uses a symlink detour to exercise the absolutization branch.
  mkdir -p "$cli_dir/.fwlink"
  ln -s "$fw_abs" "$cli_dir/.fwlink/framework"
  # Replace the placeholder: use a relative FRAMEWORK_DIR that must be
  # resolved against CLI_DIR.
  local tmp_env="$cli_dir/.env.new"
  sed "s|%%FW%%|./.fwlink/framework|g" "$cli_dir/.env" > "$tmp_env"
  mv "$tmp_env" "$cli_dir/.env"

  cat > "$cli_dir/Taskfile.yaml" <<'EOF'
version: '3'
silent: true
dotenv: ['.env']
vars:
  FLAGS:
    - {name: help, short: h, type: bool, desc: "Show help"}
    - {name: verbose, short: v, type: bool, desc: "Verbose"}
    - {name: quiet, short: q, type: bool, desc: "Quiet"}
    - {name: no-color, type: bool, desc: "No color"}
    - {name: version, type: bool, desc: "Version"}
includes:
  _help:
    taskfile: '{{.FRAMEWORK_DIR}}/lib/help'
  hello:
    taskfile: ./cmds/hello
tasks:
  default:
    cmd: "echo root"
EOF

  cat > "$cli_dir/cmds/hello/Taskfile.yaml" <<'EOF'
version: '3'
vars:
  FLAGS:
    - {name: shout, type: bool, desc: "Uppercase output"}
tasks:
  default:
    desc: "Say hello"
    vars:
      FLAGS:
        - {name: shout, type: bool, desc: "Uppercase output"}
    cmd: "echo hi"
EOF

  run bash "${BATS_TEST_DIRNAME}/../lib/flags/compile.sh" "$cli_dir"
  [ "$status" -eq 0 ]
  local keys_len
  keys_len="$(jq -r 'keys | length' "$cli_dir/.clift/flags.json")"
  [ "$keys_len" -ge 1 ]
}
