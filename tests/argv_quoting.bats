#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR"
  export FRAMEWORK_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export CLI_DIR="$TEST_DIR"
  export CLI_NAME="testcli"
  export CLI_VERSION="1.0.0"

  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
dotenv: ['.env']
vars:
  FLAGS:
    - {name: help, short: h, type: bool}
    - {name: verbose, short: v, type: bool}
    - {name: quiet, short: q, type: bool}
    - {name: no-color, type: bool}
    - {name: version, type: bool}
includes:
  echo:
    taskfile: ./cmds/echo
tasks:
  default:
    cmd: echo root
YAML
  cat > "$TEST_DIR/.env" <<ENV
CLI_NAME=$CLI_NAME
CLI_VERSION=$CLI_VERSION
CLI_DIR=$TEST_DIR
FRAMEWORK_DIR=$FRAMEWORK_DIR
CLIFT_MODE=standard
ENV

  mkdir -p "$TEST_DIR/cmds/echo"
  cat > "$TEST_DIR/cmds/echo/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: msg, short: m, type: string}
tasks:
  default:
    vars: {FLAGS: []}
    cmd: "CLI_ARGS='{{.CLI_ARGS}}' '{{.FRAMEWORK_DIR}}/lib/router/router.sh' '{{.TASK}}'"
YAML
  cat > "$TEST_DIR/cmds/echo/echo.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "MSG=[${CLIFT_FLAG_MSG:-unset}]"
for i in $(seq 1 "${CLIFT_POS_COUNT:-0}"); do
  var="CLIFT_POS_$i"
  echo "POS${i}=[${!var}]"
done
SCRIPT
  chmod +x "$TEST_DIR/cmds/echo/echo.sh"

  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$TEST_DIR"

  mkdir -p "$TEST_DIR/bin"
  sed \
    -e "s|%%FRAMEWORK_DIR%%|$FRAMEWORK_DIR|g" \
    -e "s|%%CLI_DIR%%|$TEST_DIR|g" \
    -e "s|%%CLI_NAME%%|$CLI_NAME|g" \
    -e "s|%%CLI_VERSION%%|$CLI_VERSION|g" \
    "$FRAMEWORK_DIR/lib/wrapper/wrapper.sh.tmpl" > "$TEST_DIR/bin/$CLI_NAME"
  chmod +x "$TEST_DIR/bin/$CLI_NAME"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "positional with spaces" {
  run "$TEST_DIR/bin/$CLI_NAME" echo "hello world"
  [[ "$output" == *"POS1=[hello world]"* ]]
}

@test "positional with single quotes" {
  run "$TEST_DIR/bin/$CLI_NAME" echo "it's working"
  [[ "$output" == *"POS1=[it's working]"* ]]
}

@test "positional with dollar literals" {
  run "$TEST_DIR/bin/$CLI_NAME" echo '$HOME'
  [[ "$output" == *'POS1=[$HOME]'* ]]
}

@test "flag value with double quotes escaped" {
  run "$TEST_DIR/bin/$CLI_NAME" echo --msg 'with "quotes" inside'
  [[ "$output" == *'MSG=[with "quotes" inside]'* ]]
}

@test "flag value with backslash" {
  run "$TEST_DIR/bin/$CLI_NAME" echo --msg 'a\b\c'
  [[ "$output" == *'MSG=[a\b\c]'* ]]
}
