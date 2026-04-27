#!/usr/bin/env bats
# T13 — standup --join / --meeting wiring.
# --join: scan calendar [now, now+15min); first /standup/i match; URL precedence
#   .url field > meeting_url_extract on title. open|xdg-open with stdout fallback.
# --meeting URL: bypass calendar, open URL directly.
# Always renders the normal Yesterday/Today/Blockers summary afterward.

bats_require_minimum_version 1.5.0

load 'jarvis_helper'
load 'jarvis_shim_helper'

setup() {
  jarvis_common_setup
  shim_setup
  cp -R "${BATS_TEST_DIRNAME}/fixtures/status-profile" "$JARVIS_HOME/test"
  cp "${BATS_TEST_DIRNAME}/fixtures/calendar.ics" "$JARVIS_HOME/test/cal.ics"
  cat >> "$JARVIS_HOME/test/config.toml" <<EOF

[calendar]
provider = "ics"
[calendar.ics]
source = "$JARVIS_HOME/test/cal.ics"
EOF
  shim_install open     'echo "open: $1" > "$0.log"; exit 0'
  shim_install xdg-open 'echo "xdg-open: $1" > "$0.log"; exit 0'
  mkdir -p "$JARVIS_HOME/test/notes"
  echo '{"version":1,"notes":[]}' > "$JARVIS_HOME/test/notes/index.json"
  # 10 min before standup at 10:00 — within the 15-min lookahead window.
  export JARVIS_FAKE_NOW="2026-05-01T09:50:00Z"
}

teardown() { jarvis_common_teardown; }

@test "standup --join finds standup event and opens its URL" {
  run bash "${CLIFT_JARVIS_DIR}/cmds/standup/standup.sh" --join --profile test
  [ "$status" -eq 0 ]
  [ -f "$(shim_log_path open)" ]
  grep -q "https://zoom.us/j/123" "$(shim_log_path open)"
  [[ "$output" == *"Yesterday"* ]]
}

@test "standup --meeting URL bypasses calendar" {
  rm -f "$JARVIS_HOME/test/cal.ics"
  run bash "${CLIFT_JARVIS_DIR}/cmds/standup/standup.sh" \
    --meeting "https://meet.google.com/xyz-abcd-efg" --profile test
  [ "$status" -eq 0 ]
  [ -f "$(shim_log_path open)" ]
  grep -q "https://meet.google.com/xyz-abcd-efg" "$(shim_log_path open)"
}

@test "standup --join with no standup event prints note + summary" {
  export JARVIS_FAKE_NOW="2026-05-01T22:00:00Z"
  run bash "${CLIFT_JARVIS_DIR}/cmds/standup/standup.sh" --join --profile test
  [ "$status" -eq 0 ]
  [[ "$output" == *"no standup event"* ]]
  [ ! -f "$(shim_log_path open)" ]
}

@test "no open/xdg-open available -> URL printed to stdout" {
  rm -f "$SHIM_DIR/open" "$SHIM_DIR/xdg-open"
  run bash "${CLIFT_JARVIS_DIR}/cmds/standup/standup.sh" \
    --meeting "https://zoom.us/j/777" --profile test
  [ "$status" -eq 0 ]
  [[ "$output" == *"https://zoom.us/j/777"* ]]
}
