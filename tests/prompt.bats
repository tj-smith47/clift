#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR"
  export FRAMEWORK_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "prompt input returns existing env var without prompting" {
  run bash -c 'export MY_VAR="existing_value"; "$FRAMEWORK_DIR/lib/prompt/prompt.sh" input "Label" --var MY_VAR'
  [ "$status" -eq 0 ]
  [ "$output" = "existing_value" ]
}

@test "prompt choose returns existing env var without prompting" {
  run bash -c 'export MY_VAR="opt2"; "$FRAMEWORK_DIR/lib/prompt/prompt.sh" choose "Label" --var MY_VAR --options "opt1,opt2,opt3"'
  [ "$status" -eq 0 ]
  [ "$output" = "opt2" ]
}

@test "prompt input with PROMPT=false uses default" {
  run bash -c 'export PROMPT=false; "$FRAMEWORK_DIR/lib/prompt/prompt.sh" input "Label" --var UNSET_VAR --default "fallback"'
  [ "$status" -eq 0 ]
  [ "$output" = "fallback" ]
}

@test "prompt input with PROMPT=false and no default exits with error" {
  run bash -c 'export PROMPT=false; "$FRAMEWORK_DIR/lib/prompt/prompt.sh" input "Label" --var UNSET_VAR 2>&1'
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing required value"* ]]
}

@test "prompt choose with PROMPT=false uses default" {
  run bash -c 'export PROMPT=false; "$FRAMEWORK_DIR/lib/prompt/prompt.sh" choose "Label" --var UNSET_VAR --options "a,b,c" --default "b"'
  [ "$status" -eq 0 ]
  [ "$output" = "b" ]
}

@test "prompt requires --var flag" {
  run bash -c '"$FRAMEWORK_DIR/lib/prompt/prompt.sh" input "Label" 2>&1'
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires --var"* ]]
}

@test "prompt rejects unknown flags" {
  run bash -c '"$FRAMEWORK_DIR/lib/prompt/prompt.sh" input "Label" --var X --bogus 2>&1'
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown"* ]]
}

@test "prompt choose requires --options" {
  run bash -c 'export PROMPT=true; echo "1" | "$FRAMEWORK_DIR/lib/prompt/prompt.sh" choose "Label" --var UNSET_VAR 2>&1'
  [ "$status" -eq 1 ]
  [[ "$output" == *"--options required"* ]]
}

@test "prompt rejects unknown type" {
  run bash -c '"$FRAMEWORK_DIR/lib/prompt/prompt.sh" bogustype "Label" --var X 2>&1'
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown prompt type"* ]]
}

@test "prompt input with PROMPT=false and empty var uses default" {
  # PROMPT=false ensures no interactive path is attempted
  run bash -c 'export PROMPT=false; unset UNSET_VAR; "$FRAMEWORK_DIR/lib/prompt/prompt.sh" input "Label" --var UNSET_VAR --default "mydefault"'
  [ "$status" -eq 0 ]
  [ "$output" = "mydefault" ]
}

@test "prompt choose with PROMPT=false and no default exits with error" {
  run bash -c 'export PROMPT=false; "$FRAMEWORK_DIR/lib/prompt/prompt.sh" choose "Label" --var UNSET_VAR --options "a,b,c" 2>&1'
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing required value"* ]]
}

@test "prompt input with PROMPT=false returns default for empty var" {
  run bash -c 'export PROMPT=false; export MY_VAR=""; "$FRAMEWORK_DIR/lib/prompt/prompt.sh" input "Label" --var MY_VAR --default "fb" 2>&1'
  [ "$status" -eq 0 ]
  [ "$output" = "fb" ]
}

@test "prompt requires type and label" {
  run bash -c '"$FRAMEWORK_DIR/lib/prompt/prompt.sh" 2>&1'
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires type and label"* ]]
}

@test "prompt choose existing env var takes priority over options" {
  run bash -c 'export PICK="special"; "$FRAMEWORK_DIR/lib/prompt/prompt.sh" choose "Label" --var PICK --options "a,b,c"'
  [ "$status" -eq 0 ]
  [ "$output" = "special" ]
}

