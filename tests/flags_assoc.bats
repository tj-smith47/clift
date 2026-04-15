#!/usr/bin/env bats
# Task 2.2 — CLIFT_FLAGS assoc array (Cobra-style ergonomics).
#
# User scripts can read parsed flags via `${CLIFT_FLAGS[name]}` (dash-preserving
# keys) in addition to the legacy `CLIFT_FLAG_<UPPER_NAME>` env vars. The array
# is built by the runtime prelude from a NUL-separated tempfile the parser
# writes at the end of parse; the router's EXIT trap cleans the tempfile.

bats_require_minimum_version 1.5.0

load test_helper

# Build a single-command CLI whose script dumps state to stdout so assertions
# can inspect both the assoc array and the legacy env vars.
_build_cli() {
  local flags_yaml="$1" script_body="$2"

  create_test_cli sub "$flags_yaml"

  cat > "$CLI_DIR/cmds/sub/sub.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
${script_body}
SCRIPT
  chmod +x "$CLI_DIR/cmds/sub/sub.sh"

  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
}

@test "CLIFT_FLAGS[name] exposes string flag value" {
  _build_cli \
    '- {name: target, type: string, default: staging}' \
    'echo "target=${CLIFT_FLAGS[target]}"'

  CLIFT_ARG_COUNT=1 CLIFT_ARG_1=--target=prod \
    run bash "$FRAMEWORK_DIR/lib/router/router.sh" sub
  [ "$status" -eq 0 ]
  [[ "$output" == *"target=prod"* ]]
}

@test "CLIFT_FLAGS[name] exposes bool flag as 'true' when set" {
  _build_cli \
    '- {name: force, short: f, type: bool}' \
    'echo "force=${CLIFT_FLAGS[force]:-UNSET}"'

  CLIFT_ARG_COUNT=1 CLIFT_ARG_1=--force \
    run bash "$FRAMEWORK_DIR/lib/router/router.sh" sub
  [ "$status" -eq 0 ]
  [[ "$output" == *"force=true"* ]]
}

@test "CLIFT_FLAGS[name] is absent for bool flag that was not set" {
  _build_cli \
    '- {name: force, short: f, type: bool}' \
    'if [[ -v CLIFT_FLAGS[force] ]]; then echo "present"; else echo "absent"; fi'

  CLIFT_ARG_COUNT=0 \
    run bash "$FRAMEWORK_DIR/lib/router/router.sh" sub
  [ "$status" -eq 0 ]
  [[ "$output" == *"absent"* ]]
}

@test "CLIFT_FLAGS preserves dashes in flag names (dry-run not DRY_RUN)" {
  _build_cli \
    '- {name: dry-run, type: bool}' \
    'echo "dash=${CLIFT_FLAGS[dry-run]:-UNSET}"; echo "under=${CLIFT_FLAGS[DRY_RUN]:-UNSET}"'

  CLIFT_ARG_COUNT=1 CLIFT_ARG_1=--dry-run \
    run bash "$FRAMEWORK_DIR/lib/router/router.sh" sub
  [ "$status" -eq 0 ]
  [[ "$output" == *"dash=true"* ]]
  [[ "$output" == *"under=UNSET"* ]]
}

@test "CLIFT_FLAGS for list flags is a comma-joined value" {
  _build_cli \
    '- {name: tag, type: list}' \
    'echo "tag=${CLIFT_FLAGS[tag]:-UNSET}"'

  CLIFT_ARG_COUNT=2 CLIFT_ARG_1=--tag=a CLIFT_ARG_2=--tag=b,c \
    run bash "$FRAMEWORK_DIR/lib/router/router.sh" sub
  [ "$status" -eq 0 ]
  [[ "$output" == *"tag=a,b,c"* ]]
}

@test "per-element CLIFT_FLAG_<NAME>_N env vars still work (back-compat)" {
  _build_cli \
    '- {name: tag, type: list}' \
    'echo "count=${CLIFT_FLAG_TAG_COUNT}"; echo "one=${CLIFT_FLAG_TAG_1}"; echo "two=${CLIFT_FLAG_TAG_2}"; echo "three=${CLIFT_FLAG_TAG_3}"'

  CLIFT_ARG_COUNT=2 CLIFT_ARG_1=--tag=a CLIFT_ARG_2=--tag=b,c \
    run bash "$FRAMEWORK_DIR/lib/router/router.sh" sub
  [ "$status" -eq 0 ]
  [[ "$output" == *"count=3"* ]]
  [[ "$output" == *"one=a"* ]]
  [[ "$output" == *"two=b"* ]]
  [[ "$output" == *"three=c"* ]]
}

@test "legacy CLIFT_FLAG_<UPPER> env vars coexist with CLIFT_FLAGS" {
  _build_cli \
    '- {name: dry-run, type: bool}' \
    'echo "arr=${CLIFT_FLAGS[dry-run]:-UNSET}"; echo "env=${CLIFT_FLAG_DRY_RUN:-UNSET}"'

  CLIFT_ARG_COUNT=1 CLIFT_ARG_1=--dry-run \
    run bash "$FRAMEWORK_DIR/lib/router/router.sh" sub
  [ "$status" -eq 0 ]
  [[ "$output" == *"arr=true"* ]]
  [[ "$output" == *"env=true"* ]]
}

