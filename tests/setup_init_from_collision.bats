#!/usr/bin/env bats
# Tier 4J — `lib/setup/init_from.sh` reserved-name + self-collision UX.
#
# Exercises the orchestrator's atomic abort behaviour: collision detection
# runs BEFORE any files are written, so a colliding case must leave the
# destination directory untouched. Each of the three resolution paths
# (--rename, --prefix, --framework-namespace) must clear the collision
# and produce a usable CLI dir.
#
# Filesystem isolation: HOME is redirected by common_setup; every fixture
# is written under $TEST_DIR.

bats_require_minimum_version 1.5.0

load test_helper

_INIT_FROM_SH="${BATS_TEST_DIRNAME}/../lib/setup/init_from.sh"

# _write_collision_source — a single-task Taskfile whose name collides
# with a framework reserved name. `version` is one of the canonical
# framework commands surfaced by lib/_framework_aggregate.yaml.
_write_collision_source() {
  cat > "$TEST_DIR/source.yaml" <<'YAML'
version: '3'
tasks:
  version:
    desc: Print app version (user)
    cmd: 'echo "user version"'
YAML
}

_run_init_from() {
  local dest="$1"
  shift
  rm -rf "$dest"
  run bash "$_INIT_FROM_SH" "$dest" "$@"
}

# 1. Reserved collision — error, three resolution paths, exit 1
@test "reserved-name collision (version) → exit 1 with three resolutions" {
  _write_collision_source
  _run_init_from "$TEST_DIR/mycli" --from "$TEST_DIR/source.yaml"

  [ "$status" -eq 1 ]
  [[ "$output" == *"collide with framework"* ]]
  [[ "$output" == *"version"* ]]
  [[ "$output" == *"--rename"* ]]
  [[ "$output" == *"--prefix"* ]]
  [[ "$output" == *"--framework-namespace"* ]]
  # The user-facing reference uses the dest basename so the error reads
  # naturally as `mycli version`, not the abstract `version`.
  [[ "$output" == *"mycli version"* ]] || [[ "$output" == *"\`mycli "* ]]
}

# 2. --rename clears the collision
@test "reserved-name collision resolved by --rename version=ver" {
  _write_collision_source
  _run_init_from "$TEST_DIR/mycli" --from "$TEST_DIR/source.yaml" \
    --rename "version=ver"

  [ "$status" -eq 0 ]
  [ -d "$TEST_DIR/mycli/cmds/ver" ]
  [ -x "$TEST_DIR/mycli/cmds/ver/ver.sh" ]
  # Wrapper still dispatches to the original `version` go-task name.
  run grep -F "Wraps go-task task: version" "$TEST_DIR/mycli/cmds/ver/ver.sh"
  [ "$status" -eq 0 ]
}

# 3. --prefix clears the collision
@test "reserved-name collision resolved by --prefix user-" {
  _write_collision_source
  _run_init_from "$TEST_DIR/mycli" --from "$TEST_DIR/source.yaml" \
    --prefix "user-"

  [ "$status" -eq 0 ]
  [ -d "$TEST_DIR/mycli/cmds/user-version" ]
  [ -x "$TEST_DIR/mycli/cmds/user-version/user-version.sh" ]
}

# 4. --framework-namespace clears the collision
@test "reserved-name collision resolved by --framework-namespace=clift" {
  _write_collision_source
  _run_init_from "$TEST_DIR/mycli" --from "$TEST_DIR/source.yaml" \
    --framework-namespace "clift"

  [ "$status" -eq 0 ]

  # User's `version` made it through.
  [ -d "$TEST_DIR/mycli/cmds/version" ]
  [ -x "$TEST_DIR/mycli/cmds/version/version.sh" ]

  # And the root Taskfile mounts the framework aggregator under `clift:`.
  agg="$(yq '.includes.clift.taskfile' "$TEST_DIR/mycli/Taskfile.yaml")"
  [[ "$agg" == *"_framework_aggregate.yaml" ]]

  # The user `version` row is also present under top-level includes.
  has_user_version="$(yq '.includes | has("version")' "$TEST_DIR/mycli/Taskfile.yaml")"
  [ "$has_user_version" = "true" ]

  # `framework_namespace` recorded in .clift.yaml.
  ns="$(yq '.framework_namespace' "$TEST_DIR/mycli/.clift.yaml")"
  [ "$ns" = "clift" ]
}

# 5. Self-collision (two renames produce the same final name)
@test "self-collision: --rename a=foo --rename b=foo → exit 1" {
  cat > "$TEST_DIR/source.yaml" <<'YAML'
version: '3'
tasks:
  alpha:
    desc: Alpha task
    cmd: echo alpha
  beta:
    desc: Beta task
    cmd: echo beta
YAML

  _run_init_from "$TEST_DIR/mycli" --from "$TEST_DIR/source.yaml" \
    --rename "alpha=foo" --rename "beta=foo"

  [ "$status" -eq 1 ]
  [[ "$output" == *"collide after rename"* ]] \
    || [[ "$output" == *"Each final name must be unique"* ]]
  # Source identifiers should be reported so the user can disambiguate.
  [[ "$output" == *"alpha"* ]]
  [[ "$output" == *"beta"* ]]
}

# 6. Atomic abort — colliding cases write nothing
@test "collision aborts atomically — no files written" {
  _write_collision_source
  rm -rf "$TEST_DIR/mycli"
  run bash "$_INIT_FROM_SH" "$TEST_DIR/mycli" --from "$TEST_DIR/source.yaml"
  [ "$status" -eq 1 ]

  # Dest dir must be absent OR empty — never half-populated.
  if [ -d "$TEST_DIR/mycli" ]; then
    run bash -c "ls -A '$TEST_DIR/mycli' | wc -l"
    [ "$output" = "0" ]
  fi
}

# 7. --framework-namespace=clift suppresses reserved-name detection entirely.
# Even with multiple "framework"-named user tasks, --framework-namespace
# means the framework moves out of the way so all user names land cleanly.
@test "--framework-namespace suppresses ALL reserved-name collisions" {
  cat > "$TEST_DIR/source.yaml" <<'YAML'
version: '3'
tasks:
  config:
    desc: User config
    cmd: echo cfg
  version:
    desc: User version
    cmd: echo ver
  update:
    desc: User update
    cmd: echo upd
YAML

  _run_init_from "$TEST_DIR/mycli" --from "$TEST_DIR/source.yaml" \
    --framework-namespace "clift"
  [ "$status" -eq 0 ]

  for cmd in config version update; do
    [ -d "$TEST_DIR/mycli/cmds/$cmd" ]
  done
}
