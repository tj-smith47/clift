#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load test_helper

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

@test "task name with colon validates per-task FLAGS" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
tasks:
  deploy:staging:
    vars:
      FLAGS:
        - {name: bad_name, type: bool}
    cmd: echo hi
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tasks.deploy:staging"* ]]
  [[ "$output" == *"must match"* ]]
}

@test "task name with colon and valid FLAGS passes" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
tasks:
  deploy:prod:
    vars:
      FLAGS:
        - {name: force, short: f, type: bool}
    cmd: echo hi
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
}

@test "flag name starting with arg- rejected" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: arg-count, type: int}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"reserved"* ]]
}

@test "flag name 'task' rejected" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: task, type: string}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"reserved"* ]]
}

@test "flag name 'mode' rejected" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: mode, type: string}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"reserved"* ]]
}

@test "bare-string FLAGS entry rejected cleanly (no jq stderr leak)" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - force
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be a map"* ]]
  [[ "$output" != *"jq: error"* ]]
}

@test "malformed YAML surfaces real error, not silent pass" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS: [this is not valid yaml :
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -ne 0 ]
}

@test "100 tasks with 2 flags each validates quickly" {
  # Build a synthetic Taskfile with 100 tasks
  {
    echo "version: '3'"
    echo "tasks:"
    for i in $(seq 1 100); do
      cat <<YAML
  task${i}:
    vars:
      FLAGS:
        - {name: opt-a-${i}, short: a, type: bool}
        - {name: opt-b-${i}, short: b, type: string, default: "hi"}
    cmd: echo ${i}
YAML
    done
  } > "$TEST_DIR/Taskfile.yaml"

  # Bound: 5 seconds (generous; target is <1s after fix)
  local start=$SECONDS
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  local elapsed=$((SECONDS - start))
  [ "$status" -eq 0 ]
  [ "$elapsed" -lt 5 ]
}
