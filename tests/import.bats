#!/usr/bin/env bats
# Deprecation stub for the retired `clift import` command. The original
# import surface (lib/import/import.sh) was built on the wrong premise
# (adopt-into-existing-CLI) and was replaced by `clift init <name> --from PATH`.
#
# These tests lock in the one-release soft-landing: invoking `clift import`
# (or running redirect.sh directly) emits a single stderr line pointing the
# user at the replacement command, and exits 2. Once the deprecation window
# closes, lib/import/ can be removed entirely along with this test file.
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

@test "redirect.sh prints the deprecation line on stderr and exits 2" {
  run bash "$FRAMEWORK_DIR/lib/import/redirect.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"clift import"* ]]
  [[ "$output" == *"clift init"* ]]
  [[ "$output" == *"--from"* ]]
}

@test "redirect.sh writes the message to stderr (not stdout)" {
  # Capture streams independently — the message must not pollute stdout.
  local out_file err_file
  out_file="$TEST_DIR/redirect.out"
  err_file="$TEST_DIR/redirect.err"
  bash "$FRAMEWORK_DIR/lib/import/redirect.sh" \
    >"$out_file" 2>"$err_file" || true
  [ ! -s "$out_file" ]
  grep -q "clift import" "$err_file"
}

@test "clift import dispatches the redirect through the wrapper" {
  # Existing CLIs that still have the `import:` include in their root
  # Taskfile keep getting the redirect for one release. Simulate an
  # already-initialized CLI by adding the include manually after init —
  # newer `clift init` no longer writes it (it was dropped from the
  # template alongside this stub).
  #
  # Exit code under the wrapper is `task`'s own translated value (201)
  # rather than the script's native 2 — the exit-2 contract is enforced
  # at the script level by the redirect.sh test above. Here we only
  # require non-zero plus the right user-facing message.
  _init_impcli
  awk 'BEGIN{done=0} {print} /^includes:$/ && !done {
        print "  import:";
        print "    taskfile: '\''{{.FRAMEWORK_DIR}}/lib/import'\''";
        done=1
      }' \
    "$CLI_DIR/Taskfile.yaml" > "$CLI_DIR/Taskfile.yaml.new"
  mv "$CLI_DIR/Taskfile.yaml.new" "$CLI_DIR/Taskfile.yaml"
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR" >/dev/null

  run "$CLI_DIR/bin/impcli" import
  [ "$status" -ne 0 ]
  [[ "$output" == *"clift import"* ]]
  [[ "$output" == *"clift init"* ]]
}
