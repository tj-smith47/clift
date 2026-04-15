#!/usr/bin/env bats
# Value validation via `choices:` and `pattern:` flag fields.
#
# Runtime cases source parser.sh directly with a hand-crafted flags.json
# (matches the pattern in tests/flags_parser.bats and tests/flags_groups.bats);
# compile-time cases run validate.sh against a Taskfile fixture.

bats_require_minimum_version 1.5.0

load test_helper

setup() { common_setup; }
teardown() { common_teardown; }

# --- Runtime: choices (string) --------------------------------------------

@test "choices string: valid value accepted" {
  cat > "$TEST_DIR/flags.json" <<'JSON'
[
  {"name": "level", "type": "string", "choices": ["low", "mid", "high"]}
]
JSON
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --level=mid
    echo \"LEVEL=\${CLIFT_FLAG_LEVEL}\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"LEVEL=mid"* ]]
}

@test "choices string: invalid value errors with allowed list" {
  cat > "$TEST_DIR/flags.json" <<'JSON'
[
  {"name": "level", "type": "string", "choices": ["low", "mid", "high"]}
]
JSON
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --level=bogus
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"not one of"* ]]
  [[ "$output" == *"low"* ]]
  [[ "$output" == *"mid"* ]]
  [[ "$output" == *"high"* ]]
  [[ "$output" == *"--level"* ]]
  [[ "$output" == *"bogus"* ]]
}

# --- Runtime: choices (list) ----------------------------------------------

@test "choices list: every element validated; first invalid element errors" {
  cat > "$TEST_DIR/flags.json" <<'JSON'
[
  {"name": "tag", "type": "list", "choices": ["a", "b", "c"]}
]
JSON
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --tag=a,zzz,b
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"not one of"* ]]
  [[ "$output" == *"zzz"* ]]
}

@test "choices list: all elements valid accepted" {
  cat > "$TEST_DIR/flags.json" <<'JSON'
[
  {"name": "tag", "type": "list", "choices": ["a", "b", "c"]}
]
JSON
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --tag=a,b
    echo \"COUNT=\${CLIFT_FLAG_TAG_COUNT}\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"COUNT=2"* ]]
}

# --- Runtime: pattern ------------------------------------------------------

@test "pattern: value matching accepted" {
  cat > "$TEST_DIR/flags.json" <<'JSON'
[
  {"name": "addr", "type": "string", "pattern": "^[0-9]{1,3}(\\.[0-9]{1,3}){3}$"}
]
JSON
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --addr=10.0.0.1
    echo \"ADDR=\${CLIFT_FLAG_ADDR}\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"ADDR=10.0.0.1"* ]]
}

@test "pattern: non-matching value errors with 'does not match pattern'" {
  cat > "$TEST_DIR/flags.json" <<'JSON'
[
  {"name": "addr", "type": "string", "pattern": "^[0-9]+$"}
]
JSON
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --addr=nope
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not match pattern"* ]]
  [[ "$output" == *"--addr"* ]]
  [[ "$output" == *"nope"* ]]
}

# --- Runtime: choices + pattern simultaneously ----------------------------

@test "choices + pattern: both must pass (choices fails first)" {
  cat > "$TEST_DIR/flags.json" <<'JSON'
[
  {"name": "tier", "type": "string", "choices": ["s1", "s2"], "pattern": "^s[0-9]+$"}
]
JSON
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --tier=xx
  "
  [ "$status" -ne 0 ]
  # Either error is acceptable — both constraints fail; the first-checked wins.
  [[ "$output" == *"--tier"* ]]
}

# --- Runtime: default also validated --------------------------------------

# The default-not-in-choices compile check is the primary guard, but if a
# user calls the parser with a legitimate default, it should pass validation.
@test "default inside choices passes runtime validation" {
  cat > "$TEST_DIR/flags.json" <<'JSON'
[
  {"name": "level", "type": "string", "choices": ["low", "high"], "default": "low"}
]
JSON
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json'
    echo \"LEVEL=\${CLIFT_FLAG_LEVEL}\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"LEVEL=low"* ]]
}

# --- Compile: schema errors ------------------------------------------------

@test "compile: bool + choices rejected" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: force, type: bool, choices: ["yes", "no"]}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bool and cannot declare 'choices'"* ]]
}

