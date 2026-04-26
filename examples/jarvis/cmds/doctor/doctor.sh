#!/usr/bin/env bash
set -euo pipefail

# Resolve framework/CLI dirs with fallback so this script runs standalone in tests.
: "${FRAMEWORK_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)}"
: "${CLI_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# shellcheck source=/dev/null
source "${FRAMEWORK_DIR}/lib/log/log.sh"
# shellcheck source=/dev/null
source "${CLI_DIR}/lib/state/profile.sh"

# CLIFT_FLAGS may not be declared when invoked standalone.
if ! declare -p CLIFT_FLAGS >/dev/null 2>&1; then
  declare -A CLIFT_FLAGS=()
fi

path_flag="${CLIFT_FLAGS[path]:-}"
rebuild_flag="${CLIFT_FLAGS[rebuild-index]:-}"

state_dir="$(state_profile_dir)"

if [[ "$path_flag" == "true" ]]; then
  printf '%s\n' "$state_dir"
  exit 0
fi

if [[ "$rebuild_flag" == "true" ]]; then
  # shellcheck source=/dev/null
  source "${CLI_DIR}/lib/state/lock.sh"
  # shellcheck source=/dev/null
  source "${CLI_DIR}/lib/state/json.sh"
  # shellcheck source=/dev/null
  source "${CLI_DIR}/lib/frontmatter.sh"
  # shellcheck source=/dev/null
  source "${CLI_DIR}/lib/note/resolve.sh"
  # shellcheck source=/dev/null
  source "${CLI_DIR}/lib/note/index.sh"

  state_ensure_tree
  note_index_rebuild
  count="$(jq -r 'keys | length' "$(note_index_file)" 2>/dev/null || printf '0')"
  log_success "rebuilt note index: $count notes"
  exit 0
fi

printf '%-15s %-20s %s\n' "profile" "${JARVIS_PROFILE:-default}" "state at $state_dir"

if [[ -f "$state_dir/state.version" ]]; then
  schema="v$(< "$state_dir/state.version")"
  printf '%-15s %-20s %s\n' "state schema" "$schema" "up to date"
else
  printf '%-15s %-20s %s\n' "state schema" "uninitialized" "run any jarvis command once to initialize"
fi

# Integration checks (expand per-phase; P0 stubs only the presence probe pattern)
# Per-binary version probe — some tools (dasel) expose version via subcommand, not --flag.
probe_version() {
  case "$1" in
    dasel) dasel version 2>/dev/null | head -1 ;;
    *)     "$1" --version 2>&1 | head -1 ;;
  esac
}

for bin in jq dasel rg jira glow; do
  if command -v "$bin" >/dev/null 2>&1; then
    ver="$(probe_version "$bin" || true)"
    printf '\u2713 %-13s %-20s %s\n' "$bin" "$ver" "available"
  else
    printf '\u2717 %-13s %-20s %s\n' "$bin" "missing" "install $bin"
  fi
done

# reminders rollup + scheduler check (T16)
# Counts derive from per-item JSON files (pending/active) and the NDJSON
# delivery log (delivered/failed). Scheduler line reports the configured
# backend's install state plus a stale-tick warning when the heartbeat is
# older than 5 minutes (catches "cron line installed but crond not running"
# or "systemd timer disabled").
# shellcheck source=/dev/null
source "${CLI_DIR}/lib/state/config.sh"
# shellcheck source=/dev/null
source "${CLI_DIR}/lib/remind/install.sh"

