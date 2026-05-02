#!/usr/bin/env bats
# Tier 4I — `lib/setup/init_from.sh` end-to-end orchestration.
#
# Verifies that the orchestrator wires read_source → rename overlay →
# root_writer → wrapper_writer → user-include splice into a coherent
# CLI directory shape. Collision behaviour is covered separately in
# tests/setup_init_from_collision.bats.
#
# Filesystem isolation: HOME is redirected by common_setup; every
# fixture is written under $TEST_DIR.

bats_require_minimum_version 1.5.0

load test_helper

_INIT_FROM_SH="${BATS_TEST_DIRNAME}/../lib/setup/init_from.sh"

# _write_basic_source — two-task fixture covering passthrough + parsed-flag
# branches. Avoids `vars: {K: V}` boolean values because the framework
# validator (lib/flags/validate.sh rule 6) rejects bool flags carrying a
# default — see tier 1B/2D follow-up; orchestration here works around it.
_write_basic_source() {
  cat > "$TEST_DIR/source.yaml" <<'YAML'
version: '3'
tasks:
  build:
    desc: Build the project
    cmd: echo build
  deploy:
    desc: Deploy to environment
    requires:
      vars: [ENV]
    cmd: 'echo "deploying to {{.ENV}}"'
YAML
}

# Convenience runner — guarantees the dest dir is fresh per case.
_run_init_from() {
  local dest="$1"
  shift
  rm -rf "$dest"
  run bash "$_INIT_FROM_SH" "$dest" "$@"
}

# --- Happy path ---------------------------------------------------------

@test "happy path: writes .clift.yaml, .env, bin/<name>, Taskfile*.yaml" {
  _write_basic_source
  _run_init_from "$TEST_DIR/mycli" --from "$TEST_DIR/source.yaml"
  [ "$status" -eq 0 ]

  [ -f "$TEST_DIR/mycli/.clift.yaml" ]
  [ -f "$TEST_DIR/mycli/.env" ]
  [ -f "$TEST_DIR/mycli/Taskfile.yaml" ]
  [ -f "$TEST_DIR/mycli/Taskfile.user.yaml" ]
  [ -x "$TEST_DIR/mycli/bin/mycli" ]
}

@test "happy path: Taskfile.user.yaml is byte-for-byte copy of source" {
  _write_basic_source
  _run_init_from "$TEST_DIR/mycli" --from "$TEST_DIR/source.yaml"
  [ "$status" -eq 0 ]

  run cmp "$TEST_DIR/source.yaml" "$TEST_DIR/mycli/Taskfile.user.yaml"
  [ "$status" -eq 0 ]
}

@test "happy path: per-task cmds/<top>/Taskfile.yaml + <task>.sh exist" {
  _write_basic_source
  _run_init_from "$TEST_DIR/mycli" --from "$TEST_DIR/source.yaml"
  [ "$status" -eq 0 ]

  [ -f "$TEST_DIR/mycli/cmds/build/Taskfile.yaml" ]
  [ -x "$TEST_DIR/mycli/cmds/build/build.sh" ]
  [ -f "$TEST_DIR/mycli/cmds/deploy/Taskfile.yaml" ]
  [ -x "$TEST_DIR/mycli/cmds/deploy/deploy.sh" ]
}

@test "happy path: root Taskfile splices user-include rows for each top" {
  _write_basic_source
  _run_init_from "$TEST_DIR/mycli" --from "$TEST_DIR/source.yaml"
  [ "$status" -eq 0 ]

  # Sentinel must be gone.
  run grep -F '__USER_INCLUDES__' "$TEST_DIR/mycli/Taskfile.yaml"
  [ "$status" -ne 0 ]

  # Each top-level command shows up under includes.
  has_build="$(yq '.includes | has("build")' "$TEST_DIR/mycli/Taskfile.yaml")"
  [ "$has_build" = "true" ]
  has_deploy="$(yq '.includes | has("deploy")' "$TEST_DIR/mycli/Taskfile.yaml")"
  [ "$has_deploy" = "true" ]

  # Path is the conventional ./cmds/<top> form.
  build_path="$(yq '.includes.build.taskfile' "$TEST_DIR/mycli/Taskfile.yaml")"
  [ "$build_path" = "./cmds/build" ]
}

