#!/usr/bin/env bash
set -euo pipefail

source "${FRAMEWORK_DIR}/lib/log/log.sh"

filter="${CLIFT_FLAGS[priority]:-}"

# Canned task list — in a real CLI this comes from persistent state.
_tasks=(
  "3|high|ship vhs demos|today"
  "7|high|review auth PR|today"
  "11|med|write release notes for v1.1|tomorrow"
  "14|med|update quickstart docs|fri"
  "21|low|archive old branches|—"
)

_pr_color() {
  case "$1" in
    high) printf '\033[31m%s\033[0m' "$1" ;;
    med)  printf '\033[33m%s\033[0m' "$1" ;;
    low)  printf '\033[90m%s\033[0m' "$1" ;;
    *)    printf '%s' "$1" ;;
  esac
}

printf '\n  \033[1m%-3s %-6s %-30s %s\033[0m\n' "ID" "PRI" "DESCRIPTION" "DUE"
for row in "${_tasks[@]}"; do
  IFS='|' read -r id pri desc due <<< "$row"
  [[ -n "$filter" && "$pri" != "$filter" ]] && continue
  printf '  %-3s %-15s %-30s %s\n' "$id" "$(_pr_color "$pri")" "$desc" "$due"
done
printf '\n'
