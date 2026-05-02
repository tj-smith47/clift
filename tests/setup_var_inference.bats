#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

# Tests for lib/setup/var_inference.sh — pure functions that turn go-task
# vars: / requires.vars: declarations into clift FLAG entries.

load test_helper

setup() {
  common_setup
  # shellcheck source=../lib/setup/var_inference.sh
  source "$FRAMEWORK_DIR/lib/setup/var_inference.sh"
}

teardown() {
  common_teardown
}

# --- Bool inference -----------------------------------------------------

@test "infer_flag: unquoted true → bool, no default key" {
  run -0 infer_flag DRY_RUN true
  [ "$(echo "$output" | jq -r '.name')"          = "dry-run" ]
  [ "$(echo "$output" | jq -r '.type')"          = "bool" ]
  # validate.sh rule 6 rejects bool flags carrying `default`. Bool semantics
  # are presence-driven (see var_inference.sh header).
  [ "$(echo "$output" | jq 'has("default") | not')" = "true" ]
}

@test "infer_flag: unquoted false → bool, no default key" {
  run -0 infer_flag DRY_RUN false
  [ "$(echo "$output" | jq -r '.name')"          = "dry-run" ]
  [ "$(echo "$output" | jq -r '.type')"          = "bool" ]
  [ "$(echo "$output" | jq 'has("default") | not')" = "true" ]
}

@test "infer_flag: quoted \"true\" → bool, no default key" {
  run -0 infer_flag RELEASE '"true"'
  [ "$(echo "$output" | jq -r '.type')"          = "bool" ]
  [ "$(echo "$output" | jq 'has("default") | not')" = "true" ]
}

@test "infer_flag: quoted \"false\" → bool, no default key" {
  run -0 infer_flag RELEASE '"false"'
  [ "$(echo "$output" | jq -r '.type')"          = "bool" ]
  [ "$(echo "$output" | jq 'has("default") | not')" = "true" ]
}

# --- Int inference ------------------------------------------------------

@test "infer_flag: integer 3 → int default 3" {
  run -0 infer_flag REPLICAS 3
  [ "$(echo "$output" | jq -r '.name')"    = "replicas" ]
  [ "$(echo "$output" | jq -r '.type')"    = "int" ]
  [ "$(echo "$output" | jq -r '.default')" = "3" ]
}

@test "infer_flag: integer 0 → int default 0" {
  run -0 infer_flag COUNT 0
  [ "$(echo "$output" | jq -r '.type')"    = "int" ]
  [ "$(echo "$output" | jq -r '.default')" = "0" ]
}

@test "infer_flag: negative integer -5 → int default -5" {
  run -0 infer_flag OFFSET '-5'
  [ "$(echo "$output" | jq -r '.type')"    = "int" ]
  [ "$(echo "$output" | jq -r '.default')" = "-5" ]
}

# --- Float / string ----------------------------------------------------

@test "infer_flag: float 1.5 → string (no float in clift)" {
  run -0 infer_flag SCALE 1.5
  [ "$(echo "$output" | jq -r '.type')"    = "string" ]
  [ "$(echo "$output" | jq -r '.default')" = "1.5" ]
}

@test "infer_flag: bare string myapp → string" {
  run -0 infer_flag NAME myapp
  [ "$(echo "$output" | jq -r '.type')"    = "string" ]
  [ "$(echo "$output" | jq -r '.default')" = "myapp" ]
}

@test "infer_flag: quoted string \"myapp\" → string with quotes stripped" {
  run -0 infer_flag NAME '"myapp"'
  [ "$(echo "$output" | jq -r '.type')"    = "string" ]
  [ "$(echo "$output" | jq -r '.default')" = "myapp" ]
}

@test "infer_flag: empty string \"\" → string default \"\"" {
  run -0 infer_flag NOTE '""'
  [ "$(echo "$output" | jq -r '.name')"    = "note" ]
  [ "$(echo "$output" | jq -r '.type')"    = "string" ]
  [ "$(echo "$output" | jq -r '.default')" = "" ]
}

@test "infer_flag: go-task template {{.OTHER}} → string preserved" {
  run -0 infer_flag DEST '{{.OTHER}}'
  [ "$(echo "$output" | jq -r '.type')"    = "string" ]
  [ "$(echo "$output" | jq -r '.default')" = "{{.OTHER}}" ]
}

# --- Name conversion ---------------------------------------------------

@test "infer_flag: DRY_RUN → dry-run" {
  run -0 infer_flag DRY_RUN false
  [ "$(echo "$output" | jq -r '.name')" = "dry-run" ]
}

@test "infer_flag: MAX_RETRY → max-retry" {
  run -0 infer_flag MAX_RETRY 3
  [ "$(echo "$output" | jq -r '.name')" = "max-retry" ]
}

@test "infer_flag: FOO_BAR_BAZ → foo-bar-baz" {
  run -0 infer_flag FOO_BAR_BAZ x
  [ "$(echo "$output" | jq -r '.name')" = "foo-bar-baz" ]
}

@test "infer_flag: single-token NAME → name" {
  run -0 infer_flag NAME hello
  [ "$(echo "$output" | jq -r '.name')" = "name" ]
}

# --- Required ----------------------------------------------------------

@test "infer_required: ENV → string required" {
  run -0 infer_required ENV
  [ "$(echo "$output" | jq -r '.name')"     = "env" ]
  [ "$(echo "$output" | jq -r '.type')"     = "string" ]
  [ "$(echo "$output" | jq -r '.required')" = "true" ]
  # No default is permitted alongside required:true (validate.sh rule 5).
  [ "$(echo "$output" | jq 'has("default")')" = "false" ]
}

@test "infer_required: TARGET_HOST → target-host string required" {
  run -0 infer_required TARGET_HOST
  [ "$(echo "$output" | jq -r '.name')"     = "target-host" ]
  [ "$(echo "$output" | jq -r '.required')" = "true" ]
}

# --- Invalid name rejection --------------------------------------------

@test "infer_flag: name starting with digit rejected" {
  run infer_flag 1ST_PLACE 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a valid flag name"* ]]
}

@test "infer_required: name starting with digit rejected" {
  run infer_required 9LIVES
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a valid flag name"* ]]
}

@test "infer_flag: empty varname rejected" {
  run infer_flag '' false
  [ "$status" -ne 0 ]
  [[ "$output" == *"empty variable name"* ]]
}

@test "infer_flag: missing args rejected" {
  run infer_flag DRY_RUN
  [ "$status" -ne 0 ]
  [[ "$output" == *"requires"* ]]
}

@test "infer_required: missing arg rejected" {
  run infer_required
  [ "$status" -ne 0 ]
  [[ "$output" == *"requires"* ]]
}
