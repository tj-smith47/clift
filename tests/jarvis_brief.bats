#!/usr/bin/env bats
# brief: real-data sections + --short snapshot.
# Sections gate on lib output; --short emits a frozen one-liner.

bats_require_minimum_version 1.5.0

load 'jarvis_helper'
load 'jarvis_shim_helper'

setup() {
  jarvis_common_setup
  shim_setup
  cp -R "${BATS_TEST_DIRNAME}/fixtures/status-profile" "$JARVIS_HOME/test"
  # Augment the fixture profile with an oncall block + ICS calendar source
  # so brief has every section to render. status-profile/config.toml already
  # carries [jira]; we append rather than rewrite.
  cat >> "$JARVIS_HOME/test/config.toml" <<EOF

[oncall]
primary = "alex"
secondary = "you"
pager = "quiet"

[calendar]
provider = "ics"

[calendar.ics]
source = "$JARVIS_HOME/test/cal.ics"
EOF
  cp "${BATS_TEST_DIRNAME}/fixtures/calendar.ics" "$JARVIS_HOME/test/cal.ics"
  cat > "$JARVIS_HOME/test/deploys.log" <<EOF
2026-05-01T13:00:00Z	api	v1.12.3	ok
2026-05-01T08:00:00Z	web	v0.47.1	ok
EOF
  shim_install gh '
case "$1" in
  pr) cat <<EOF2
[{"number":482,"title":"feat(router): persistent flags","url":"https://github.com/org/repo/pull/482","headRepository":{"name":"repo","owner":{"login":"org"}}}]
EOF2
   exit 0 ;;
esac'
  export JARVIS_FAKE_NOW="2026-05-01T15:00:00Z"
}

teardown() {
  jarvis_common_teardown
}

@test "brief shows all sections when configured" {
  run bash "${CLIFT_JARVIS_DIR}/cmds/brief/brief.sh" --profile test
  [ "$status" -eq 0 ]
  [[ "$output" == *"Calendar"* ]]
  [[ "$output" == *"PRs"* ]]
  [[ "$output" == *"Deploys"* ]]
  [[ "$output" == *"Oncall"* ]]
  [[ "$output" == *"alex"* ]]
  [[ "$output" == *"v1.12.3"* ]]
  [[ "$output" == *"#482"* ]]
}

@test "brief --short matches snapshot byte-for-byte" {
  run bash "${CLIFT_JARVIS_DIR}/cmds/brief/brief.sh" --short --profile test
  [ "$status" -eq 0 ]
  diff <(printf '%s\n' "$output") "${BATS_TEST_DIRNAME}/fixtures/brief-short.txt"
}

@test "brief --skip-calendar hides Calendar but keeps others" {
  run bash "${CLIFT_JARVIS_DIR}/cmds/brief/brief.sh" --skip-calendar --profile test
  [ "$status" -eq 0 ]
  [[ "$output" != *"Calendar"* ]]
  [[ "$output" == *"PRs"* ]]
  [[ "$output" == *"Deploys"* ]]
}

@test "missing gh hides PRs section" {
  rm -f "$SHIM_DIR/gh"
  run bash "${CLIFT_JARVIS_DIR}/cmds/brief/brief.sh" --profile test
  [ "$status" -eq 0 ]
  [[ "$output" != *"PRs awaiting"* ]]
}

@test "calendar cache populated after first brief run" {
  bash "${CLIFT_JARVIS_DIR}/cmds/brief/brief.sh" --profile test > /dev/null
  bash "${CLIFT_JARVIS_DIR}/cmds/brief/brief.sh" --profile test > /dev/null
  [ -f "$JARVIS_HOME/test/cache/calendar.json" ]
}