@test "happy path: success summary reports each command on stderr+stdout" {
  _write_basic_source
  _run_init_from "$TEST_DIR/mycli" --from "$TEST_DIR/source.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Created"* ]]
  [[ "$output" == *"build"* ]]
  [[ "$output" == *"deploy"* ]]
}

# --- Wildcards ----------------------------------------------------------

@test "wildcard task: produces wrapper that takes positional \$1" {
  cat > "$TEST_DIR/source.yaml" <<'YAML'
version: '3'
tasks:
  deploy:*:
    desc: Deploy to target
    cmd: 'echo "deploy to {{index .MATCH 0}}"'
YAML
  _run_init_from "$TEST_DIR/mycli" --from "$TEST_DIR/source.yaml"
  [ "$status" -eq 0 ]

  # tier 1A's reader strips the wildcard segment from the clift-side
  # `name`, so `deploy:*` lands at cmds/deploy/deploy.sh — exactly the
  # path the router's passthrough lookup probes.
  [ -f "$TEST_DIR/mycli/cmds/deploy/deploy.sh" ]

  # Wildcard tasks are router-passthrough — argv arrives as $1, not
  # CLIFT_POS_*. The wrapper reads $1 into the wildcard slot via :?
  # so a missing target produces a clear usage error.
  grep -qF '"${1:?Usage: deploy <TARGET>}"' "$TEST_DIR/mycli/cmds/deploy/deploy.sh"
}

# --- Internal task exclusion -------------------------------------------

@test "internal: true tasks do not appear in cmds/" {
  cat > "$TEST_DIR/source.yaml" <<'YAML'
version: '3'
tasks:
  visible:
    desc: Visible task
    cmd: echo visible
  hidden:
    internal: true
    desc: Should not be imported
    cmd: echo hidden
YAML
  _run_init_from "$TEST_DIR/mycli" --from "$TEST_DIR/source.yaml"
  [ "$status" -eq 0 ]

  [ -d "$TEST_DIR/mycli/cmds/visible" ]
  [ ! -d "$TEST_DIR/mycli/cmds/hidden" ]

  # And no `hidden:` include row was added.
  has_hidden="$(yq '.includes | has("hidden")' "$TEST_DIR/mycli/Taskfile.yaml")"
  [ "$has_hidden" = "false" ]
}

# --- Aliases preserved --------------------------------------------------

@test "aliases: [b, bld] preserved in generated cmds/build/Taskfile.yaml" {
  cat > "$TEST_DIR/source.yaml" <<'YAML'
version: '3'
tasks:
  build:
    desc: Build
    aliases: [b, bld]
    cmd: echo build
YAML
  _run_init_from "$TEST_DIR/mycli" --from "$TEST_DIR/source.yaml"
  [ "$status" -eq 0 ]

  aliases_json="$(yq -o=json '.tasks.default.aliases' "$TEST_DIR/mycli/cmds/build/Taskfile.yaml")"
  [[ "$aliases_json" == *'"b"'* ]]
  [[ "$aliases_json" == *'"bld"'* ]]
}

# --- Renamed names override --------------------------------------------

@test "--rename SRC=DST renames the clift name but keeps go-task dispatch" {
  cat > "$TEST_DIR/source.yaml" <<'YAML'
version: '3'
tasks:
  config:
    desc: User config tooling
    cmd: 'echo "user config tool"'
YAML
  # Use --rename to dodge the framework reserved-name collision and rename
  # the user task `config` → `cfg` on the clift side.
  _run_init_from "$TEST_DIR/mycli" --from "$TEST_DIR/source.yaml" \
    --rename "config=cfg"
  [ "$status" -eq 0 ]

  # cmds dir uses the renamed top.
  [ -d "$TEST_DIR/mycli/cmds/cfg" ]
  [ -x "$TEST_DIR/mycli/cmds/cfg/cfg.sh" ]
  [ ! -d "$TEST_DIR/mycli/cmds/config" ]

  # Wrapper still dispatches to the original go-task `config` identifier.
  run grep -F "Wraps go-task task: config" "$TEST_DIR/mycli/cmds/cfg/cfg.sh"
  [ "$status" -eq 0 ]
  run grep -E "exec task .* config\$|exec task .* config -- " "$TEST_DIR/mycli/cmds/cfg/cfg.sh"
  [ "$status" -eq 0 ]

  # Root Taskfile mounts `cfg`, not `config` (well, it also has the
  # framework's `config` row — but no user `config` row).
  has_user_cfg="$(yq '.includes | has("cfg")' "$TEST_DIR/mycli/Taskfile.yaml")"
  [ "$has_user_cfg" = "true" ]
}

