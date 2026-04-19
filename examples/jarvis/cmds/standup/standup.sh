#!/usr/bin/env bash
set -euo pipefail

source "${FRAMEWORK_DIR}/lib/log/log.sh"

since="${CLIFT_FLAGS[since]:-yesterday}"

printf '\n'
log_info "standup draft — since ${since}"
printf '\n'

printf '  \033[1mYesterday\033[0m\n'
printf '    • shipped jarvis v1.0 example for clift framework\n'
printf '    • fixed flag alias / persistent-flag collision in compile.sh\n'
printf '    • rebuilt all VHS demos with cleaner fixture\n\n'

printf '  \033[1mToday\033[0m\n'
printf '    • write release notes for v1.1\n'
printf '    • review auth PR (#491)\n'
printf '    • standup 10:00, platform sync 15:00\n\n'

printf '  \033[1mBlockers\033[0m\n'
printf '    none\n\n'
