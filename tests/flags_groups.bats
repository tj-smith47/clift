#!/usr/bin/env bats
# Flag groups: mutually-exclusive and required-together.
#
# Runtime cases source parser.sh directly with a hand-crafted flags.json
# (matches the pattern in tests/flags_parser.bats and tests/flags_aliases.bats);
# compile-time cases run validate.sh against a Taskfile fixture.

bats_require_minimum_version 1.5.0

load test_helper

setup() { common_setup; }
teardown() { common_teardown; }

# --- Mutually-exclusive groups ---------------------------------------------

@test "exclusive group: two members set errors with 'mutually exclusive' + both names" {
  cat > "$TEST_DIR/flags.json" <<'JSON'
[
  {"name": "json", "type": "bool", "group": "format", "exclusive": true},
  {"name": "yaml", "type": "bool", "group": "format", "exclusive": true},
  {"name": "csv",  "type": "bool", "group": "format", "exclusive": true}
]
JSON
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --json --yaml
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"mutually exclusive"* ]]
  [[ "$output" == *"--json"* ]]
  [[ "$output" == *"--yaml"* ]]
}

@test "exclusive group: one member set exits 0" {
  cat > "$TEST_DIR/flags.json" <<'JSON'
[
  {"name": "json", "type": "bool", "group": "format", "exclusive": true},
  {"name": "yaml", "type": "bool", "group": "format", "exclusive": true}
]
JSON
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --json
    echo \"JSON=\${CLIFT_FLAG_JSON:-unset}\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"JSON=true"* ]]
}

@test "exclusive group: no members set exits 0" {
  cat > "$TEST_DIR/flags.json" <<'JSON'
[
  {"name": "json", "type": "bool", "group": "format", "exclusive": true},
  {"name": "yaml", "type": "bool", "group": "format", "exclusive": true}
]
JSON
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json'
  "
  [ "$status" -eq 0 ]
}

# --- Required-together groups ----------------------------------------------

@test "requires-all group: one member set errors naming the missing flag" {
  cat > "$TEST_DIR/flags.json" <<'JSON'
[
  {"name": "user", "type": "string", "group": "creds", "requires": "all"},
  {"name": "pass", "type": "string", "group": "creds", "requires": "all"}
]
JSON
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --user=alice
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"required"* ]]
  [[ "$output" == *"--pass"* ]]
}

@test "requires-all group: all members set exits 0" {
  cat > "$TEST_DIR/flags.json" <<'JSON'
[
  {"name": "user", "type": "string", "group": "creds", "requires": "all"},
  {"name": "pass", "type": "string", "group": "creds", "requires": "all"}
]
JSON
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --user=alice --pass=hunter2
    echo \"USER=\${CLIFT_FLAG_USER} PASS=\${CLIFT_FLAG_PASS}\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"USER=alice"* ]]
  [[ "$output" == *"PASS=hunter2"* ]]
}

@test "requires-all group: no members set exits 0" {
  cat > "$TEST_DIR/flags.json" <<'JSON'
[
  {"name": "user", "type": "string", "group": "creds", "requires": "all"},
  {"name": "pass", "type": "string", "group": "creds", "requires": "all"}
]
JSON
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json'
  "
  [ "$status" -eq 0 ]
}

# --- Compile-time validation -----------------------------------------------

@test "validate: exclusive: true without group: errors" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: lonely, type: bool, exclusive: true}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"exclusive"* ]]
  [[ "$output" == *"group"* ]]
}

@test "validate: mixed modifiers within one group errors" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: one, type: string, group: "mix", exclusive: true}
    - {name: two, type: string, group: "mix", requires: "all"}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"group"* ]]
  [[ "$output" == *"consistent"* || "$output" == *"uses"* ]]
}

@test "validate: requires with non-'all' value errors" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: foo, type: string, group: "bar", requires: "xyz"}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"requires"* ]]
  [[ "$output" == *"all"* ]]
}

@test "validate: first-member-bare + later-member-modifier errors (important 1)" {
  # Repro of the "silent no-op" trap: if the first member has no modifier
  # and a later member adds exclusive/requires, the group used to compile
  # clean and do nothing at runtime. Now it must be a compile error.
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: a, type: bool, group: "g"}
    - {name: b, type: bool, group: "g", exclusive: true}
    - {name: c, type: bool, group: "g", requires: "all"}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"group 'g'"* ]]
  [[ "$output" == *"'b'"* ]]
  [[ "$output" == *"'a'"* ]]
}

