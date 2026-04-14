#!/usr/bin/env bats
# Tests for `clift import` — wraps existing go-task tasks as clift commands.
bats_require_minimum_version 1.5.0

load test_helper

setup() {
  common_setup
  export FRAMEWORK_DIR
  export CLI_NAME="impcli"
  export CLI_VERSION="0.1.0"
  export CLIFT_MODE="standard"
}

teardown() {
  common_teardown
}

_init_impcli() {
  bash "$FRAMEWORK_DIR/bin/clift" init "$CLI_DIR" --mode standard >/dev/null 2>&1
}

_write_user_taskfile() {
  cat > "$CLI_DIR/Taskfile.user.yaml" <<'YAML'
version: '3'
tasks:
  build:
    desc: "Build the app"
    cmd: echo "building args={{.CLI_ARGS}}"
  test:
    desc: "Run tests"
    cmd: echo "testing"
  lint:
    desc: "Run shellcheck"
    cmd: echo "linting"
YAML
}

@test "import.sh requires CLI_DIR and FRAMEWORK_DIR" {
  run bash "$FRAMEWORK_DIR/lib/import/import.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires CLI_DIR and FRAMEWORK_DIR"* ]]
}

@test "import --from requires a path" {
  _init_impcli
  run bash "$FRAMEWORK_DIR/lib/import/import.sh" "$CLI_DIR" "$FRAMEWORK_DIR" --from
  [ "$status" -ne 0 ]
  [[ "$output" == *"--from requires a path"* ]]
}

@test "clift import runs end-to-end through the wrapper" {
  _init_impcli
  _write_user_taskfile
  run "$CLI_DIR/bin/impcli" import --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"importable task"* ]]
  [[ "$output" == *"build"* ]]
  [[ "$output" == *"no changes made"* ]]
  # --dry-run must have been honored
  [ ! -d "$CLI_DIR/cmds/build" ]
}

@test "import skips wildcard tasks" {
  _init_impcli
  cat > "$CLI_DIR/Taskfile.user.yaml" <<'YAML'
version: '3'
tasks:
  "deploy:*":
    desc: "Wildcard deploy"
    cmd: echo "deploy $CLI_ARGS"
  lint:
    desc: "Lint"
    cmd: echo lint
YAML
  run bash "$FRAMEWORK_DIR/lib/import/import.sh" "$CLI_DIR" "$FRAMEWORK_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"wildcard not supported"* ]]
  [ ! -d "$CLI_DIR/cmds/deploy" ]
  [ -d "$CLI_DIR/cmds/lint" ]
}

@test "import refuses to run outside a clift CLI" {
  mkdir -p "$TEST_DIR/plain"
  run bash "$FRAMEWORK_DIR/lib/import/import.sh" "$TEST_DIR/plain" "$FRAMEWORK_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Not a clift CLI"* ]]
  [[ "$output" == *"clift init"* ]]
}

@test "import errs when source Taskfile is missing" {
  _init_impcli
  # No Taskfile.user.yaml, root Taskfile exists, but --from points elsewhere
  run bash "$FRAMEWORK_DIR/lib/import/import.sh" "$CLI_DIR" "$FRAMEWORK_DIR" --from "$TEST_DIR/nope.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Source Taskfile not found"* ]]
}

@test "import generates cmds/<name>/ dirs and root includes for 3 tasks" {
  _init_impcli
  _write_user_taskfile
  run bash "$FRAMEWORK_DIR/lib/import/import.sh" "$CLI_DIR" "$FRAMEWORK_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Imported 3 command(s)"* ]]

  for name in build test lint; do
    [ -d "$CLI_DIR/cmds/$name" ]
    [ -x "$CLI_DIR/cmds/$name/$name.sh" ]
    [ -f "$CLI_DIR/cmds/$name/Taskfile.yaml" ]
    grep -q "^  $name:$" "$CLI_DIR/Taskfile.yaml"
    grep -q "./cmds/$name" "$CLI_DIR/Taskfile.yaml"
  done
}

@test "import is idempotent — re-running skips existing cmds" {
  _init_impcli
  _write_user_taskfile
  bash "$FRAMEWORK_DIR/lib/import/import.sh" "$CLI_DIR" "$FRAMEWORK_DIR" >/dev/null
  # Snapshot the root Taskfile
  local before
  before="$(cat "$CLI_DIR/Taskfile.yaml")"

  run bash "$FRAMEWORK_DIR/lib/import/import.sh" "$CLI_DIR" "$FRAMEWORK_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already exists in cmds/"* ]]
  [ "$(cat "$CLI_DIR/Taskfile.yaml")" = "$before" ]
}

@test "import generated wrapper invokes the wrapped task with forwarded args" {
  _init_impcli
  _write_user_taskfile
  bash "$FRAMEWORK_DIR/lib/import/import.sh" "$CLI_DIR" "$FRAMEWORK_DIR" >/dev/null

  run "$CLI_DIR/bin/impcli" build hello world
  [ "$status" -eq 0 ]
  [[ "$output" == *"building"* ]]
  # CLI_ARGS from go-task should include both positionals
  [[ "$output" == *"hello"* ]]
  [[ "$output" == *"world"* ]]
}

