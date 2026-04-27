#!/usr/bin/env bats
# Tests for examples/jarvis/lib/calendar/ics.sh — VEVENT block parsing,
# [since,until) window filter, file + URL sources, JSON escaping.

bats_require_minimum_version 1.5.0

load 'jarvis_helper'
load 'jarvis_shim_helper'

setup() {
  jarvis_common_setup
  shim_setup
  # shellcheck source=/dev/null
  source "${CLIFT_JARVIS_DIR}/lib/state/profile.sh"
  # shellcheck source=/dev/null
  source "${CLIFT_JARVIS_DIR}/lib/state/config.sh"
  # shellcheck source=/dev/null
  source "${CLIFT_JARVIS_DIR}/lib/calendar/provider.sh"
  # shellcheck source=/dev/null
  source "${CLIFT_JARVIS_DIR}/lib/calendar/ics.sh"
  state_ensure_tree
}

teardown() {
  jarvis_common_teardown
}

@test "ics registers itself + outlook-ics alias" {
  [[ -n "${_CALENDAR_PROVIDERS[ics]:-}" ]]
  [[ -n "${_CALENDAR_PROVIDERS[outlook-ics]:-}" ]]
}

@test "missing [calendar.ics] source -> exit 1" {
  printf '[calendar]\nprovider = "ics"\n' > "$JARVIS_HOME/test/config.toml"
  run calendar_ics_events "2026-05-01T00:00:00Z" "2026-05-02T00:00:00Z" test
  [ "$status" -eq 1 ]
}

@test "ics file path -> 2 events in window" {
  cp "${BATS_TEST_DIRNAME}/fixtures/calendar.ics" "$JARVIS_HOME/test/cal.ics"
  printf '[calendar]\nprovider = "ics"\n[calendar.ics]\nsource = "%s"\n' \
    "$JARVIS_HOME/test/cal.ics" > "$JARVIS_HOME/test/config.toml"
  run calendar_ics_events "2026-05-01T00:00:00Z" "2026-05-02T00:00:00Z" test
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l)" -eq 2 ]
  printf '%s\n' "$output" | head -1 | jq -e '.title == "standup" and .url == "https://zoom.us/j/123"' > /dev/null
}

@test "ics URL -> fetched via curl shim" {
  cp "${BATS_TEST_DIRNAME}/fixtures/calendar.ics" "$SHIM_DIR/feed.ics"
  shim_install curl 'cat "'"$SHIM_DIR"'/feed.ics"; exit 0'
  printf '[calendar]\nprovider = "ics"\n[calendar.ics]\nsource = "https://example.com/feed.ics"\n' \
    > "$JARVIS_HOME/test/config.toml"
  run calendar_ics_events "2026-05-01T00:00:00Z" "2026-05-02T00:00:00Z" test
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l)" -eq 2 ]
}

@test "events outside window are filtered out" {
  cp "${BATS_TEST_DIRNAME}/fixtures/calendar.ics" "$JARVIS_HOME/test/cal.ics"
  printf '[calendar]\nprovider = "ics"\n[calendar.ics]\nsource = "%s"\n' \
    "$JARVIS_HOME/test/cal.ics" > "$JARVIS_HOME/test/config.toml"
  run calendar_ics_events "2026-04-01T00:00:00Z" "2026-04-02T00:00:00Z" test
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l)" -eq 1 ]
  printf '%s\n' "$output" | jq -e '.title == "past event"' > /dev/null
}

@test "ics title with quotes is JSON-escaped" {
  cat > "$JARVIS_HOME/test/cal.ics" <<'EOF'
BEGIN:VCALENDAR
BEGIN:VEVENT
DTSTART:20260501T100000Z
DTEND:20260501T103000Z
SUMMARY:Sam's "1:1" review
URL:https://example/meet
END:VEVENT
END:VCALENDAR
EOF
  printf '[calendar]\nprovider = "ics"\n[calendar.ics]\nsource = "%s"\n' \
    "$JARVIS_HOME/test/cal.ics" > "$JARVIS_HOME/test/config.toml"
  run calendar_ics_events "2026-05-01T00:00:00Z" "2026-05-02T00:00:00Z" test
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.title == "Sam'\''s \"1:1\" review"' > /dev/null
}
