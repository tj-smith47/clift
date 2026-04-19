#!/usr/bin/env bash
set -euo pipefail

source "${FRAMEWORK_DIR}/lib/log/log.sh"

json="${CLIFT_FLAGS[json]:-}"
yaml="${CLIFT_FLAGS[yaml]:-}"
profile="${CLIFT_FLAGS[profile]:-work}"

if [[ "$json" == "true" ]]; then
  cat <<EOF
{
  "profile": "${profile}",
  "tasks": {"open": 4, "done_today": 2},
  "reminders": {"scheduled": 3, "next_in": "42m"},
  "focus": {"streak_days": 6, "minutes_today": 75}
}
EOF
  exit 0
fi

if [[ "$yaml" == "true" ]]; then
  cat <<EOF
profile: ${profile}
tasks:
  open: 4
  done_today: 2
reminders:
  scheduled: 3
  next_in: 42m
focus:
  streak_days: 6
  minutes_today: 75
EOF
  exit 0
fi

# Default: pretty dashboard
log_info "Dashboard (${profile})"
printf '\n'
printf '  \033[1mTasks\033[0m\n'
printf '    open           4\n'
printf '    done today     2\n\n'

printf '  \033[1mReminders\033[0m\n'
printf '    scheduled      3\n'
printf '    next           42m  "stand up"\n\n'

printf '  \033[1mFocus\033[0m\n'
printf '    streak         6 days  🔥\n'
printf '    today          75 min\n'
printf '\n'