@test "import skips names that collide with clift framework commands" {
  _init_impcli
  cat > "$CLI_DIR/Taskfile.user.yaml" <<'YAML'
version: '3'
tasks:
  config:
    desc: "user's config task"
    cmd: echo user-config
  deploy:
    desc: "Deploy"
    cmd: echo deploy
YAML
  run bash "$FRAMEWORK_DIR/lib/import/import.sh" "$CLI_DIR" "$FRAMEWORK_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"config"* ]]
  [[ "$output" == *"collides with clift framework command"* ]]
  # config must NOT be imported — it would shadow the framework command
  [ ! -d "$CLI_DIR/cmds/config" ]
  # deploy IS imported
  [ -d "$CLI_DIR/cmds/deploy" ]
}

@test "import skips names invalid for clift (dashes, uppercase)" {
  _init_impcli
  cat > "$CLI_DIR/Taskfile.user.yaml" <<'YAML'
version: '3'
tasks:
  "My-Task":
    desc: "Bad name"
    cmd: echo bad
  good:
    desc: "Fine"
    cmd: echo good
YAML
  run bash "$FRAMEWORK_DIR/lib/import/import.sh" "$CLI_DIR" "$FRAMEWORK_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"My-Task"* ]]
  [[ "$output" == *"invalid name for clift"* ]]
  [ ! -d "$CLI_DIR/cmds/My-Task" ]
  [ -d "$CLI_DIR/cmds/good" ]
}

@test "import --dry-run prints plan and writes nothing" {
  _init_impcli
  _write_user_taskfile
  # Snapshot before
  local cmds_before
  cmds_before="$(ls "$CLI_DIR/cmds" 2>/dev/null || true)"

  run bash "$FRAMEWORK_DIR/lib/import/import.sh" "$CLI_DIR" "$FRAMEWORK_DIR" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dry run"* ]]
  [[ "$output" == *"build"* ]]
  [[ "$output" == *"no changes made"* ]]

  # No cmds/<name>/ directories were created
  [ "$(ls "$CLI_DIR/cmds" 2>/dev/null || true)" = "$cmds_before" ]
  # Root Taskfile wasn't modified
  ! grep -q "^  build:$" "$CLI_DIR/Taskfile.yaml"
}

@test "import honors --from with a custom path" {
  _init_impcli
  cat > "$TEST_DIR/custom.yaml" <<'YAML'
version: '3'
tasks:
  custom:
    desc: "Custom task"
    cmd: echo "custom={{.CLI_ARGS}}"
YAML
  run bash "$FRAMEWORK_DIR/lib/import/import.sh" "$CLI_DIR" "$FRAMEWORK_DIR" --from "$TEST_DIR/custom.yaml"
  [ "$status" -eq 0 ]
  [ -d "$CLI_DIR/cmds/custom" ]
  # Generated wrapper should reference the custom source, not Taskfile.user.yaml
  grep -q "$TEST_DIR/custom.yaml" "$CLI_DIR/cmds/custom/custom.sh"
}

@test "import refuses to wrap tasks from the clift-managed root Taskfile" {
  _init_impcli
  # Don't create Taskfile.user.yaml — import should default to root Taskfile,
  # see framework includes there, and refuse rather than recurse.
  run bash "$FRAMEWORK_DIR/lib/import/import.sh" "$CLI_DIR" "$FRAMEWORK_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"clift-managed root Taskfile"* ]]
  [[ "$output" == *"Taskfile.user.yaml"* ]]
}

@test "import rejects unknown flags" {
  _init_impcli
  _write_user_taskfile
  run bash "$FRAMEWORK_DIR/lib/import/import.sh" "$CLI_DIR" "$FRAMEWORK_DIR" --bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown flag"* ]]
}

@test "import surfaces in mycli --help after running" {
  _init_impcli
  # Even without importing, the `import` command itself should appear.
  run "$CLI_DIR/bin/impcli" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"import"* ]]
}

@test "import after manually adding a flag still forwards positionals" {
  # Simulates: user imports, then edits cmds/foo/Taskfile.yaml to declare a
  # real flag. The wrapper script is unchanged — positionals should still
  # reach the wrapped task via CLIFT_POS_*.
  _init_impcli
  cat > "$CLI_DIR/Taskfile.user.yaml" <<'YAML'
version: '3'
tasks:
  foo:
    desc: "Foo"
    cmd: echo "foo args={{.CLI_ARGS}}"
YAML
  bash "$FRAMEWORK_DIR/lib/import/import.sh" "$CLI_DIR" "$FRAMEWORK_DIR" >/dev/null

  # User adds a --loud flag manually
  cat > "$CLI_DIR/cmds/foo/Taskfile.yaml" <<YAML
version: '3'
vars:
  FLAGS:
    - {name: loud, type: bool, desc: "Be loud"}
tasks:
  default:
    desc: "Foo"
    vars:
      FLAGS:
        - {name: loud, type: bool, desc: "Be loud"}
    cmd: "CLI_ARGS='{{.CLI_ARGS}}' '{{.FRAMEWORK_DIR}}/lib/router/router.sh' '{{.TASK}}'"
YAML
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR" >/dev/null 2>&1

  run "$CLI_DIR/bin/impcli" foo --loud positional_one
  [ "$status" -eq 0 ]
  # The positional reaches the wrapped task
  [[ "$output" == *"positional_one"* ]]
}
