#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load test_helper

setup() { common_setup; }
teardown() { common_teardown; }

# Runtime: using a deprecated flag emits a stderr warning and still works.
@test "deprecated flag emits stderr warning when used" {
  cat > "$TEST_DIR/flags.json" <<'JSON'
[
  {"name": "old", "type": "string", "deprecated": "use --new instead"}
]
JSON
  run --separate-stderr bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --old=x
    echo \"OLD=\${CLIFT_FLAG_OLD}\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"OLD=x"* ]]
  [[ "$stderr" == *"warning: --old is deprecated: use --new instead"* ]]
}

@test "deprecated flag does not warn when unused" {
  cat > "$TEST_DIR/flags.json" <<'JSON'
[
  {"name": "old", "type": "string", "deprecated": "use --new instead"},
  {"name": "other", "type": "string"}
]
JSON
  run --separate-stderr bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --other=y
  "
  [ "$status" -eq 0 ]
  [[ "$stderr" != *"deprecated"* ]]
}

@test "deprecated empty string does not warn" {
  cat > "$TEST_DIR/flags.json" <<'JSON'
[
  {"name": "old", "type": "string", "deprecated": ""}
]
JSON
  run --separate-stderr bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --old=x
  "
  [ "$status" -eq 0 ]
  [[ "$stderr" != *"deprecated"* ]]
}

# Alias used against a deprecated flag should warn under the canonical name.
@test "deprecated flag alias warns under canonical name" {
  cat > "$TEST_DIR/flags.json" <<'JSON'
[
  {"name": "old", "aliases": ["legacy"], "type": "string", "deprecated": "use --new instead"}
]
JSON
  run --separate-stderr bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --legacy=x
  "
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"warning: --old is deprecated: use --new instead"* ]]
}

# Bool deprecated flag (no value) warns too.
@test "deprecated bool flag warns when set" {
  cat > "$TEST_DIR/flags.json" <<'JSON'
[
  {"name": "old", "type": "bool", "deprecated": "removed in v2"}
]
JSON
  run --separate-stderr bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --old
  "
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"warning: --old is deprecated: removed in v2"* ]]
}

# Short form (-o) of a deprecated flag should also warn.
@test "deprecated flag warns via short form" {
  cat > "$TEST_DIR/flags.json" <<'JSON'
[
  {"name": "old", "short": "o", "type": "string", "deprecated": "use --new"}
]
JSON
  run --separate-stderr bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' -o x
  "
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"warning: --old is deprecated: use --new"* ]]
}

# Compile pipeline: deprecated field must survive into flags.json.
@test "compile preserves deprecated field in flags.json" {
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
    - {name: old, type: string, deprecated: "use --new instead", desc: "old flag"}
tasks:
  default:
    cmd: echo show
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
  [ "$status" -eq 0 ]
  run jq -r '(.["show"] // .["show:default"]) | map(select(.name == "old")) | .[0].deprecated' "$CLI_DIR/.clift/flags.json"
  [[ "$output" == *"use --new instead"* ]]
}

# Help rendering: deprecated flags get a " (deprecated)" suffix.
@test "render_flags marks deprecated flags in help output" {
  run bash -c "
    source '$FRAMEWORK_DIR/lib/help/render_flags.sh'
    clift_render_flags '[{\"name\":\"old\",\"type\":\"string\",\"desc\":\"old flag\",\"deprecated\":\"use --new\"}]'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"--old"* ]]
  [[ "$output" == *"(deprecated)"* ]]
}

@test "render_flags does not mark non-deprecated flags" {
  run bash -c "
    source '$FRAMEWORK_DIR/lib/help/render_flags.sh'
    clift_render_flags '[{\"name\":\"keep\",\"type\":\"string\",\"desc\":\"active flag\"}]'
  "
  [ "$status" -eq 0 ]
  [[ "$output" != *"(deprecated)"* ]]
}
