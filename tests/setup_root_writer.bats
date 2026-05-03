#!/usr/bin/env bats
# Tier 2F — `lib/setup/root_writer.sh::write_cli_skeleton`
#
# Verifies that the writer emits the top-level files of a brand-new clift
# CLI in the right shape, including the `framework_namespace` schema toggle
# and the stable user-includes sentinel that tier 4I will splice into.
#
# Filesystem isolation: HOME is redirected by common_setup; every fixture
# is written under $TEST_DIR.

bats_require_minimum_version 1.5.0

load test_helper

# Path under test plus the framework dir for the sourced module.
_ROOT_WRITER_SH="${BATS_TEST_DIRNAME}/../lib/setup/root_writer.sh"

# Shared fixture: a minimal source Taskfile with a couple of tasks. Used as
# the third argument to write_cli_skeleton — the writer copies it verbatim
# into Taskfile.user.yaml, so the contents must round-trip byte-for-byte.
_write_source_taskfile() {
  cat > "$TEST_DIR/source.yaml" <<'YAML'
version: '3'
tasks:
  build:
    desc: Build it
    cmd: echo building
  deploy:
    desc: Deploy it
    requires:
      vars: [ENV]
    cmd: echo "deploying to {{.ENV}}"
YAML
}

# _run_writer <name> <dest> [framework_namespace]
# Invokes write_cli_skeleton via a fresh subshell so the source-guard does
# not leak between cases.
_run_writer() {
  local name="$1" dest="$2" fwns="${3:-}"
  if [[ -n "$fwns" ]]; then
    run bash "$_ROOT_WRITER_SH" "$name" "$dest" "$TEST_DIR/source.yaml" "$fwns"
  else
    run bash "$_ROOT_WRITER_SH" "$name" "$dest" "$TEST_DIR/source.yaml"
  fi
}

@test "bare invocation (no framework namespace) writes .clift.yaml without framework_namespace" {
  _write_source_taskfile
  _run_writer "mycli" "$TEST_DIR/mycli"
  [ "$status" -eq 0 ]

  [ -f "$TEST_DIR/mycli/.clift.yaml" ]
  name="$(yq '.name' "$TEST_DIR/mycli/.clift.yaml")"
  [ "$name" = "mycli" ]

  version="$(yq '.version' "$TEST_DIR/mycli/.clift.yaml")"
  [ "$version" = "0.1.0" ]

  has_ns="$(yq 'has("framework_namespace")' "$TEST_DIR/mycli/.clift.yaml")"
  [ "$has_ns" = "false" ]

  required="$(yq -o=json '.dependencies.required' "$TEST_DIR/mycli/.clift.yaml")"
  [[ "$required" == *'"jq"'* ]]
  [[ "$required" == *'"yq"'* ]]

  optional="$(yq -o=json '.dependencies.optional' "$TEST_DIR/mycli/.clift.yaml")"
  [[ "$optional" == *'"gum"'* ]]
}

@test "framework_namespace=clift records framework_namespace in .clift.yaml" {
  _write_source_taskfile
  _run_writer "mycli" "$TEST_DIR/mycli" "clift"
  [ "$status" -eq 0 ]

  ns="$(yq '.framework_namespace' "$TEST_DIR/mycli/.clift.yaml")"
  [ "$ns" = "clift" ]
}

@test "generated Taskfile.yaml parses cleanly with yq" {
  _write_source_taskfile
  _run_writer "mycli" "$TEST_DIR/mycli"
  [ "$status" -eq 0 ]

  run yq '.' "$TEST_DIR/mycli/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"version"* ]]
}

@test "framework_namespace mode emits aggregator include + privileged framework internals" {
  _write_source_taskfile
  _run_writer "mycli" "$TEST_DIR/mycli" "clift"
  [ "$status" -eq 0 ]

  # The aggregator key is the namespace itself.
  agg="$(yq '.includes.clift.taskfile' "$TEST_DIR/mycli/Taskfile.yaml")"
  [[ "$agg" == *"_framework_aggregate.yaml" ]]

  # Privileged framework infrastructure stays at top level — the wrapper's
  # `--help` short-circuit hits `_help:list` and themed logging sources
  # `_log:`, both of which are unconditionally needed regardless of where
  # the user-facing framework commands live.
  has_help="$(yq '.includes | has("_help")' "$TEST_DIR/mycli/Taskfile.yaml")"
  [ "$has_help" = "true" ]
  has_log="$(yq '.includes | has("_log")' "$TEST_DIR/mycli/Taskfile.yaml")"
  [ "$has_log" = "true" ]

  # User-facing framework commands (`config`, `version`, `update`,
  # `completion`, `new`) move to `<fwns>:*` and are NOT mounted at top.
  for key in config version completion update new; do
    has="$(yq ".includes | has(\"$key\")" "$TEST_DIR/mycli/Taskfile.yaml")"
    [ "$has" = "false" ]
  done
}

