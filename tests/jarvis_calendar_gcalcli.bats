#!/usr/bin/env bats
# Tests for examples/jarvis/lib/calendar/gcalcli.sh — TSV agenda → NDJSON
# event mapping. Uses PATH-shimmed `gcalcli` so no real binary is invoked.

bats_require_minimum_version 1.5.0

load 'jarvis_helper'
load 'jarvis_shim_helper'

setup() {
  jarvis_common_setup
  shim_setup
  # shellcheck source=/dev/null
  source "${CLIFT_JARVIS_DIR}/lib/calendar/provider.sh"
  # shellcheck source=/dev/null
  source "${CLIFT_JARVIS_DIR}/lib/calendar/gcalcli.sh"
}

teardown() {
  jarvis_common_teardown
}

@test "gcalcli registers itself" {
  [[ -n "${_CALENDAR_PROVIDERS[gcalcli]:-}" ]]
}

@test "missing gcalcli binary -> exit 1" {
  PATH="$SHIM_DIR" run calendar_gcalcli_events "2026-05-01T00:00:00Z" "2026-05-02T00:00:00Z" test
  [ "$status" -eq 1 ]
}

@test "gcalcli TSV -> NDJSON one row per event" {
  shim_install gcalcli 'cat <<EOF
2026-05-01	10:00	2026-05-01	10:30	https://meet.google.com/abc-defg	standup
2026-05-01	13:30	2026-05-01	14:00	https://zoom.us/j/123	1:1 with sam
EOF
exit 0'
  run calendar_gcalcli_events "2026-05-01T00:00:00Z" "2026-05-02T00:00:00Z" test
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l)" -ge 1 ]
  printf '%s\n' "$output" | head -1 | jq -e '.start == "2026-05-01T10:00:00" and .title == "standup"' > /dev/null
  printf '%s\n' "$output" | sed -n 2p | jq -e '.url == "https://zoom.us/j/123"' > /dev/null
}

@test "gcalcli nonzero exit -> exit 1" {
  shim_install gcalcli 'echo "auth error" >&2; exit 2'
  run calendar_gcalcli_events "2026-05-01T00:00:00Z" "2026-05-02T00:00:00Z" test
  [ "$status" -eq 1 ]
}

@test "empty gcalcli output -> exit 0 empty" {
  shim_install gcalcli 'exit 0'
  run calendar_gcalcli_events "2026-05-01T00:00:00Z" "2026-05-02T00:00:00Z" test
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
