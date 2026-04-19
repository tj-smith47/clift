#!/usr/bin/env bash
set -euo pipefail

source "${FRAMEWORK_DIR}/lib/log/log.sh"

short="${CLIFT_FLAGS[short]:-}"
profile="${CLIFT_FLAGS[profile]:-work}"

if [[ "$short" == "true" ]]; then
  log_info "brief (${profile}): 3 PRs · 2 deploys today · oncall: alex"
  exit 0
fi

# Canned briefing content — this is a demo, not real data.
printf '\n'
log_info "☀  Good morning — ${profile} profile"
printf '\n'

printf '  \033[1mCalendar\033[0m\n'
printf '    10:00  standup\n'
printf '    13:30  1:1 with sam\n'
printf '    15:00  platform sync\n\n'

printf '  \033[1mPRs awaiting your review\033[0m\n'
printf '    #482  feat(router): persistent flags before cmd token\n'
printf '    #491  fix(flags): alias collision detection\n'
printf '    #493  docs: update quickstart for jarvis example\n\n'

printf '  \033[1mRecent deploys\033[0m\n'
printf '    api          v1.12.3   ✓ 2h ago\n'
printf '    web          v0.47.1   ✓ 5h ago\n'
printf '    ingest       v2.1.0    ⚠  rolled back 1d ago\n\n'

printf '  \033[1mOncall\033[0m\n'
printf '    primary:    alex  (pager: quiet)\n'
printf '    secondary:  you\n'
printf '\n'
