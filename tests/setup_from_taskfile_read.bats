#!/usr/bin/env bats
# Tier 1A — `lib/setup/from_taskfile.sh::read_source`
#
# Verifies that the source reader correctly normalizes go-task
# `--list-all --json --nested` output into a flat task list with the
# clift-side schema (see lib/setup/from_taskfile.sh header).
#
# Filesystem isolation: HOME is redirected by common_setup; every
# fixture Taskfile is written under $TEST_DIR.

bats_require_minimum_version 1.5.0

load test_helper

# read_source path under test, plus a tiny helper for the run-and-jq
# pattern repeated by every case below.
_FROM_TASKFILE_SH="${BATS_TEST_DIRNAME}/../lib/setup/from_taskfile.sh"

# _read <fixture> → captures JSON in $output (raw, single-line).
_read() {
  run bash "$_FROM_TASKFILE_SH" "$1"
}

# _jq <expr>  → run jq against the captured $output (single-line JSON).
_jq() {
  jq -r "$1" <<< "$output"
}

@test "flat Taskfile (3 top-level tasks) → 3 entries" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
tasks:
  build:
    desc: Build it
    cmd: echo build
  test:
    desc: Run tests
    cmd: echo test
  lint:
    desc: Run lints
    cmd: echo lint
YAML

  _read "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]

  count="$(_jq '.tasks | length')"
  [ "$count" -eq 3 ]

  names="$(_jq '[.tasks[].name] | sort | join(",")')"
  [ "$names" = "build,lint,test" ]

  src="$(_jq '.source')"
  [ "$src" = "$TEST_DIR/Taskfile.yaml" ]
}

@test "namespaced (lint:default, lint:eslint) → bare 'lint' and 'lint:eslint'" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
tasks:
  lint:default:
    desc: Run all lints
    cmd: echo all
  lint:eslint:
    desc: Run eslint only
    cmd: echo eslint
YAML

  _read "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]

  names="$(_jq '[.tasks[].name] | sort | join(",")')"
  [ "$names" = "lint,lint:eslint" ]

  # Original go-task name preserved verbatim in `task`.
  bare_orig="$(_jq '.tasks[] | select(.name == "lint") | .task')"
  [ "$bare_orig" = "lint:default" ]

  sub_orig="$(_jq '.tasks[] | select(.name == "lint:eslint") | .task')"
  [ "$sub_orig" = "lint:eslint" ]
}

@test "internal: true → excluded (go-task already filters; verify here)" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
tasks:
  visible:
    desc: Visible
    cmd: echo visible
  hidden:
    internal: true
    desc: Hidden
    cmd: echo hidden
YAML

  _read "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]

  count="$(_jq '.tasks | length')"
  [ "$count" -eq 1 ]

  names="$(_jq '[.tasks[].name] | join(",")')"
  [ "$names" = "visible" ]
}

@test "wildcard deploy:* → name strips wildcard segment, task preserved" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
tasks:
  "deploy:*":
    desc: Deploy to wildcard
    cmd: echo deploy
YAML

  _read "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]

  wild="$(_jq '.tasks[0].wildcard')"
  [ "$wild" = "true" ]

  # Original go-task identifier preserved for dispatch.
  task="$(_jq '.tasks[0].task')"
  [ "$task" = "deploy:*" ]

  # clift-side name has the wildcard segment removed so the wrapper
  # writer's `<name>.sh` derivation produces `deploy.sh`, which the
  # router can find via its `cmds/<top>/<top>.sh` passthrough lookup.
  name="$(_jq '.tasks[0].name')"
  [ "$name" = "deploy" ]
}

@test "wildcard build:*:release → name preserves non-wildcard segments" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
tasks:
  "build:*:release":
    desc: Build release for <TARGET>
    cmd: echo build
YAML

  _read "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]

  wild="$(_jq '.tasks[0].wildcard')"
  [ "$wild" = "true" ]

  task="$(_jq '.tasks[0].task')"
  [ "$task" = "build:*:release" ]

  # Mid-segment wildcard stripped, surrounding segments rejoined.
  name="$(_jq '.tasks[0].name')"
  [ "$name" = "build:release" ]
}

@test "aliases [b, bld] → preserved as a list" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
tasks:
  build:
    desc: Build
    aliases: [b, bld]
    cmd: echo build
YAML

  _read "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]

  count="$(_jq '.tasks[0].aliases | length')"
  [ "$count" -eq 2 ]

  joined="$(_jq '.tasks[0].aliases | sort | join(",")')"
  [ "$joined" = "b,bld" ]
}

@test "vars: {DRY_RUN: false} + requires.vars: [ENV] → present in output" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
tasks:
  deploy:
    desc: Deploy
    requires:
      vars: [ENV]
    vars:
      DRY_RUN: false
    cmd: echo deploy
YAML

  _read "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]

  vars="$(_jq '.tasks[0].vars | tojson')"
  [ "$vars" = '{"DRY_RUN":false}' ]

  reqs="$(_jq '.tasks[0].requires_vars | tojson')"
  [ "$reqs" = '["ENV"]' ]

  # vars OR requires non-empty → not passthrough.
  pt="$(_jq '.tasks[0].passthrough')"
  [ "$pt" = "false" ]
}

@test "task with no vars/requires → passthrough: true" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
tasks:
  build:
    desc: Build
    cmd: echo build
  deploy:
    desc: Deploy
    requires:
      vars: [ENV]
    cmd: echo deploy
YAML

  _read "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]

  build_pt="$(_jq '.tasks[] | select(.name == "build") | .passthrough')"
  [ "$build_pt" = "true" ]

  deploy_pt="$(_jq '.tasks[] | select(.name == "deploy") | .passthrough')"
  [ "$deploy_pt" = "false" ]
}

@test "missing source file → exit nonzero with clear stderr message" {
  run bash "$_FROM_TASKFILE_SH" "$TEST_DIR/does-not-exist.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"source not found"* ]]
}

@test "directory passed as source → exit nonzero (regular file required)" {
  mkdir -p "$TEST_DIR/some-dir"
  run bash "$_FROM_TASKFILE_SH" "$TEST_DIR/some-dir"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a regular file"* ]]
}

@test "malformed Taskfile → exit nonzero with parse error on stderr" {
  printf 'this: is: not: valid: yaml:\n  - [unbalanced\n' > "$TEST_DIR/Taskfile.yaml"
  run bash "$_FROM_TASKFILE_SH" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"failed to"* ]]
}