@test "validate: bare-only group (cosmetic) passes" {
  # A named group with NO modifier on any member is purely cosmetic
  # (help-partition only) and must remain legal.
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: alpha, type: string, group: "ui"}
    - {name: beta,  type: string, group: "ui"}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
}

@test "validate: single-member exclusive group errors (important 2)" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: solo, type: bool, group: "alone", exclusive: true}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"group 'alone'"* ]]
  [[ "$output" == *"exclusive"* ]]
  [[ "$output" == *">=2"* ]]
}

@test "validate: single-member requires-all group errors (important 2)" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: solo, type: string, group: "alone", requires: "all"}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"group 'alone'"* ]]
  [[ "$output" == *"requires-all"* ]]
  [[ "$output" == *">=2"* ]]
}

@test "validate: well-formed mutex group passes" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: json, type: bool, group: "format", exclusive: true}
    - {name: yaml, type: bool, group: "format", exclusive: true}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
}

@test "validate: well-formed requires-all group passes" {
  cat > "$TEST_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: user, type: string, group: "creds", requires: "all"}
    - {name: pass, type: string, group: "creds", requires: "all"}
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/validate.sh" "$TEST_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
}

# --- Help rendering --------------------------------------------------------

@test "render_flags: mutex group renders as subsection" {
  run bash -c "
    source '$FRAMEWORK_DIR/lib/help/render_flags.sh'
    clift_render_flags '[
      {\"name\":\"json\",\"type\":\"bool\",\"group\":\"format\",\"exclusive\":true,\"desc\":\"json\"},
      {\"name\":\"yaml\",\"type\":\"bool\",\"group\":\"format\",\"exclusive\":true,\"desc\":\"yaml\"}
    ]'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"format (mutually exclusive)"* ]]
  [[ "$output" == *"--json"* ]]
  [[ "$output" == *"--yaml"* ]]
}

@test "render_flags: requires-all group renders as subsection" {
  run bash -c "
    source '$FRAMEWORK_DIR/lib/help/render_flags.sh'
    clift_render_flags '[
      {\"name\":\"user\",\"type\":\"string\",\"group\":\"creds\",\"requires\":\"all\",\"desc\":\"u\"},
      {\"name\":\"pass\",\"type\":\"string\",\"group\":\"creds\",\"requires\":\"all\",\"desc\":\"p\"}
    ]'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"creds (required together)"* ]]
  [[ "$output" == *"--user"* ]]
  [[ "$output" == *"--pass"* ]]
}

# --- Multi-member mutex + interaction with required: true ------------------

@test "exclusive group: 3 members all set, error names ALL three (suggestion 7a)" {
  cat > "$TEST_DIR/flags.json" <<'JSON'
[
  {"name": "json", "type": "bool", "group": "format", "exclusive": true},
  {"name": "yaml", "type": "bool", "group": "format", "exclusive": true},
  {"name": "csv",  "type": "bool", "group": "format", "exclusive": true}
]
JSON
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --json --yaml --csv
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"mutually exclusive"* ]]
  [[ "$output" == *"--json"* ]]
  [[ "$output" == *"--yaml"* ]]
  [[ "$output" == *"--csv"* ]]
}

@test "required + requires-all: setting only the required flag fires GROUP error, not required (suggestion 7d)" {
  # --user is required AND in requires-all group with --pass. User sets only
  # --user. Group check runs first, so the error must be the group violation
  # (--pass missing because --user was provided), not a missing-required
  # error. This pins precedence: group constraints validate before the
  # bare-required check.
  cat > "$TEST_DIR/flags.json" <<'JSON'
[
  {"name": "user", "type": "string", "group": "creds", "requires": "all", "required": true},
  {"name": "pass", "type": "string", "group": "creds", "requires": "all"}
]
JSON
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --user=alice
  "
  [ "$status" -ne 0 ]
  # Group error: --pass required when --user provided
  [[ "$output" == *"--pass"* ]]
  [[ "$output" == *"required"* ]]
  [[ "$output" == *"creds"* ]]
  # Must NOT be the bare missing-required wording for --user
  [[ "$output" != *"required flag '--user' not provided"* ]]
}

@test "required + requires-all: setting nothing fires the bare required error (suggestion 7d)" {
  # Counterpart to the precedence test: when NO group member is set, the
  # group check is a no-op (set_count == 0) and the standard required-flag
  # check fires for --user.
  cat > "$TEST_DIR/flags.json" <<'JSON'
[
  {"name": "user", "type": "string", "group": "creds", "requires": "all", "required": true},
  {"name": "pass", "type": "string", "group": "creds", "requires": "all"}
]
JSON
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json'
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"required flag '--user' not provided"* ]]
}
