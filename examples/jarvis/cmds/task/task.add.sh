#!/usr/bin/env bash
set -euo pipefail

source "${FRAMEWORK_DIR}/lib/log/log.sh"

desc="${CLIFT_POS_1:-}"
priority="${CLIFT_FLAGS[priority]:-med}"
due="${CLIFT_FLAGS[due]:-}"
project="${CLIFT_FLAGS[project]:-inbox}"

if [[ -z "$desc" ]]; then
  clift_exit 2 "usage: jarvis task add <description> [--priority low|med|high] [--due DATE] [--project NAME]"
fi

# Fake id — in a real CLI this would increment persistent state.
id=$((RANDOM % 90 + 10))

_pr_color() {
  case "$1" in
    high) printf '\033[31m%s\033[0m' "$1" ;;
    med)  printf '\033[33m%s\033[0m' "$1" ;;
    low)  printf '\033[90m%s\033[0m' "$1" ;;
    *)    printf '%s' "$1" ;;
  esac
}

log_success "task #${id} added to ${project}"
printf '  priority: %s\n' "$(_pr_color "$priority")"
printf '  desc:     %s\n' "$desc"
[[ -n "$due" ]] && printf '  due:      %s\n' "$due"
