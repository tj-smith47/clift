#!/usr/bin/env bats
# Tier 5L — end-to-end matrix for `init_from.sh`.
#
# Each test scaffolds a fixture Taskfile under $TEST_DIR, runs the
# orchestrator directly (bypassing `task init:from -- <dir>` to avoid
# wrapper-of-wrapper noise), and exercises the resulting CLI's bin/<name>.
#
# Coverage maps to the plan's Tier 5L row:
#   1. Flat passthrough Taskfile          → mycli foo
#   2. Parsed-flag (requires.vars + vars) → mycli deploy --env=staging
#   3. Internal task excluded             → cmds/ omits internal tasks
#   4. Wildcard task                      → mycli deploy <target>
#   5. Namespace :default + :sub          → mycli ns / mycli ns sub
#   6. Dashed task names                  → mycli build-dev / run.tests
#   7. Reserved-name collision (3 paths)  → --rename / --prefix / --fwns
#   8. Aliases preserved                  → mycli b / mycli bld
#   9. framework_namespace=clift          → mycli clift:version + --help
#  10. Path portability                   → wrapper script reads $CLI_DIR
#  11. Argument forwarding                → mycli foo bar baz → "bar baz"
#  12. --from -                           → cat fixture | bash init_from.sh - --from -
#  13. --from <directory>                 → looks for Taskfile.yaml inside
#
# Filesystem isolation: HOME is redirected by common_setup; every fixture
# lives under $TEST_DIR. No real $HOME / /tmp pollution.

bats_require_minimum_version 1.5.0

load test_helper

_INIT_FROM_SH="${BATS_TEST_DIRNAME}/../lib/setup/init_from.sh"

# _run_init_from <dest> <args...> — invoke the orchestrator with $dest
# guaranteed-fresh. Mirrors the helper in setup_init_from.bats so failure
# output is consistent across the two suites.
_run_init_from() {
  local dest="$1"
  shift
  rm -rf "$dest"
  run bash "$_INIT_FROM_SH" "$dest" "$@"
}

# --- 1. Flat passthrough Taskfile --------------------------------------

@test "flat passthrough: 3 tasks; mycli <task> dispatches each" {
  cat > "$TEST_DIR/source.yaml" <<'YAML'
version: '3'
tasks:
  foo:
    cmd: echo "foo ran"
  bar:
    cmd: echo "bar ran"
  baz:
    cmd: echo "baz ran"
YAML
  _run_init_from "$TEST_DIR/mycli" --from "$TEST_DIR/source.yaml"
  [ "$status" -eq 0 ]
  [ -x "$TEST_DIR/mycli/bin/mycli" ]

  run -0 "$TEST_DIR/mycli/bin/mycli" foo
  [[ "$output" == *"foo ran"* ]]

  run -0 "$TEST_DIR/mycli/bin/mycli" bar
  [[ "$output" == *"bar ran"* ]]

  run -0 "$TEST_DIR/mycli/bin/mycli" baz
  [[ "$output" == *"baz ran"* ]]
}

# --- 2. Parsed-flag Taskfile -------------------------------------------

@test "parsed-flag: requires.vars enforces presence; --env=staging passes" {
  cat > "$TEST_DIR/source.yaml" <<'YAML'
version: '3'
tasks:
  deploy:
    requires:
      vars: [ENV]
    vars: {DRY_RUN: false}
    cmd: 'echo "deploy env={{.ENV}} dry={{.DRY_RUN}}"'
YAML
  _run_init_from "$TEST_DIR/mycli" --from "$TEST_DIR/source.yaml"
  [ "$status" -eq 0 ]

  # Required flag missing → router rejects with required-flag error.
  run "$TEST_DIR/mycli/bin/mycli" deploy
  [ "$status" -ne 0 ]
  [[ "$output" == *"required"* ]] || [[ "$output" == *"--env"* ]]

  # Required flag provided → forwards to go-task as ENV=staging.
  run -0 "$TEST_DIR/mycli/bin/mycli" deploy --env=staging
  [[ "$output" == *"env=staging"* ]]

  # Optional bool absent → go-task source default applies (dry=false).
  # Note: with `--dry-run` flag, go-task's task-level vars: defaults are
  # NOT overridable from the CLI (see lib/setup/var_inference.sh header) —
  # this test only asserts the source default fires when the flag is
  # absent, which is the case the framework can guarantee.
  run -0 "$TEST_DIR/mycli/bin/mycli" deploy --env=staging
  [[ "$output" == *"dry=false"* ]]
}

# --- 3. Internal task excluded -----------------------------------------