@test "persistent flags appear in CLIFT_FLAGS under the declared name" {
  # Build root with PERSISTENT_FLAGS block injected (pattern from flags_persistent.bats).
  CLIFT_TEST_PERSISTENT_BLOCK='  PERSISTENT_FLAGS:
    - {name: profile, short: p, type: string, default: "default", desc: "Profile name"}' \
    create_test_cli deploy

  cat > "$CLI_DIR/cmds/deploy/deploy.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
echo "profile=${CLIFT_FLAGS[profile]:-UNSET}"
SCRIPT
  chmod +x "$CLI_DIR/cmds/deploy/deploy.sh"

  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"

  CLIFT_ARG_COUNT=1 CLIFT_ARG_1=--profile=staging \
    run bash "$FRAMEWORK_DIR/lib/router/router.sh" deploy
  [ "$status" -eq 0 ]
  [[ "$output" == *"profile=staging"* ]]
}

@test "CLIFT_FLAGS_FILE is unset before user script body runs (prelude cleans up)" {
  # The prelude reads the tempfile, unlinks it, AND unsets CLIFT_FLAGS_FILE so
  # subshells never see a dangling path. User scripts access parsed flags via
  # the CLIFT_FLAGS assoc array, not by re-reading the file. Cleanup is eager
  # so it survives the router's exec-into-exec.sh jump (which would otherwise
  # skip the router's EXIT trap).
  _build_cli \
    '- {name: target, type: string, default: x}' \
    'if [[ -v CLIFT_FLAGS_FILE ]]; then echo "envvar=set:${CLIFT_FLAGS_FILE}"; else echo "envvar=unset"; fi; echo "target=${CLIFT_FLAGS[target]:-UNSET}"'

  CLIFT_ARG_COUNT=1 CLIFT_ARG_1=--target=y \
    run bash "$FRAMEWORK_DIR/lib/router/router.sh" sub
  [ "$status" -eq 0 ]
  [[ "$output" == *"envvar=unset"* ]]
  [[ "$output" == *"target=y"* ]]
}

@test "router cleans up parser tempfile even when parse fails" {
  # M3: belt-and-suspenders — router's EXIT trap must remove CLIFT_FLAGS_FILE
  # on the failure path where the parser exits early (unknown flag) and
  # never reaches the prelude's eager unlink.
  _build_cli \
    '- {name: target, type: string}' \
    'echo "should-not-run"'

  # Point TMPDIR at an isolated dir so we can detect any leftover tmp files
  # without interference from other tests.
  local probe_tmpdir="$TEST_DIR/m3_tmpdir"
  mkdir -p "$probe_tmpdir"

  TMPDIR="$probe_tmpdir" CLIFT_ARG_COUNT=1 CLIFT_ARG_1=--bogus-flag \
    run bash "$FRAMEWORK_DIR/lib/router/router.sh" sub
  [ "$status" -ne 0 ]

  # No leftover tempfiles from the parser emit path in the isolated TMPDIR.
  # (The cache under $CLI_DIR/.clift/ is separate and not placed in TMPDIR.)
  shopt -s nullglob
  local leftovers=("$probe_tmpdir"/tmp.*)
  shopt -u nullglob
  [ "${#leftovers[@]}" -eq 0 ]
}

@test "concurrent invocations see distinct CLIFT_FLAGS_FILE paths" {
  # M4: mktemp uniqueness — two invocations run back-to-back (and in the
  # background) must each observe their own tempfile path. The prelude dumps
  # the path before cleanup via a debug trap; we just assert the CLIFT_FLAGS
  # assoc array ends up with the value each invocation supplied.
  _build_cli \
    '- {name: target, type: string, default: d}' \
    'echo "pid=$$ target=${CLIFT_FLAGS[target]}"'

  local out1="$TEST_DIR/m4.out1" out2="$TEST_DIR/m4.out2"

  CLIFT_ARG_COUNT=1 CLIFT_ARG_1=--target=one \
    bash "$FRAMEWORK_DIR/lib/router/router.sh" sub >"$out1" 2>&1 &
  local pid1=$!

  CLIFT_ARG_COUNT=1 CLIFT_ARG_1=--target=two \
    bash "$FRAMEWORK_DIR/lib/router/router.sh" sub >"$out2" 2>&1 &
  local pid2=$!

  wait "$pid1"
  wait "$pid2"

  grep -q "target=one" "$out1"
  grep -q "target=two" "$out2"
  # Each invocation saw its own flag value — mktemp-per-invocation is sound.
}

@test "CLIFT_FLAGS defaults populate even when no user value is supplied" {
  _build_cli \
    '- {name: target, type: string, default: staging}' \
    'echo "target=${CLIFT_FLAGS[target]:-UNSET}"'

  CLIFT_ARG_COUNT=0 \
    run bash "$FRAMEWORK_DIR/lib/router/router.sh" sub
  [ "$status" -eq 0 ]
  [[ "$output" == *"target=staging"* ]]
}