@test "compile: bool + pattern rejected" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: force, type: bool, pattern: "^y$"}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bool and cannot declare 'pattern'"* ]]
}

@test "compile: empty choices array rejected" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: level, type: string, choices: []}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"empty 'choices'"* ]]
}

@test "compile: non-array choices rejected" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: level, type: string, choices: "a,b,c"}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be a non-empty array"* ]]
}

@test "compile: default not in choices rejected" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: level, type: string, choices: [low, mid, high], default: critical}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"default 'critical' is not in choices"* ]]
}

@test "compile: list default with one element outside choices rejected" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: tag, type: list, choices: [a, b, c], default: "a,zzz"}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"default element 'zzz' is not in choices"* ]]
}

@test "compile: well-formed choices + default passes" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: level, type: string, choices: [low, mid, high], default: mid}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
}

@test "compile: well-formed pattern passes" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: ref, type: string, pattern: "^v[0-9]+\\.[0-9]+\\.[0-9]+$"}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
}

@test "compile: empty pattern rejected" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: ref, type: string, pattern: ""}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"empty 'pattern'"* ]]
}

# --- Help rendering --------------------------------------------------------

@test "render_flags: choices flag shows '(one of: ...)' in help" {
  # Drive render_flags.sh directly with a JSON array; column -t collapses
  # whitespace so we assert the literal substring 'one of: low, mid, high'.
  run bash -c "
    source '$FRAMEWORK_DIR/lib/help/render_flags.sh'
    clift_render_flags '[{\"name\":\"level\",\"type\":\"string\",\"desc\":\"Log level\",\"choices\":[\"low\",\"mid\",\"high\"]}]'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"--level"* ]]
  [[ "$output" == *"(one of: low, mid, high)"* ]]
}

@test "render_flags: flag without choices does not add 'one of' suffix" {
  run bash -c "
    source '$FRAMEWORK_DIR/lib/help/render_flags.sh'
    clift_render_flags '[{\"name\":\"name\",\"type\":\"string\",\"desc\":\"Your name\"}]'
  "
  [ "$status" -eq 0 ]
  [[ "$output" != *"one of"* ]]
}

# --- Runtime: choices on int ----------------------------------------------

@test "choices int: valid integer accepted" {
  cat > "$TEST_DIR/flags.json" <<'JSON'
[
  {"name": "port", "type": "int", "choices": ["80", "443", "8080"]}
]
JSON
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --port=443
    echo \"PORT=\${CLIFT_FLAG_PORT}\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"PORT=443"* ]]
}

@test "choices int: value not in list errors" {
  cat > "$TEST_DIR/flags.json" <<'JSON'
[
  {"name": "port", "type": "int", "choices": ["80", "443", "8080"]}
]
JSON
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --port=22
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"not one of"* ]]
  [[ "$output" == *"--port"* ]]
}

# --- Compile: int + non-integer choices -----------------------------------

@test "compile: int flag with non-integer choices rejected" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: count, type: int, choices: ["one", "two", "three"]}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"non-integer"* ]]
}

# --- Compile: invalid regex -----------------------------------------------

@test "compile: syntactically invalid regex pattern rejected" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: ref, type: string, pattern: "[invalid(regex"}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid regex"* ]]
}

# --- Help: pattern suffix + combined --------------------------------------

@test "render_flags: pattern flag shows '(matches: ...)' in help" {
  run bash -c "
    source '$FRAMEWORK_DIR/lib/help/render_flags.sh'
    clift_render_flags '[{\"name\":\"ref\",\"type\":\"string\",\"desc\":\"Git ref\",\"pattern\":\"^v[0-9]+\$\"}]'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"(matches: ^v[0-9]+\$)"* ]]
}

@test "render_flags: choices + pattern both appear in help" {
  run bash -c "
    source '$FRAMEWORK_DIR/lib/help/render_flags.sh'
    clift_render_flags '[{\"name\":\"tier\",\"type\":\"string\",\"desc\":\"Tier\",\"choices\":[\"s1\",\"s2\"],\"pattern\":\"^s[0-9]+\$\"}]'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"(one of: s1, s2)"* ]]
  [[ "$output" == *"(matches: ^s[0-9]+\$)"* ]]
}