@test "internal: true excluded from cmds/ and from --help" {
  cat > "$TEST_DIR/source.yaml" <<'YAML'
version: '3'
tasks:
  visible:
    desc: Visible task
    cmd: echo visible
  hidden:
    internal: true
    desc: Should not appear
    cmd: echo hidden
YAML
  _run_init_from "$TEST_DIR/mycli" --from "$TEST_DIR/source.yaml"
  [ "$status" -eq 0 ]

  # cmds/ shape — visible has a dir, hidden does not.
  [ -d "$TEST_DIR/mycli/cmds/visible" ]
  [ ! -d "$TEST_DIR/mycli/cmds/hidden" ]

  # Generated includes — `visible:` is mounted, `hidden:` is not.
  has_visible="$(yq '.includes | has("visible")' "$TEST_DIR/mycli/Taskfile.yaml")"
  [ "$has_visible" = "true" ]
  has_hidden="$(yq '.includes | has("hidden")' "$TEST_DIR/mycli/Taskfile.yaml")"
  [ "$has_hidden" = "false" ]
}

# --- 4. Wildcard task --------------------------------------------------

@test "wildcard task: mycli deploy <target> dispatches deploy:<target>" {
  # tier 1A's reader strips wildcard segments from the clift-side name
  # (`deploy:*` → `name=deploy`) so the wrapper writer derives
  # `cmds/deploy/deploy.sh` — exactly the path the router's passthrough
  # dispatch looks for. The wrapper body still substitutes CLIFT_POS_1
  # into the original task's wildcard slot for the go-task call.
  cat > "$TEST_DIR/source.yaml" <<'YAML'
version: '3'
tasks:
  deploy:*:
    cmd: 'echo "deploy to {{index .MATCH 0}}"'
YAML
  _run_init_from "$TEST_DIR/mycli" --from "$TEST_DIR/source.yaml"
  [ "$status" -eq 0 ]

  # Missing positional → wrapper's :? guard fires.
  run "$TEST_DIR/mycli/bin/mycli" deploy
  [ "$status" -ne 0 ]

  run -0 "$TEST_DIR/mycli/bin/mycli" deploy prod
  [[ "$output" == *"deploy to prod"* ]]
}

# --- 5. Namespace :default + :sub --------------------------------------

@test "namespace :default + :sub: mycli ns runs default, mycli ns sub runs sub" {
  # init_from.sh groups tasks by top-level segment and writes ONE
  # cmds/<top>/Taskfile.yaml per top with one block per task (default
  # for the bare/`:default`, named blocks for sub-segments). The router
  # resolves `mycli lint eslint` → task `lint:eslint` → script
  # `cmds/lint/lint.eslint.sh` (per-task wrapper) directly, falling
  # back to `lint.sh` for the bare-top task — no dispatcher shim.
  cat > "$TEST_DIR/source.yaml" <<'YAML'
version: '3'
tasks:
  lint:default:
    cmd: 'echo "default-lint"'
  lint:eslint:
    cmd: 'echo "eslint"'
YAML
  _run_init_from "$TEST_DIR/mycli" --from "$TEST_DIR/source.yaml"
  [ "$status" -eq 0 ]

  # Layout: per-task wrapper for the sub, bare-top wrapper for default.
  # No dispatcher shim, no `<top>.default.sh` indirection.
  [ -f "$TEST_DIR/mycli/cmds/lint/lint.sh" ]
  [ -f "$TEST_DIR/mycli/cmds/lint/lint.eslint.sh" ]
  [ ! -f "$TEST_DIR/mycli/cmds/lint/lint.default.sh" ]
  run grep -q "Dispatcher for a namespace group" "$TEST_DIR/mycli/cmds/lint/lint.sh"
  [ "$status" -ne 0 ]

  run -0 "$TEST_DIR/mycli/bin/mycli" lint
  [[ "$output" == *"default-lint"* ]]

  run -0 "$TEST_DIR/mycli/bin/mycli" lint eslint
  [[ "$output" == *"eslint"* ]]
}

# --- 6. Dashed task names ----------------------------------------------

@test "dashed names: build-dev and run.tests both import and run" {
  cat > "$TEST_DIR/source.yaml" <<'YAML'
version: '3'
tasks:
  build-dev:
    cmd: 'echo "build-dev ran"'
  run.tests:
    cmd: 'echo "run.tests ran"'
YAML
  _run_init_from "$TEST_DIR/mycli" --from "$TEST_DIR/source.yaml"
  [ "$status" -eq 0 ]

  [ -d "$TEST_DIR/mycli/cmds/build-dev" ]
  [ -d "$TEST_DIR/mycli/cmds/run.tests" ]

  run -0 "$TEST_DIR/mycli/bin/mycli" build-dev
  [[ "$output" == *"build-dev ran"* ]]

  run -0 "$TEST_DIR/mycli/bin/mycli" run.tests
  [[ "$output" == *"run.tests ran"* ]]
}