# --- Prefix applied -----------------------------------------------------

@test "--prefix STR prepends STR to every command name" {
  _write_basic_source
  _run_init_from "$TEST_DIR/mycli" --from "$TEST_DIR/source.yaml" \
    --prefix "team-"
  [ "$status" -eq 0 ]

  [ -d "$TEST_DIR/mycli/cmds/team-build" ]
  [ -d "$TEST_DIR/mycli/cmds/team-deploy" ]
  [ ! -d "$TEST_DIR/mycli/cmds/build" ]

  has_team_build="$(yq '.includes | has("team-build")' "$TEST_DIR/mycli/Taskfile.yaml")"
  [ "$has_team_build" = "true" ]
}

# --- Optional: stdin source --------------------------------------------

@test "--from - reads source from stdin" {
  _write_basic_source
  rm -rf "$TEST_DIR/mycli"
  run bash -c "cat '$TEST_DIR/source.yaml' | bash '$_INIT_FROM_SH' '$TEST_DIR/mycli' --from -"
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/mycli/Taskfile.user.yaml" ]
  [ -d "$TEST_DIR/mycli/cmds/build" ]
}

# --- Optional: directory source (looks for Taskfile.yaml inside) -------

@test "--from <directory> finds Taskfile.yaml inside" {
  mkdir -p "$TEST_DIR/srcdir"
  cat > "$TEST_DIR/srcdir/Taskfile.yaml" <<'YAML'
version: '3'
tasks:
  greet:
    desc: Say hi
    cmd: echo hi
YAML
  _run_init_from "$TEST_DIR/mycli" --from "$TEST_DIR/srcdir"
  [ "$status" -eq 0 ]
  [ -d "$TEST_DIR/mycli/cmds/greet" ]
}

# --- Wildcard vs plain conflict ----------------------------------------

@test "wildcard shadowed by plain task: wildcard silently dropped, note on stderr" {
  # When a source declares both `deploy` (plain) and `deploy:*` (wildcard),
  # both normalize to clift name `deploy`. clift's command tree has one
  # slot per name, so only the plain task is importable. Mirrors go-task's
  # own literal-takes-precedence rule. Emits a `note:` on stderr; the
  # generated CLI is still functional.
  cat > "$TEST_DIR/source.yaml" <<'YAML'
version: '3'
tasks:
  deploy:
    desc: Deploy
    requires: {vars: [ENV]}
    cmd: 'echo "deploy env={{.ENV}}"'
  deploy:*:
    desc: Wildcard deploy
    cmd: 'echo "deploy:* match={{index .MATCH 0}}"'
YAML
  _run_init_from "$TEST_DIR/mycli" --from "$TEST_DIR/source.yaml"
  [ "$status" -eq 0 ]

  # The plain `deploy` survived and is parsed-flag (requires --env).
  [ -d "$TEST_DIR/mycli/cmds/deploy" ]

  # Only one wrapper exists — the wildcard's wrapper was never written.
  count="$(find "$TEST_DIR/mycli/cmds/deploy" -name "*.sh" -type f | wc -l)"
  [ "$count" -eq 1 ]

  # Stderr surfaced the drop note.
  [[ "$output" == *"dropping wildcard"* ]] || [[ "$output" == *"shadowed"* ]]

  # `mycli deploy --env staging` still works (plain task is functional).
  run -0 "$TEST_DIR/mycli/bin/mycli" deploy --env=staging
  [[ "$output" == *"deploy env=staging"* ]]
}

# --- Missing-flag errors -----------------------------------------------

@test "missing --from PATH errors with usage" {
  run bash "$_INIT_FROM_SH" "$TEST_DIR/mycli"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing --from"* ]] || [[ "$output" == *"Usage:"* ]]
}

@test "missing <dir> errors" {
  run bash "$_INIT_FROM_SH" --from "$TEST_DIR/source.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing <dir>"* ]] || [[ "$output" == *"Usage:"* ]]
}

@test "nonexistent --from PATH exits 3" {
  run bash "$_INIT_FROM_SH" "$TEST_DIR/mycli" --from "$TEST_DIR/no-such-file.yaml"
  [ "$status" -eq 3 ]
}
