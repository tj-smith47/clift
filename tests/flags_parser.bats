#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR"
  export FRAMEWORK_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

  # A flag table fixture with one of each type
  cat > "$TEST_DIR/flags.json" <<'JSON'
[
  {"name": "force", "short": "f", "type": "bool"},
  {"name": "verbose", "short": "v", "type": "bool"},
  {"name": "target", "short": "t", "type": "string", "default": "staging"},
  {"name": "count", "short": "c", "type": "int"},
  {"name": "tag", "type": "list"},
  {"name": "required-one", "short": "r", "type": "string", "required": true}
]
JSON
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "parses long bool flag" {
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --force --required-one x
    echo \"FORCE=\${CLIFT_FLAG_FORCE:-unset}\"
  "
  [[ "$output" == *"FORCE=true"* ]]
}

@test "parses short bool flag" {
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' -f -r x
    echo \"FORCE=\${CLIFT_FLAG_FORCE:-unset}\"
  "
  [[ "$output" == *"FORCE=true"* ]]
}

@test "parses long string with equals" {
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --target=prod --required-one x
    echo \"TARGET=\${CLIFT_FLAG_TARGET}\"
  "
  [[ "$output" == *"TARGET=prod"* ]]
}

@test "parses long string with space" {
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --target prod --required-one x
    echo \"TARGET=\${CLIFT_FLAG_TARGET}\"
  "
  [[ "$output" == *"TARGET=prod"* ]]
}

@test "parses short string with space" {
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' -t prod -r x
    echo \"TARGET=\${CLIFT_FLAG_TARGET}\"
  "
  [[ "$output" == *"TARGET=prod"* ]]
}

@test "applies string default when absent" {
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --required-one x
    echo \"TARGET=\${CLIFT_FLAG_TARGET}\"
  "
  [[ "$output" == *"TARGET=staging"* ]]
}

@test "parses int, including negative" {
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --count -5 --required-one x
    echo \"COUNT=\${CLIFT_FLAG_COUNT}\"
  "
  [[ "$output" == *"COUNT=-5"* ]]
}

@test "rejects int with non-numeric value" {
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --count abc --required-one x
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"integer"* ]]
}

@test "parses list flag as indexed env vars" {
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --tag=a --tag=b --tag=c --required-one x
    echo \"COUNT=\${CLIFT_FLAG_TAG_COUNT}\"
    echo \"T1=\${CLIFT_FLAG_TAG_1}\"
    echo \"T2=\${CLIFT_FLAG_TAG_2}\"
    echo \"T3=\${CLIFT_FLAG_TAG_3}\"
  "
  [[ "$output" == *"COUNT=3"* ]]
  [[ "$output" == *"T1=a"* ]]
  [[ "$output" == *"T2=b"* ]]
  [[ "$output" == *"T3=c"* ]]
}

@test "user-supplied list value REPLACES default, not appends" {
  cat > "$TEST_DIR/flags_with_default.json" <<'JSON'
[
  {"name": "tag", "type": "list", "default": "x,y"},
  {"name": "required-one", "short": "r", "type": "string", "required": true}
]
JSON
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags_with_default.json' --tag=a --required-one x
    echo \"COUNT=\${CLIFT_FLAG_TAG_COUNT}\"
    echo \"T1=\${CLIFT_FLAG_TAG_1}\"
    echo \"T2=\${CLIFT_FLAG_TAG_2:-unset}\"
  "
  [[ "$output" == *"COUNT=1"* ]]
  [[ "$output" == *"T1=a"* ]]
  [[ "$output" == *"T2=unset"* ]]
}

@test "list default applies when flag not passed" {
  cat > "$TEST_DIR/flags_with_default.json" <<'JSON'
[
  {"name": "tag", "type": "list", "default": "x,y"},
  {"name": "required-one", "short": "r", "type": "string", "required": true}
]
JSON
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags_with_default.json' --required-one x
    echo \"COUNT=\${CLIFT_FLAG_TAG_COUNT}\"
    echo \"T1=\${CLIFT_FLAG_TAG_1}\"
    echo \"T2=\${CLIFT_FLAG_TAG_2}\"
  "
  [[ "$output" == *"COUNT=2"* ]]
  [[ "$output" == *"T1=x"* ]]
  [[ "$output" == *"T2=y"* ]]
}

@test "flag value with spaces survives via CLIFT_ARG" {
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --target 'hello world' --required-one x
    echo \"TARGET=[\${CLIFT_FLAG_TARGET}]\"
  "
  [[ "$output" == *"TARGET=[hello world]"* ]]
}

@test "empty flag value --name= accepted" {
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --target= --required-one x
    echo \"TARGET=[\${CLIFT_FLAG_TARGET}]\"
  "
  [[ "$output" == *"TARGET=[]"* ]]
}

@test "positional args become CLIFT_POS_N" {
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --required-one x file1.txt file2.txt
    echo \"COUNT=\${CLIFT_POS_COUNT}\"
    echo \"P1=\${CLIFT_POS_1}\"
    echo \"P2=\${CLIFT_POS_2}\"
  "
  [[ "$output" == *"COUNT=2"* ]]
  [[ "$output" == *"P1=file1.txt"* ]]
  [[ "$output" == *"P2=file2.txt"* ]]
}

@test "-- ends flag parsing" {
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --required-one x -- --force notaflag
    echo \"FORCE=\${CLIFT_FLAG_FORCE:-unset}\"
    echo \"P1=\${CLIFT_POS_1}\"
    echo \"P2=\${CLIFT_POS_2}\"
  "
  [[ "$output" == *"FORCE=unset"* ]]
  [[ "$output" == *"P1=--force"* ]]
  [[ "$output" == *"P2=notaflag"* ]]
}

