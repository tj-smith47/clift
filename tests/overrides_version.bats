#!/usr/bin/env bats
# Task 3.3 — version_print override slot.
#
# Exercises the override dispatch wired into:
#   - lib/wrapper/wrapper.sh.tmpl   (standard-mode `mycli --version|-V`)
#   - lib/router/router.sh          (mid-command `mycli <cmd> --version`)
#   - lib/version/version.sh        (framework `mycli version` subcommand)

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  common_setup
  create_test_cli "greet" "- {name: who, short: w, type: string, default: world, desc: 'Who to greet'}"
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR" >/dev/null 2>&1 || true
  build_test_wrapper
}

teardown() {
  common_teardown
}

# --- wrapper-path --version --------------------------------------------------

@test "version_print override replaces default --version output" {
  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/version_print.sh" <<'SH'
clift_override_version_print() {
  # $1 default_fn, $2 CLI_NAME, $3 CLI_VERSION, $4 CLI_DIR — ignore default.
  echo "${2} ${3} (build: abc123)"
}
SH

  run "$CLI_DIR/bin/$CLI_NAME" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"$CLI_NAME $CLI_VERSION (build: abc123)"* ]]
  # Default "<name> version <version>" line MUST be absent.
  [[ "$output" != *"$CLI_NAME version $CLI_VERSION"* ]]
}

@test "default --version output unchanged when no override" {
  run "$CLI_DIR/bin/$CLI_NAME" --version
  [ "$status" -eq 0 ]
  [[ "$output" == "$CLI_NAME version $CLI_VERSION" ]]
}

@test "version_print wrap pattern: user calls default then appends" {
  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/version_print.sh" <<'SH'
clift_override_version_print() {
  local default_fn="$1"; shift
  "$default_fn" "$@"
  echo "build: abc123"
}
SH

  run "$CLI_DIR/bin/$CLI_NAME" --version
  [ "$status" -eq 0 ]
  # Both the standard line AND the extra appear, in order.
  [[ "$output" == *"$CLI_NAME version $CLI_VERSION"* ]]
  [[ "$output" == *"build: abc123"* ]]
  default_line="$(printf '%s\n' "$output" | grep -n "$CLI_NAME version" | head -1 | cut -d: -f1)"
  extra_line="$(printf '%s\n' "$output" | grep -n 'build: abc123' | head -1 | cut -d: -f1)"
  [ "$default_line" -lt "$extra_line" ]
}

# --- version subcommand (lib/version/version.sh) -----------------------------

@test "version_print override applies to mycli version subcommand too" {
  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/version_print.sh" <<'SH'
clift_override_version_print() {
  echo "${2}-subcmd-${3}"
}
SH

  run bash "$FRAMEWORK_DIR/lib/version/version.sh" "$CLI_DIR" "$FRAMEWORK_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"${CLI_NAME}-subcmd-${CLI_VERSION}"* ]]
  # Default line is absent.
  [[ "$output" != *"$CLI_NAME version $CLI_VERSION"* ]]
}

# --- router-path mid-command --version ---------------------------------------

@test "version override applies when router intercept fires (fixture-driven)" {
  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/version_print.sh" <<'SH'
clift_override_version_print() {
  echo "ROUTER-OVERRIDE:${2}:${3}"
}
SH

  # Drives the router intercept block directly via CLIFT_FLAG_VERSION=true,
  # bypassing the parser. Locks intercept-block behaviour without a full task
  # fixture; see the next test for end-to-end coverage through the wrapper.
  CLIFT_FLAG_VERSION=true CLIFT_ARG_COUNT=0 \
    run bash "$FRAMEWORK_DIR/lib/router/router.sh" "greet"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ROUTER-OVERRIDE:${CLI_NAME}:${CLI_VERSION}"* ]]
  [[ "$output" != *"$CLI_NAME version $CLI_VERSION"* ]]
}

@test "version_print override applies end-to-end via mycli <cmd> --version" {
  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/version_print.sh" <<'SH'
clift_override_version_print() {
  echo "E2E-OVERRIDE:${2}:${3}"
}
SH

  # Real wrapper invocation: argv flows wrapper -> task -> router -> parser,
  # parser sets CLIFT_FLAG_VERSION=true from the merged globals, router
  # intercept fires the override.
  run "$CLI_DIR/bin/$CLI_NAME" greet --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"E2E-OVERRIDE:${CLI_NAME}:${CLI_VERSION}"* ]]
  [[ "$output" != *"$CLI_NAME version $CLI_VERSION"* ]]
}