_doctor_count_status() {
  local dir="$1" status="$2"
  shopt -s nullglob
  local files=( "$dir"/reminders/*.json )
  shopt -u nullglob
  if (( ${#files[@]} == 0 )); then
    printf '0\n'; return 0
  fi
  jq -s --arg s "$status" '[.[] | select(.status == $s)] | length' \
    "${files[@]}" 2>/dev/null || printf '0\n'
}

_doctor_count_delivery() {
  local log="$1" cond="$2"
  if [[ ! -f "$log" ]]; then
    printf '0\n'; return 0
  fi
  jq -c "select($cond)" < "$log" 2>/dev/null | wc -l | tr -d ' '
}

_doctor_last_heartbeat() {
  local log="$1"
  [[ -f "$log" ]] || return 1
  local ts
  ts="$(jq -r 'select(.kind == "tick.heartbeat") | .ts' < "$log" 2>/dev/null \
        | tail -n 1)"
  [[ -n "$ts" ]] || return 1
  printf '%s\n' "$ts"
}

_doctor_now_epoch() {
  if [[ -n "${JARVIS_FAKE_NOW:-}" ]]; then
    date -u -d "$JARVIS_FAKE_NOW" +%s 2>/dev/null
  else
    date +%s
  fi
}

_doctor_format_age() {
  local secs="$1"
  if (( secs < 60 )); then
    printf '%ds ago' "$secs"
  elif (( secs < 3600 )); then
    printf '%dm ago' $((secs / 60))
  else
    printf '%dh ago' $((secs / 3600))
  fi
}

_doctor_scheduler_line() {
  local backend="$1" log="$2"
  local installed=1 last_iso last_e now_e age
  case "$backend" in
    cron)    _remind_cron_installed    && installed=0 ;;
    systemd) _remind_systemd_installed && installed=0 ;;
    *)       printf '%s NOT installed (unknown backend)\n' "$backend"; return 0 ;;
  esac

  if (( installed != 0 )); then
    # shellcheck disable=SC2016  # backticks here are literal markdown, not subshells
    printf '%s NOT installed \u2014 run `jarvis remind install`\n' "$backend"
    return 0
  fi

  if last_iso="$(_doctor_last_heartbeat "$log")"; then
    last_e="$(date -u -d "$last_iso" +%s 2>/dev/null || printf '0')"
    now_e="$(_doctor_now_epoch)"
    age=$((now_e - last_e))
    if (( age > 300 )); then
      printf '%s installed but stale \u2014 last tick %s \u2014 is the scheduler running?\n' \
        "$backend" "$(_doctor_format_age "$age")"
    else
      printf '%s installed (last tick %s)\n' "$backend" "$(_doctor_format_age "$age")"
    fi
  else
    printf '%s installed (no tick yet \u2014 wait one minute)\n' "$backend"
  fi
}

_doctor_render_reminders() {
  local dir="$1"
  local log="$dir/reminders.delivery.log"
  local pending active delivered failed backend sched_line
  pending="$(_doctor_count_status "$dir" pending)"
  active="$(_doctor_count_status "$dir" active)"
  delivered="$(_doctor_count_delivery "$log" '.ok == true')"
  failed="$(_doctor_count_delivery "$log" '.ok == false')"
  backend="$(config_get scheduler.backend cron)"
  sched_line="$(_doctor_scheduler_line "$backend" "$log")"

  printf '\nreminders:\n'
  printf '  pending     %s\n' "$pending"
  printf '  active      %s\n' "$active"
  printf '  delivered   %s\n' "$delivered"
  printf '  failed      %s\n' "$failed"
  printf '  scheduler   %s\n' "$sched_line"
}

_doctor_render_reminders "$state_dir"

# focus.log orphan check \u2014 surfaces SIGKILL / power-loss cases where a
# `start` row landed but the EXIT trap never got to write its `end`.
# Sources are loaded lazily here so the dependency only kicks in when the
# log exists (avoids cost on a freshly-bootstrapped profile).
focus_log="$state_dir/focus.log"
if [[ -f "$focus_log" ]]; then
  # shellcheck source=/dev/null
  source "${CLI_DIR}/lib/state/lock.sh"
  # shellcheck source=/dev/null
  source "${CLI_DIR}/lib/state/ndjson.sh"
  # shellcheck source=/dev/null
  source "${CLI_DIR}/lib/focus/log.sh"
  orphan_count="$(focus_orphan_starts | grep -c . || true)"
  if (( orphan_count == 0 )); then
    printf '\u2713 %-13s %-20s %s\n' "focus.log" "0 orphan rows" "clean"
  else
    printf '\u26a0 %-13s %-20s %s\n' "focus.log" "$orphan_count orphan rows" \
      "SIGKILL or power loss left starts unmatched (cleanup TBD)"
  fi
else
  printf '\u2713 %-13s %-20s %s\n' "focus.log" "no log yet" "no focus sessions recorded"
fi
