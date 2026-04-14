#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load test_helper

setup() { common_setup; }
teardown() { common_teardown; }

# -----------------------------------------------------------------------------
# Single consolidated cache file: .clift/index.json.
#
# Shape:
#   { tasks: { <name>: { flags: [...], aliases: [...], hidden: bool, summary: str } } }
#
# `.clift/flags.json` is kept as a derived view for backwards compat with
# out-of-tree consumers (its shape is the flat {task: [flag...]} map that
# pre-Task-1.3 consumers already depend on).
# -----------------------------------------------------------------------------

@test "compile emits .clift/index.json alongside flags.json" {
  create_test_cli "greet" '- {name: name, short: n, type: string, default: world}'
  run bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
  [ "$status" -eq 0 ]
  [ -f "$CLI_DIR/.clift/index.json" ]
  [ -f "$CLI_DIR/.clift/flags.json" ]
}

@test "index.json has the spec'd shape" {
  create_test_cli "greet" '- {name: name, short: n, type: string, default: world}'
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"

  # Top-level key must be "tasks"
  run jq -r '.tasks | type' "$CLI_DIR/.clift/index.json"
  [[ "$output" == "object" ]]

  # Each task entry has the four fields
  run jq -r '.tasks["greet"] | keys | sort | join(",")' "$CLI_DIR/.clift/index.json"
  [[ "$output" == *"aliases"* ]]
  [[ "$output" == *"flags"* ]]
  [[ "$output" == *"hidden"* ]]
  [[ "$output" == *"summary"* ]]
}

@test "index.json.tasks[x].flags equals flags.json[x]" {
  create_test_cli "greet" '- {name: name, short: n, type: string, default: world}'
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"

  idx_flags="$(jq -c '.tasks["greet"].flags' "$CLI_DIR/.clift/index.json")"
  view_flags="$(jq -c '.["greet"]' "$CLI_DIR/.clift/flags.json")"
  [[ "$idx_flags" == "$view_flags" ]]
}

@test "index.json captures vars.HIDDEN: true from command Taskfile" {
  create_test_cli "greet"
  # Inject HIDDEN: true into the command's top-level vars (portable: awk + mv)
  local tf="$CLI_DIR/cmds/greet/Taskfile.yaml"
  awk '/^vars:/{print; print "  HIDDEN: true"; next} {print}' "$tf" > "$tf.new"
  mv "$tf.new" "$tf"

  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
  run jq -r '.tasks["greet"].hidden' "$CLI_DIR/.clift/index.json"
  [[ "$output" == "true" ]]
}

@test "index.json hidden defaults to false when vars.HIDDEN absent" {
  create_test_cli "greet"
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
  run jq -r '.tasks["greet"].hidden' "$CLI_DIR/.clift/index.json"
  [[ "$output" == "false" ]]
}

@test "router.sh reads flag table from index.json" {
  create_test_cli "greet" '- {name: name, short: n, type: string, default: world}'
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"

  # Corrupt flags.json so any code path reading it would fail. router must
  # still be able to parse --name because it reads from index.json.
  echo 'GARBAGE' > "$CLI_DIR/.clift/flags.json"

  cat > "$CLI_DIR/cmds/greet/greet.sh" <<'SH'
#!/usr/bin/env bash
echo "NAME=${CLIFT_FLAG_NAME:-unset}"
SH
  chmod +x "$CLI_DIR/cmds/greet/greet.sh"

  build_test_wrapper testcli
  run "$CLI_DIR/bin/testcli" greet --name alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"NAME=alice"* ]]
}

@test "recompile picks up vars.HIDDEN changes" {
  create_test_cli "greet"
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"

  # Baseline: hidden is false
  run jq -r '.tasks["greet"].hidden' "$CLI_DIR/.clift/index.json"
  [[ "$output" == "false" ]]

  # Mutate the command Taskfile (portable: awk + mv).
  local tf="$CLI_DIR/cmds/greet/Taskfile.yaml"
  awk '/^vars:/{print; print "  HIDDEN: true"; next} {print}' "$tf" > "$tf.new"
  mv "$tf.new" "$tf"

  # Recompile directly — this test pins "compile re-reads the source", not
  # the cache.sh staleness/mtime path (covered elsewhere).
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
  run jq -r '.tasks["greet"].hidden' "$CLI_DIR/.clift/index.json"
  [[ "$output" == "true" ]]
}