@test "short bool cluster all-bool" {
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' -fv -r x
    echo \"FORCE=\${CLIFT_FLAG_FORCE}\"
    echo \"VERBOSE=\${CLIFT_FLAG_VERBOSE}\"
  "
  [[ "$output" == *"FORCE=true"* ]]
  [[ "$output" == *"VERBOSE=true"* ]]
}

@test "short bool cluster with non-bool rejected" {
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' -fvt -r x
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"cluster"* ]]
}

@test "unknown flag error with did-you-mean" {
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --froce --required-one x
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown flag"* ]]
  [[ "$output" == *"force"* ]]
}

@test "missing required flag errors" {
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --force
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"required"* ]]
  [[ "$output" == *"required-one"* ]]
}

@test "missing value at end of argv errors" {
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --required-one
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"requires a value"* ]]
}

@test "short flag list accumulation: -t a -t b produces indexed vars" {
  cat > "$TEST_DIR/flags.json" <<'JSON'
[{"name":"tag","short":"t","type":"list"}]
JSON
  run bash -c "source '$FRAMEWORK_DIR/lib/flags/parser.sh'; clift_parse_args '$TEST_DIR/flags.json' -t a -t b; echo \"COUNT=\$CLIFT_FLAG_TAG_COUNT T1=\$CLIFT_FLAG_TAG_1 T2=\$CLIFT_FLAG_TAG_2\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"COUNT=2"* ]]
  [[ "$output" == *"T1=a"* ]]
  [[ "$output" == *"T2=b"* ]]
}

@test "short flag -t=a,b with list type splits on commas" {
  cat > "$TEST_DIR/flags.json" <<'JSON'
[{"name":"tag","short":"t","type":"list"}]
JSON
  run bash -c "source '$FRAMEWORK_DIR/lib/flags/parser.sh'; clift_parse_args '$TEST_DIR/flags.json' '-t=a,b'; echo \"COUNT=\$CLIFT_FLAG_TAG_COUNT T1=\$CLIFT_FLAG_TAG_1 T2=\$CLIFT_FLAG_TAG_2\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"COUNT=2"* ]]
  [[ "$output" == *"T1=a"* ]]
  [[ "$output" == *"T2=b"* ]]
}

@test "long flag --tag=a,b with list type splits on commas" {
  cat > "$TEST_DIR/flags.json" <<'JSON'
[{"name":"tag","short":"t","type":"list"}]
JSON
  run bash -c "source '$FRAMEWORK_DIR/lib/flags/parser.sh'; clift_parse_args '$TEST_DIR/flags.json' '--tag=a,b'; echo \"COUNT=\$CLIFT_FLAG_TAG_COUNT T1=\$CLIFT_FLAG_TAG_1 T2=\$CLIFT_FLAG_TAG_2\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"COUNT=2"* ]]
  [[ "$output" == *"T1=a"* ]]
  [[ "$output" == *"T2=b"* ]]
}

@test "flag value with shell metacharacters survives literally" {
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --target 'foo|bar;baz\$(pwd)' --required-one x
    echo \"TARGET=[\${CLIFT_FLAG_TARGET}]\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *'TARGET=[foo|bar;baz$(pwd)]'* ]]
}

@test "bool flag does not consume next positional as value" {
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --force --required-one x file.txt
    echo \"FORCE=\${CLIFT_FLAG_FORCE}\"
    echo \"P1=\${CLIFT_POS_1}\"
  "
  [[ "$output" == *"FORCE=true"* ]]
  [[ "$output" == *"P1=file.txt"* ]]
}

@test "bool flag with explicit =true and =false" {
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --force=true --verbose=false --required-one x
    echo \"FORCE=\${CLIFT_FLAG_FORCE}\"
    echo \"VERBOSE=\${CLIFT_FLAG_VERBOSE}\"
  "
  [[ "$output" == *"FORCE=true"* ]]
  [[ "$output" == *"VERBOSE=false"* ]]
}

@test "empty list default produces COUNT=0" {
  cat > "$TEST_DIR/flags_empty_list.json" <<'JSON'
[{"name": "tag", "type": "list", "default": ""}]
JSON
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags_empty_list.json'
    echo \"COUNT=\${CLIFT_FLAG_TAG_COUNT}\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"COUNT=0"* ]]
}

@test "multiple list flags accumulate across separate invocations" {
  cat > "$TEST_DIR/flags.json" <<'JSON'
[{"name":"tag","short":"t","type":"list"}]
JSON
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' --tag=a --tag=b --tag=c
    echo \"COUNT=\$CLIFT_FLAG_TAG_COUNT\"
    echo \"T1=\$CLIFT_FLAG_TAG_1\"
    echo \"T2=\$CLIFT_FLAG_TAG_2\"
    echo \"T3=\$CLIFT_FLAG_TAG_3\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"COUNT=3"* ]]
  [[ "$output" == *"T1=a"* ]]
  [[ "$output" == *"T2=b"* ]]
  [[ "$output" == *"T3=c"* ]]
}

@test "no flags and no positionals produces CLIFT_POS_COUNT=0" {
  cat > "$TEST_DIR/flags_optional.json" <<'JSON'
[{"name": "force", "type": "bool"}]
JSON
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags_optional.json'
    echo \"POS=\${CLIFT_POS_COUNT}\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"POS=0"* ]]
}

@test "short flag with equals -t=value" {
  run bash -c "
    source '$FRAMEWORK_DIR/lib/flags/parser.sh'
    clift_parse_args '$TEST_DIR/flags.json' -t=myhost -r x
    echo \"TARGET=\${CLIFT_FLAG_TARGET}\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"TARGET=myhost"* ]]
}
