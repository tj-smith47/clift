#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load test_helper

setup() { common_setup; }
teardown() { common_teardown; }

# End-to-end: aliases resolve to the canonical flag at runtime.
@test "flag alias resolves to canonical name via parser" {
  cat > "$TEST_DIR/flags.json" <<'JSON'
[
  {"name": "format", "aliases": ["output", "fmt"], "type": "string", "default": "json"}
]
JSON
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --output yaml
    echo \"FORMAT=\${CLIFT_FLAG_FORMAT}\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"FORMAT=yaml"* ]]
}

@test "second alias resolves to canonical name" {
  cat > "$TEST_DIR/flags.json" <<'JSON'
[
  {"name": "format", "aliases": ["output", "fmt"], "type": "string", "default": "json"}
]
JSON
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --fmt csv
    echo \"FORMAT=\${CLIFT_FLAG_FORMAT}\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"FORMAT=csv"* ]]
}

@test "alias with =value form works" {
  cat > "$TEST_DIR/flags.json" <<'JSON'
[
  {"name": "format", "aliases": ["output"], "type": "string"}
]
JSON
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --output=yaml
    echo \"FORMAT=\${CLIFT_FLAG_FORMAT}\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"FORMAT=yaml"* ]]
}

@test "bool alias sets canonical flag to true" {
  cat > "$TEST_DIR/flags.json" <<'JSON'
[
  {"name": "force", "aliases": ["yes"], "type": "bool"}
]
JSON
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --yes
    echo \"FORCE=\${CLIFT_FLAG_FORCE:-unset}\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"FORCE=true"* ]]
}

# Validation: aliases must not collide with other names or aliases.
@test "alias duplicating another flag's name errors at compile time" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: a, type: string}
    - {name: b, aliases: ["a"], type: string}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"alias 'a' conflicts"* ]]
}

@test "two flags declaring the same alias error at compile time" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: first, aliases: ["x"], type: string}
    - {name: second, aliases: ["x"], type: string}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"alias 'x' conflicts"* ]]
}

@test "alias matching its own flag's name errors" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: foo, aliases: ["foo"], type: string}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"alias 'foo' conflicts"* ]]
}

@test "valid non-colliding aliases pass validation" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: format, aliases: ["output", "fmt"], type: string}
    - {name: force, aliases: ["yes"], type: bool}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
}

# Compile pipeline: aliases field must survive into flags.json.
@test "compile preserves aliases field in flags.json" {
  export CLI_DIR="$TEST_DIR"
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
dotenv: ['.env']
vars:
  FLAGS:
    - {name: trace, short: t, type: bool, desc: "Trace"}
includes:
  show:
    taskfile: ./cmds/show
tasks:
  default:
    cmd: echo hi
YAML
  echo "CLI_NAME=testcli" > "$TEST_DIR/.env"
  mkdir -p "$TEST_DIR/cmds/show"
  cat > "$TEST_DIR/cmds/show/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: format, aliases: ["output", "fmt"], type: string, default: "json", desc: "output format"}
tasks:
  default:
    cmd: echo show
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
  [ "$status" -eq 0 ]
  run jq -r '(.["show"] // .["show:default"]) | map(select(.name == "format")) | .[0].aliases | .[]' "$CLI_DIR/.clift/flags.json"
  [[ "$output" == *"output"* ]]
  [[ "$output" == *"fmt"* ]]
}

# Help rendering: aliases appear alongside the canonical name.
@test "render_flags emits aliases in the flag column" {
  run bash -c "
    source '$FRAMEWORK_DIR/lib/help/render_flags.sh'
    clift_render_flags '[{\"name\":\"format\",\"aliases\":[\"output\",\"fmt\"],\"type\":\"string\",\"desc\":\"output format\"}]'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"--format"* ]]
  [[ "$output" == *"--output"* ]]
  [[ "$output" == *"--fmt"* ]]
}
