#!/usr/bin/env bats
# Task 3.2 — help_list + help_detail override slots.
#
# Exercises the override dispatch wired into lib/help/list.sh and
# lib/help/detail.sh. Invokes the scripts directly (same path as the
# `_help:list` / `_help:detail` tasks that the router + wrapper use) after
# dropping override files into the two tiers.

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  common_setup
  create_test_cli "greet" "- {name: who, short: w, type: string, default: world, desc: 'Who to greet'}"
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR" >/dev/null 2>&1 || true
}

teardown() {
  common_teardown
}

# --- help_list ---------------------------------------------------------------

@test "help_list override wraps default (banner + default + footer)" {
  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/help_list.sh" <<'SH'
clift_override_help_list() {
  echo "===BANNER==="
  "$1" "${@:2}"
  echo "===FOOTER==="
}
SH

  run bash "$FRAMEWORK_DIR/lib/help/list.sh" "$CLI_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"===BANNER==="* ]]
  [[ "$output" == *"===FOOTER==="* ]]
  # Default content still renders — "version" header from the default impl.
  [[ "$output" == *"$CLI_NAME - version"* ]]
  # Banner precedes footer (wrap order).
  banner_line="$(printf '%s\n' "$output" | grep -n '===BANNER===' | head -1 | cut -d: -f1)"
  footer_line="$(printf '%s\n' "$output" | grep -n '===FOOTER===' | head -1 | cut -d: -f1)"
  [ "$banner_line" -lt "$footer_line" ]
}

@test "help_list override replaces default (default content absent)" {
  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/help_list.sh" <<'SH'
clift_override_help_list() {
  echo "CUSTOM_HELP_ONLY"
  # Deliberately does NOT invoke "$1" — full replacement.
}
SH

  run bash "$FRAMEWORK_DIR/lib/help/list.sh" "$CLI_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CUSTOM_HELP_ONLY"* ]]
  # Default header / footer hints are absent.
  [[ "$output" != *"$CLI_NAME - version"* ]]
  [[ "$output" != *"for details on a command"* ]]
}

# --- help_detail -------------------------------------------------------------

@test "help_detail per-command override runs for that command" {
  mkdir -p "$CLI_DIR/cmds/greet/overrides"
  cat > "$CLI_DIR/cmds/greet/overrides/help_detail.sh" <<'SH'
clift_override_help_detail() {
  # $2 is the task name, $3 is CLI_DIR (per callback contract).
  echo "PER_CMD_DETAIL:$2"
}
SH

  run bash "$FRAMEWORK_DIR/lib/help/detail.sh" "greet" "$CLI_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PER_CMD_DETAIL:greet"* ]]
  # Default detail output (flag section headers) must be absent.
  [[ "$output" != *"Global Flags:"* ]]
}

@test "help_detail CLI-global override runs when no per-command override" {
  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/help_detail.sh" <<'SH'
clift_override_help_detail() {
  echo "GLOBAL_DETAIL:$2"
}
SH

  run bash "$FRAMEWORK_DIR/lib/help/detail.sh" "greet" "$CLI_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"GLOBAL_DETAIL:greet"* ]]
  [[ "$output" != *"Global Flags:"* ]]
}

@test "help_detail per-command takes precedence over CLI-global" {
  mkdir -p "$CLI_DIR/.clift/overrides"
  mkdir -p "$CLI_DIR/cmds/greet/overrides"
  cat > "$CLI_DIR/.clift/overrides/help_detail.sh" <<'SH'
clift_override_help_detail() {
  echo "GLOBAL_DETAIL"
}
SH
  cat > "$CLI_DIR/cmds/greet/overrides/help_detail.sh" <<'SH'
clift_override_help_detail() {
  echo "PER_CMD_DETAIL"
}
SH

  run bash "$FRAMEWORK_DIR/lib/help/detail.sh" "greet" "$CLI_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PER_CMD_DETAIL"* ]]
  [[ "$output" != *"GLOBAL_DETAIL"* ]]
}

@test "help_detail override can wrap default via \$1" {
  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/help_detail.sh" <<'SH'
clift_override_help_detail() {
  echo "=== detail-before ==="
  "$1" "${@:2}"
  echo "=== detail-after ==="
}
SH

  run bash "$FRAMEWORK_DIR/lib/help/detail.sh" "greet" "$CLI_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"=== detail-before ==="* ]]
  [[ "$output" == *"=== detail-after ==="* ]]
  # Default flag table still renders.
  [[ "$output" == *"--who"* ]]
}

# --- baseline ----------------------------------------------------------------

@test "no override: default help_list and help_detail render normally" {
  run bash "$FRAMEWORK_DIR/lib/help/list.sh" "$CLI_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$CLI_NAME - version"* ]]
  [[ "$output" == *"greet"* ]]

  run bash "$FRAMEWORK_DIR/lib/help/detail.sh" "greet" "$CLI_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$CLI_NAME greet"* ]]
  [[ "$output" == *"--who"* ]]
}
