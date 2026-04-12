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

@test "valid bool flag passes" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: force, short: f, type: bool, desc: "Skip confirm"}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
}

@test "flag name with underscore rejected" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: dry_run, type: bool}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"must match"* ]]
}

@test "reserved flag name rejected" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: help, type: bool}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"reserved"* ]]
}

@test "missing type rejected" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: force}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing 'type'"* ]]
}

@test "invalid type rejected" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: force, type: boolean}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid type"* ]]
}

@test "invalid short rejected" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: force, short: ff, type: bool}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"short"* ]]
}

@test "duplicate name within layer rejected" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: force, type: bool}
    - {name: force, type: string}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate flag name"* ]]
}

@test "duplicate short within layer rejected" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: force, short: f, type: bool}
    - {name: file, short: f, type: string}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate short"* ]]
}

@test "per-task vars.FLAGS validated" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS: []
tasks:
  default:
    vars:
      FLAGS:
        - {name: bad_name, type: bool}
    cmd: echo hi
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tasks.default"* ]]
}

@test "empty FLAGS list passes" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS: []
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
}

@test "missing FLAGS key passes (legacy Taskfile)" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
tasks:
  default:
    cmd: echo hi
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
}

@test "required + default rejected" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: target, type: string, required: true, default: staging}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"required"* ]]
}

@test "bool with default rejected" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: force, type: bool, default: "true"}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bool"* ]]
}

@test "int with non-numeric default rejected" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: count, type: int, default: "abc"}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"integer"* ]]
}

@test "int with negative default accepted" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: count, type: int, default: "-5"}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
}