@test "no-namespace mode emits per-command framework includes" {
  _write_source_taskfile
  _run_writer "mycli" "$TEST_DIR/mycli"
  [ "$status" -eq 0 ]

  for key in config version completion update new _help _log; do
    has="$(yq ".includes | has(\"$key\")" "$TEST_DIR/mycli/Taskfile.yaml")"
    [ "$has" = "true" ]
  done

  # And no aggregator include.
  has_clift="$(yq '.includes | has("clift")' "$TEST_DIR/mycli/Taskfile.yaml")"
  [ "$has_clift" = "false" ]
}

@test "Taskfile.user.yaml is a byte-for-byte copy of the source" {
  _write_source_taskfile
  _run_writer "mycli" "$TEST_DIR/mycli"
  [ "$status" -eq 0 ]

  [ -f "$TEST_DIR/mycli/Taskfile.user.yaml" ]
  run cmp "$TEST_DIR/source.yaml" "$TEST_DIR/mycli/Taskfile.user.yaml"
  [ "$status" -eq 0 ]
}

@test "bin/<name> is created and executable" {
  _write_source_taskfile
  _run_writer "mycli" "$TEST_DIR/mycli"
  [ "$status" -eq 0 ]

  [ -f "$TEST_DIR/mycli/bin/mycli" ]
  [ -x "$TEST_DIR/mycli/bin/mycli" ]

  # Placeholders were substituted, not left raw.
  run grep -F '%%CLI_NAME%%' "$TEST_DIR/mycli/bin/mycli"
  [ "$status" -ne 0 ]
  # CLI_DIR is no longer baked: bin/<name> self-locates from $0 so a
  # `mv` of the whole CLI dir keeps working without re-rendering. The
  # absolute path under $TEST_DIR/mycli must not appear.
  run grep -F "$TEST_DIR/mycli" "$TEST_DIR/mycli/bin/mycli"
  [ "$status" -ne 0 ]
  run grep -F 'BASH_SOURCE' "$TEST_DIR/mycli/bin/mycli"
  [ "$status" -eq 0 ]
}

@test ".env has CLI_NAME, CLI_VERSION, CLI_DIR" {
  _write_source_taskfile
  _run_writer "mycli" "$TEST_DIR/mycli"
  [ "$status" -eq 0 ]

  [ -f "$TEST_DIR/mycli/.env" ]
  run grep -E '^CLI_NAME=mycli$' "$TEST_DIR/mycli/.env"
  [ "$status" -eq 0 ]
  run grep -E '^CLI_VERSION=0\.1\.0$' "$TEST_DIR/mycli/.env"
  [ "$status" -eq 0 ]
  run grep -E "^CLI_DIR=${TEST_DIR}/mycli$" "$TEST_DIR/mycli/.env"
  [ "$status" -eq 0 ]
}

@test "re-running on the same dest succeeds (idempotent)" {
  _write_source_taskfile
  _run_writer "mycli" "$TEST_DIR/mycli"
  [ "$status" -eq 0 ]

  # Drop a sentinel inside the dest dir to confirm we don't wipe non-emitted
  # files (idempotency is per-emitted-file, not nuke-and-pave).
  mkdir -p "$TEST_DIR/mycli/cmds/extra"
  touch "$TEST_DIR/mycli/cmds/extra/marker"

  _run_writer "mycli" "$TEST_DIR/mycli"
  [ "$status" -eq 0 ]

  # All emitted files re-rendered correctly.
  [ -f "$TEST_DIR/mycli/.clift.yaml" ]
  [ -f "$TEST_DIR/mycli/.env" ]
  [ -f "$TEST_DIR/mycli/Taskfile.yaml" ]
  [ -f "$TEST_DIR/mycli/Taskfile.user.yaml" ]
  [ -x "$TEST_DIR/mycli/bin/mycli" ]

  # Sentinel scratch file untouched.
  [ -f "$TEST_DIR/mycli/cmds/extra/marker" ]
}

@test "user-includes sentinel is present and stable" {
  _write_source_taskfile
  _run_writer "mycli" "$TEST_DIR/mycli"
  [ "$status" -eq 0 ]

  # Tier 4I depends on this exact line existing inside the includes block.
  run grep -F '# __USER_INCLUDES__' "$TEST_DIR/mycli/Taskfile.yaml"
  [ "$status" -eq 0 ]

  # And a human-readable header above it.
  run grep -F '# User commands' "$TEST_DIR/mycli/Taskfile.yaml"
  [ "$status" -eq 0 ]
}

@test "framework_namespace mode also keeps the user-includes sentinel" {
  _write_source_taskfile
  _run_writer "mycli" "$TEST_DIR/mycli" "clift"
  [ "$status" -eq 0 ]

  run grep -F '# __USER_INCLUDES__' "$TEST_DIR/mycli/Taskfile.yaml"
  [ "$status" -eq 0 ]
}

@test "missing source taskfile errors clearly" {
  run bash "$_ROOT_WRITER_SH" "mycli" "$TEST_DIR/mycli" "$TEST_DIR/does-not-exist.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"source taskfile not found"* ]]
}

@test "missing args errors with usage" {
  run bash "$_ROOT_WRITER_SH" "mycli" "$TEST_DIR/mycli"
  [ "$status" -ne 0 ]
  [[ "$output" == *"requires"* ]]
}