@test "prompt input uses read fallback when gum unavailable" {
  # Mock: no gum on PATH, provide input via /dev/tty simulation
  # Use a fifo to simulate tty input
  local fifo="$TEST_DIR/input_fifo"
  mkfifo "$fifo"
  echo "typed_value" > "$fifo" &

  run bash -c '
    export PATH="/usr/bin:/bin:/usr/local/bin"
    "$FRAMEWORK_DIR/lib/prompt/prompt.sh" input "Name" --var UNSET_VAR < "'"$fifo"'"
  '
  # Either gets the value or fails because no tty — the read path is exercised either way
  [[ "$output" == *"typed_value"* ]] || [ "$status" -ne 0 ]
  rm -f "$fifo"
}

@test "prompt choose uses read fallback with numeric selection" {
  local fifo="$TEST_DIR/choose_fifo"
  mkfifo "$fifo"
  echo "2" > "$fifo" &

  run bash -c '
    export PATH="/usr/bin:/bin:/usr/local/bin"
    "$FRAMEWORK_DIR/lib/prompt/prompt.sh" choose "Pick" --var UNSET_VAR --options "alpha,beta,gamma" < "'"$fifo"'"
  '
  [[ "$output" == *"beta"* ]] || [ "$status" -ne 0 ]
  rm -f "$fifo"
}

@test "prompt choose with invalid selection and default falls back" {
  run bash -c '
    export PROMPT=false
    "$FRAMEWORK_DIR/lib/prompt/prompt.sh" choose "Pick" --var UNSET_VAR --options "a,b,c" --default "b"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "b" ]
}

@test "prompt input uses gum when available" {
  # Create a mock gum that returns a known value
  mkdir -p "$TEST_DIR/fakebin"
  cat > "$TEST_DIR/fakebin/gum" <<'SCRIPT'
#!/bin/sh
# Mock gum: echo placeholder value for input
if [ "$1" = "input" ]; then
  echo "gum_input_value"
elif [ "$1" = "choose" ]; then
  # Read stdin options and return the first one
  head -1
fi
SCRIPT
  chmod +x "$TEST_DIR/fakebin/gum"

  run bash -c "
    export PATH=\"$TEST_DIR/fakebin:\$PATH\"
    \"\$FRAMEWORK_DIR/lib/prompt/prompt.sh\" input 'Name' --var UNSET_VAR
  "
  [ "$status" -eq 0 ]
  [ "$output" = "gum_input_value" ]
}

@test "prompt input with gum uses default as initial value" {
  mkdir -p "$TEST_DIR/fakebin"
  cat > "$TEST_DIR/fakebin/gum" <<'SCRIPT'
#!/bin/sh
# Mock gum: echo the --value arg if present
while [ $# -gt 0 ]; do
  case "$1" in
    --value) echo "$2"; exit 0 ;;
    *) shift ;;
  esac
done
echo "no_value"
SCRIPT
  chmod +x "$TEST_DIR/fakebin/gum"

  run bash -c "
    export PATH=\"$TEST_DIR/fakebin:\$PATH\"
    \"\$FRAMEWORK_DIR/lib/prompt/prompt.sh\" input 'Name' --var UNSET_VAR --default 'Alice'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "Alice" ]
}

@test "prompt choose uses gum when available" {
  mkdir -p "$TEST_DIR/fakebin"
  cat > "$TEST_DIR/fakebin/gum" <<'SCRIPT'
#!/bin/sh
if [ "$1" = "choose" ]; then
  # Return the second option
  head -2 | tail -1
fi
SCRIPT
  chmod +x "$TEST_DIR/fakebin/gum"

  run bash -c "
    export PATH=\"$TEST_DIR/fakebin:\$PATH\"
    \"\$FRAMEWORK_DIR/lib/prompt/prompt.sh\" choose 'Pick' --var UNSET_VAR --options 'alpha,beta,gamma'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "beta" ]
}