# --- 7a. Reserved-name collision: --rename ------------------------------

@test "reserved-name collision: --rename version=ver produces working mycli ver" {
  cat > "$TEST_DIR/source.yaml" <<'YAML'
version: '3'
tasks:
  version:
    cmd: 'echo "user version task"'
YAML
  _run_init_from "$TEST_DIR/mycli" --from "$TEST_DIR/source.yaml" \
    --rename "version=ver"
  [ "$status" -eq 0 ]

  [ -d "$TEST_DIR/mycli/cmds/ver" ]
  [ ! -d "$TEST_DIR/mycli/cmds/version" ]

  run -0 "$TEST_DIR/mycli/bin/mycli" ver
  [[ "$output" == *"user version task"* ]]
}

# --- 7b. Reserved-name collision: --prefix ------------------------------

@test "reserved-name collision: --prefix user- produces working mycli user-version" {
  cat > "$TEST_DIR/source.yaml" <<'YAML'
version: '3'
tasks:
  version:
    cmd: 'echo "user version task"'
YAML
  _run_init_from "$TEST_DIR/mycli" --from "$TEST_DIR/source.yaml" \
    --prefix "user-"
  [ "$status" -eq 0 ]

  [ -d "$TEST_DIR/mycli/cmds/user-version" ]
  [ ! -d "$TEST_DIR/mycli/cmds/version" ]

  run -0 "$TEST_DIR/mycli/bin/mycli" user-version
  [[ "$output" == *"user version task"* ]]
}

# --- 7c. Reserved-name collision: --framework-namespace -----------------

@test "reserved-name collision: --framework-namespace=clift moves built-ins; mycli version runs user task" {
  cat > "$TEST_DIR/source.yaml" <<'YAML'
version: '3'
tasks:
  version:
    cmd: 'echo "user version task"'
YAML
  _run_init_from "$TEST_DIR/mycli" --from "$TEST_DIR/source.yaml" \
    --framework-namespace=clift
  [ "$status" -eq 0 ]

  [ -d "$TEST_DIR/mycli/cmds/version" ]

  # User's `version` task runs at the top level — no collision since the
  # framework's built-in `version` is now under `clift:version`.
  run -0 "$TEST_DIR/mycli/bin/mycli" version
  [[ "$output" == *"user version task"* ]]
}

# --- 8. Aliases preserved ----------------------------------------------

@test "aliases: [b, bld] both invoke build" {
  cat > "$TEST_DIR/source.yaml" <<'YAML'
version: '3'
tasks:
  build:
    aliases: [b, bld]
    cmd: 'echo "build ran"'
YAML
  _run_init_from "$TEST_DIR/mycli" --from "$TEST_DIR/source.yaml"
  [ "$status" -eq 0 ]

  run -0 "$TEST_DIR/mycli/bin/mycli" build
  [[ "$output" == *"build ran"* ]]

  run -0 "$TEST_DIR/mycli/bin/mycli" b
  [[ "$output" == *"build ran"* ]]

  run -0 "$TEST_DIR/mycli/bin/mycli" bld
  [[ "$output" == *"build ran"* ]]
}

# --- 9. framework_namespace=clift mode ----------------------------------

@test "framework_namespace=clift: clift: aggregator mounted at root Taskfile" {
  # root_writer.sh emits the `<fwns>:` aggregator AND keeps `_help:` and
  # `_log:` mounted at the top level (privileged framework internals,
  # underscore-prefixed so they cannot collide with user task names).
  # The wrapper's `--help` short-circuit then resolves `_help:list`
  # without falling back to go-task's `--list`.
  cat > "$TEST_DIR/source.yaml" <<'YAML'
version: '3'
tasks:
  greet:
    cmd: 'echo "hello"'
YAML
  _run_init_from "$TEST_DIR/mycli" --from "$TEST_DIR/source.yaml" \
    --framework-namespace=clift
  [ "$status" -eq 0 ]

  # .clift.yaml records the namespace.
  fwns="$(yq '.framework_namespace' "$TEST_DIR/mycli/.clift.yaml")"
  [ "$fwns" = "clift" ]

  # Root Taskfile mounts the aggregator under `clift:`.
  has_clift="$(yq '.includes | has("clift")' "$TEST_DIR/mycli/Taskfile.yaml")"
  [ "$has_clift" = "true" ]

  # `_help` and `_log` survive at the top level — required by the
  # wrapper's --help short-circuit and by themed logging.
  has_help="$(yq '.includes | has("_help")' "$TEST_DIR/mycli/Taskfile.yaml")"
  [ "$has_help" = "true" ]
  has_log="$(yq '.includes | has("_log")' "$TEST_DIR/mycli/Taskfile.yaml")"
  [ "$has_log" = "true" ]

  # User's command works at the top level (no framework collision).
  run -0 "$TEST_DIR/mycli/bin/mycli" greet
  [[ "$output" == *"hello"* ]]

  # `mycli --help` resolves cleanly under framework_namespace mode (the
  # bug-3 follow-up): the wrapper short-circuits to `_help:list`, which
  # is mounted because `_help` stayed top-level. Status 0 is the strong
  # signal that the include chain works end-to-end.
  run "$TEST_DIR/mycli/bin/mycli" --help
  [ "$status" -eq 0 ]
}

