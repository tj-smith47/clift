#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load test_helper

setup() { common_setup; }
teardown() { common_teardown; }

# -----------------------------------------------------------------------------
# Passthrough verification for native go-task task fields.
# clift does not strip or rewrite `deps:` (or any other go-task field) during
# compile — this test locks that behaviour by wiring a `deps:` prereq in front
# of a clift-routed `cmd:` and asserting both ran, in order.
# -----------------------------------------------------------------------------

@test "task deps fire before clift-routed cmd" {
  create_test_cli "build"

  # Replace the generated Taskfile with one that wires a deps task before
  # clift's router dispatch. The prereq task prints PREPPED; the user script
  # prints BUILT. Both must appear.
  cat > "$CLI_DIR/cmds/build/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS: []
tasks:
  _prep:
    cmd: echo "PREPPED"
  default:
    deps: [_prep]
    vars:
      FLAGS: []
    cmd: "CLI_ARGS='{{.CLI_ARGS}}' '{{.FRAMEWORK_DIR}}/lib/router/router.sh' '{{.TASK}}'"
YAML

  cat > "$CLI_DIR/cmds/build/build.sh" <<'SH'
#!/usr/bin/env bash
echo "BUILT"
SH
  chmod +x "$CLI_DIR/cmds/build/build.sh"

  build_test_wrapper

  run "$CLI_DIR/bin/$CLI_NAME" build
  [ "$status" -eq 0 ]
  [[ "$output" == *"PREPPED"* ]]
  [[ "$output" == *"BUILT"* ]]

  # Order check — deps should fire first.
  prep_idx=$(printf '%s\n' "$output" | grep -n "PREPPED" | head -1 | cut -d: -f1)
  built_idx=$(printf '%s\n' "$output" | grep -n "BUILT" | head -1 | cut -d: -f1)
  [ "$prep_idx" -lt "$built_idx" ]
}
