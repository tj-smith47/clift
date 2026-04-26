#!/usr/bin/env bats
# T8 tests — one-shot tick path. Recurring + multi-profile come in T9.

bats_require_minimum_version 1.5.0

load 'jarvis_helper.bash'
load 'jarvis_shim_helper.bash'

setup() {
  jarvis_common_setup
  shim_setup
  for f in state/profile state/lock state/json state/ndjson state/config \
           remind/parse remind/schedule remind/schema \
           notify/registry notify/local notify/gotify notify/slack \
           notify/dispatch remind/tick; do
    # shellcheck source=/dev/null
    source "${CLIFT_JARVIS_DIR}/lib/$f.sh"
  done
  state_ensure_tree
}

teardown() {
  jarvis_common_teardown
}

# Build a one-shot reminder JSON; defaults are due-now in fake-time.
_one_shot_reminder() {
  local slug="$1" via_json="${2:-[\"local\"]}" trigger="${3:-2026-04-26T14:30:00Z}"
  jq -nc \
    --arg slug "$slug" --arg message "$slug-msg" \
    --arg profile "test" --arg trigger_at "$trigger" \
    --argjson via "$via_json" --arg created "2026-04-26T14:00:00Z" \
    '{slug:$slug, message:$message, profile:$profile,
      trigger_at:$trigger_at, via:$via, status:"pending",
      repeat:null, anchor_at:null, until:null, count_remaining:null,
      created_at:$created, fire_count:0, last_fired_at:null}'
}

_seed() {
  local slug="$1" via_json="${2:-[\"local\"]}" trigger="${3:-2026-04-26T14:30:00Z}"
  local blob; blob="$(_one_shot_reminder "$slug" "$via_json" "$trigger")"
  remind_schema_create "$slug" "$blob" >/dev/null
}

# ---------- one-shot fire happy path ----------

@test "due one-shot pending fires → status=delivered, fire_count=1" {
  _seed ping
  export JARVIS_FAKE_NOW="2026-04-26T14:35:00Z"
  export JARVIS_NOTIFY_DRYRUN=1
  remind_tick_run
  payload="$(cat "$JARVIS_HOME/test/reminders/ping.json")"
  [ "$(jq -r '.status' <<< "$payload")" = "delivered" ]
  [ "$(jq -r '.fire_count' <<< "$payload")" = "1" ]
  [ "$(jq -r '.last_fired_at' <<< "$payload")" = "2026-04-26T14:35:00Z" ]
}

@test "fire writes a delivery NDJSON row keyed by slug" {
  _seed ping
  export JARVIS_FAKE_NOW="2026-04-26T14:35:00Z"
  export JARVIS_NOTIFY_DRYRUN=1
  remind_tick_run
  log="$JARVIS_HOME/test/reminders.delivery.log"
  [ -f "$log" ]
  # First row is the heartbeat; the fire row(s) follow.
  fire_rows="$(jq -c 'select(.slug == "ping")' < "$log" | wc -l)"
  [ "$fire_rows" -ge 1 ]
}

@test "every tick run appends a tick.heartbeat row" {
  _seed ping
  export JARVIS_FAKE_NOW="2026-04-26T14:35:00Z"
  export JARVIS_NOTIFY_DRYRUN=1
  remind_tick_run
  log="$JARVIS_HOME/test/reminders.delivery.log"
  hb_count="$(jq -c 'select(.kind == "tick.heartbeat")' < "$log" | wc -l)"
  [ "$hb_count" = "1" ]
}

@test "heartbeat fires even when nothing else does" {
  # Empty profile (no reminders) still gets a heartbeat.
  export JARVIS_FAKE_NOW="2026-04-26T14:35:00Z"
  remind_tick_run
  log="$JARVIS_HOME/test/reminders.delivery.log"
  [ -f "$log" ]
  hb_count="$(jq -c 'select(.kind == "tick.heartbeat")' < "$log" | wc -l)"
  [ "$hb_count" = "1" ]
}

# ---------- not-due / wrong-status ----------

@test "not-yet-due reminder is unchanged" {
  _seed ping '["local"]' "2026-04-26T15:00:00Z"
  export JARVIS_FAKE_NOW="2026-04-26T14:30:00Z"   # before trigger
  export JARVIS_NOTIFY_DRYRUN=1
  remind_tick_run
  payload="$(cat "$JARVIS_HOME/test/reminders/ping.json")"
  [ "$(jq -r '.status' <<< "$payload")" = "pending" ]
  [ "$(jq -r '.fire_count' <<< "$payload")" = "0" ]
}

@test "already-delivered reminder not re-fired" {
  _seed ping
  payload="$(cat "$JARVIS_HOME/test/reminders/ping.json" \
              | jq -c '.status = "delivered" | .fire_count = 1')"
  remind_schema_save ping "$payload" >/dev/null
  export JARVIS_FAKE_NOW="2026-04-26T14:35:00Z"
  export JARVIS_NOTIFY_DRYRUN=1
  remind_tick_run
  fc="$(jq -r '.fire_count' < "$JARVIS_HOME/test/reminders/ping.json")"
  [ "$fc" = "1" ]   # still 1, didn't bump
}

# ---------- failure path ----------

@test "all channels fail → status=failed, delivery row ok=false" {
  _seed ping '["gotify"]'
  cat > "$JARVIS_HOME/test/config.toml" <<'EOF'
[notify.gotify]
url = "https://gotify.example"
token = "tok"
EOF
  shim_install curl 'echo "boom" >&2; exit 7'
  export JARVIS_FAKE_NOW="2026-04-26T14:35:00Z"
  remind_tick_run
  payload="$(cat "$JARVIS_HOME/test/reminders/ping.json")"
  [ "$(jq -r '.status' <<< "$payload")" = "failed" ]
  [ "$(jq -r '.fire_count' <<< "$payload")" = "1" ]
  log="$JARVIS_HOME/test/reminders.delivery.log"
  fail_rows="$(jq -c 'select(.slug == "ping" and .ok == false)' < "$log" | wc -l)"
  [ "$fail_rows" -ge 1 ]
}

# ---------- concurrent tick race ----------

@test "two concurrent ticks → exactly one fire (flock guards)" {
  _seed ping
  export JARVIS_FAKE_NOW="2026-04-26T14:35:00Z"
  export JARVIS_NOTIFY_DRYRUN=1
  # Spawn two ticks concurrently; flock on .tick.lock should let only one
  # in. The other silently exits 0.
  remind_tick_run &
  pid1=$!
  remind_tick_run &
  pid2=$!
  wait "$pid1" "$pid2"
  fc="$(jq -r '.fire_count' < "$JARVIS_HOME/test/reminders/ping.json")"
  [ "$fc" = "1" ]
}

# ---------- recurring is left untouched in T8 (handled in T9) ----------

@test "recurring reminder is skipped in T8 (handled in T9)" {
  blob="$(_one_shot_reminder rec | jq -c '.repeat = "daily" | .anchor_at = "09:00" | .status = "active"')"
  remind_schema_create rec "$blob" >/dev/null
  export JARVIS_FAKE_NOW="2026-04-26T14:35:00Z"
  export JARVIS_NOTIFY_DRYRUN=1
  remind_tick_run
  payload="$(cat "$JARVIS_HOME/test/reminders/rec.json")"
  [ "$(jq -r '.status' <<< "$payload")" = "active" ]    # unchanged
  [ "$(jq -r '.fire_count' <<< "$payload")" = "0" ]     # unchanged
}