# --- 10. Path portability ----------------------------------------------

@test "path portability: cmds/ wrappers resolve via \$CLI_DIR (not absolute paths)" {
  # The portability claim is end-to-end: per-task wrappers reference the
  # source via ${CLI_DIR}/Taskfile.user.yaml, and bin/<name> self-locates
  # CLI_DIR from its own script path. So a renamed CLI directory keeps
  # working without re-rendering anything.
  cat > "$TEST_DIR/source.yaml" <<'YAML'
version: '3'
tasks:
  build:
    cmd: 'echo "build ran"'
YAML
  _run_init_from "$TEST_DIR/mycli" --from "$TEST_DIR/source.yaml"
  [ "$status" -eq 0 ]

  # Move the dir to a new location.
  mv "$TEST_DIR/mycli" "$TEST_DIR/elsewhere"

  # No hardcoded path to the original /mycli/ should appear in cmds/.
  run grep -F "$TEST_DIR/mycli/" "$TEST_DIR/elsewhere/cmds/build/build.sh"
  [ "$status" -ne 0 ]
  run grep -F '${CLI_DIR}/Taskfile.user.yaml' "$TEST_DIR/elsewhere/cmds/build/build.sh"
  [ "$status" -eq 0 ]

  # bin/<name> must not bake the original CLI_DIR — it self-locates.
  run grep -F "$TEST_DIR/mycli" "$TEST_DIR/elsewhere/bin/mycli"
  [ "$status" -ne 0 ]

  # End-to-end at the new location, with no CLI_DIR override.
  run -0 "$TEST_DIR/elsewhere/bin/mycli" build
  [[ "$output" == *"build ran"* ]]
}

# --- 11. Argument forwarding -------------------------------------------

@test "argument forwarding: mycli echo a b c → CLI_ARGS gets 'a b c'" {
  # go-task delivers user-provided positionals after `--` as
  # {{.CLI_ARGS}} — a single space-separated string with shell quoting
  # applied per token. Two-arg passthrough produces "a b" inside the
  # template; three args produce "a b c"; quoted spaces survive as
  # 'with spaces'. We assert the simple/common case here.
  cat > "$TEST_DIR/source.yaml" <<'YAML'
version: '3'
tasks:
  echo:
    cmd: 'echo "args=[{{.CLI_ARGS}}]"'
YAML
  _run_init_from "$TEST_DIR/mycli" --from "$TEST_DIR/source.yaml"
  [ "$status" -eq 0 ]

  run -0 "$TEST_DIR/mycli/bin/mycli" echo foo bar baz
  [[ "$output" == *"args=[foo bar baz]"* ]]
}

# --- 12. --from - reads stdin -----------------------------------------

@test "--from -: cat fixture | bash init_from.sh dest --from - works" {
  cat > "$TEST_DIR/source.yaml" <<'YAML'
version: '3'
tasks:
  hello:
    cmd: 'echo "hello world"'
YAML
  rm -rf "$TEST_DIR/mycli"
  run bash -c "cat '$TEST_DIR/source.yaml' | bash '$_INIT_FROM_SH' '$TEST_DIR/mycli' --from -"
  [ "$status" -eq 0 ]

  # Generated CLI runs the imported task.
  run -0 "$TEST_DIR/mycli/bin/mycli" hello
  [[ "$output" == *"hello world"* ]]
}

# --- 13. --from <directory> --------------------------------------------

@test "--from <directory>: resolves Taskfile.yaml inside the dir" {
  mkdir -p "$TEST_DIR/srcdir"
  cat > "$TEST_DIR/srcdir/Taskfile.yaml" <<'YAML'
version: '3'
tasks:
  greet:
    cmd: 'echo "greet ran"'
YAML
  _run_init_from "$TEST_DIR/mycli" --from "$TEST_DIR/srcdir"
  [ "$status" -eq 0 ]

  run -0 "$TEST_DIR/mycli/bin/mycli" greet
  [[ "$output" == *"greet ran"* ]]
}
