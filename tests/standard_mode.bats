#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR"
  export FRAMEWORK_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  touch "$HOME/.bashrc"
  export CLIFT_RC_FILE="$HOME/.bashrc"
  export SHELL=/bin/bash
  export PROMPT=false
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "end-to-end: setup, scaffold command, run, get flag values" {
  local cli="$TEST_DIR/mycli"

  # Setup a standard-mode CLI
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$cli" "$FRAMEWORK_DIR" "mycli" "0.1.0" "minimal" "standard"

  # Scaffold a command
  CLI_DIR="$cli" CLI_NAME="mycli" \
  bash "$FRAMEWORK_DIR/lib/scaffold/scaffold.sh" "greet" "Say hi" "$cli" "$FRAMEWORK_DIR"

  # Add a flag to the generated command Taskfile.
  # The scaffold produces two FLAGS: [] lines -- one top-level (command layer)
  # and one under tasks.default.vars (task layer). Replace only the first
  # occurrence (the top-level one) so the flag applies to the command.
  _tmp="$(mktemp)"
  sed '0,/FLAGS: \[\]/{s/FLAGS: \[\]/FLAGS:\n    - {name: name, short: n, type: string, default: world}/}' \
    "$cli/cmds/greet/Taskfile.yaml" > "$_tmp"
  mv "$_tmp" "$cli/cmds/greet/Taskfile.yaml"

  # Rewrite the generated script to print the flag
  cat > "$cli/cmds/greet/greet.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "hi ${CLIFT_FLAG_NAME}"
SCRIPT
  chmod +x "$cli/cmds/greet/greet.sh"

  # Rebuild cache after hand-edit
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$cli"

  # Invoke via the wrapper
  run "$cli/bin/mycli" greet --name alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"hi alice"* ]]

  # Default applies when absent
  run "$cli/bin/mycli" greet
  [ "$status" -eq 0 ]
  [[ "$output" == *"hi world"* ]]

  # Short form works
  run "$cli/bin/mycli" greet -n bob
  [ "$status" -eq 0 ]
  [[ "$output" == *"hi bob"* ]]
}
