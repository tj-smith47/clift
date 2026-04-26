#!/usr/bin/env bash
# Tick loop — fires due reminders across every profile under $JARVIS_HOME.
#
# Wraps work in per-profile `flock -n` so concurrent ticks (cron */1 + slow
# gotify, double-cron config, manual + scheduled overlap) cannot double-fire
# the same reminder.
#
# On every tick run, appends a `tick.heartbeat` row to the per-profile
# reminders.delivery.log so `doctor` can detect "scheduler installed but not
# firing" — caught case where cron line exists but crond isn't running.
#
# Per-channel attempt results live in two places by design:
#   - notify.log: uniform per-channel record written by every channel via
#     _notify_log (used for jq queries during testing/debugging).
#   - reminders.delivery.log: per-fire NDJSON keyed by slug. Built by tick
#     diffing notify.log around the dispatch call; doctor reads this for
#     O(1) "delivered/failed count" rollups.

# shellcheck disable=SC2317
if [[ -n "${_JARVIS_REMIND_TICK_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
_JARVIS_REMIND_TICK_LOADED=1

remind_tick_run() {
  local home="${JARVIS_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/jarvis}"
  [[ -d "$home" ]] || return 0

  local profile_dir
  for profile_dir in "$home"/*; do
    [[ -d "$profile_dir" ]] || continue
    local profile_name="${profile_dir##*/}"
    mkdir -p "$profile_dir/reminders"
    local lock_file="$profile_dir/reminders/.tick.lock"

    # Per-profile non-blocking lock. Subshell isolates the lock fd; if
    # another tick holds it, this profile is silently skipped this round.
    (
      exec 9>"$lock_file"
      flock -n 9 || exit 0
      _remind_tick_one_profile "$profile_name" "$profile_dir"
    )
  done
}

_remind_tick_one_profile() {
  local profile_name="$1" profile_dir="$2"
  local now_iso now_e
  now_iso="$(_remind_tick_now_iso)" || return 1
  now_e="$(_remind_now_epoch)" || return 1

  # Heartbeat first — even if no reminders fire, doctor sees the tick ran.
  local heartbeat
  heartbeat="$(jq -nc --arg ts "$now_iso" '{ts:$ts, kind:"tick.heartbeat"}')"
  remind_delivery_log_append "_heartbeat" "$heartbeat" "$profile_name"

  local f
  for f in "$profile_dir"/reminders/*.json; do
    [[ -e "$f" ]] || continue
    _remind_tick_one_reminder "$f" "$profile_name" "$now_iso" "$now_e"
  done
}

# now_iso preferring fake clock for tests.
_remind_tick_now_iso() {
  if [[ -n "${JARVIS_FAKE_NOW:-}" ]]; then
    printf '%s\n' "$JARVIS_FAKE_NOW"
  else
    date -u +%Y-%m-%dT%H:%M:%SZ
  fi
}

_remind_tick_one_reminder() {
  local file="$1" profile_name="$2" now_iso="$3" now_e="$4"

  local payload
  payload="$(state_json_read "$file")" || return 0

  local status repeat
  status="$(jq -r '.status' <<< "$payload")"
  case "$status" in
    pending|active) ;;
    *) return 0 ;;
  esac

  # T8: one-shot only. Recurring (.repeat != null) lands in T9.
  repeat="$(jq -r '.repeat // empty' <<< "$payload")"
  [[ -n "$repeat" ]] && return 0

  local trigger_at trigger_e
  trigger_at="$(jq -r '.trigger_at' <<< "$payload")"
  trigger_e="$(_rs_to_epoch "$trigger_at")" || return 0
  (( trigger_e <= now_e )) || return 0

  local slug rem_profile
  slug="$(jq -r '.slug' <<< "$payload")"
  rem_profile="$(jq -r '.profile' <<< "$payload")"

  # Capture notify.log size before dispatch so we can grab the new rows
  # afterward and append them to the delivery NDJSON keyed by slug.
  local notify_log before=0 after=0
  notify_log="$(_notify_log_path "$rem_profile")"
  [[ -f "$notify_log" ]] && before="$(wc -l < "$notify_log")"

  local dispatch_rc=0
  notify_dispatch "$payload" || dispatch_rc=$?

  [[ -f "$notify_log" ]] && after="$(wc -l < "$notify_log")"

  if (( after > before )); then
    local row
    while IFS= read -r row; do
      [[ -z "$row" ]] && continue
      remind_delivery_log_append "$slug" "$row" "$rem_profile"
    done < <(tail -n +"$((before+1))" "$notify_log")
  fi

  # One-shot transition: any-ok-wins → delivered; all-fail → failed.
  local new_status
  if (( dispatch_rc == 0 )); then
    new_status="delivered"
  else
    new_status="failed"
  fi

  local updated
  updated="$(jq -c \
    --arg now "$now_iso" \
    --arg s "$new_status" \
    '. | .last_fired_at = $now
       | .fire_count = (.fire_count + 1)
       | .status = $s' <<< "$payload")"
  remind_schema_save "$slug" "$updated" "$rem_profile"
}
