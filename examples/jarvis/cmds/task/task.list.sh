#!/usr/bin/env bash
set -euo pipefail

: "${FRAMEWORK_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)}"
: "${CLI_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# shellcheck source=/dev/null
source "${FRAMEWORK_DIR}/lib/log/log.sh"
# shellcheck source=/dev/null
source "${CLI_DIR}/lib/state/profile.sh"
# shellcheck source=/dev/null
source "${CLI_DIR}/lib/state/lock.sh"
# shellcheck source=/dev/null
source "${CLI_DIR}/lib/state/json.sh"
# shellcheck source=/dev/null
source "${CLI_DIR}/lib/task/store.sh"

if ! declare -p CLIFT_FLAGS >/dev/null 2>&1; then
  declare -A CLIFT_FLAGS=()
fi

all="${CLIFT_FLAGS[all]:-}"
pri="${CLIFT_FLAGS[priority]:-}"
project="${CLIFT_FLAGS[project]:-}"
due="${CLIFT_FLAGS[due]:-}"
want_json="${CLIFT_FLAGS[json]:-}"
want_yaml="${CLIFT_FLAGS[yaml]:-}"
want_jira="${CLIFT_FLAGS[jira]:-}"

if [[ "$want_jira" == "true" ]]; then
  printf 'task list --jira: not yet implemented; coming in P5\n' >&2
fi

tasks_dir="$(task_store_dir)"
shopt -s nullglob
files=("$tasks_dir"/*.json)
shopt -u nullglob

# Resilient-skip malformed JSON: one bad file shouldn't kill the whole listing.
# Validate each file up-front with `jq -e .`; warn on failures, drop from the
# slurp input. The `+"${array[@]}"` expansion form guards against `set -u`
# firing when the array is empty (bash 4 quirk).
valid_files=()
for f in "${files[@]+"${files[@]}"}"; do
  if jq -e . "$f" >/dev/null 2>&1; then
    valid_files+=("$f")
  else
    log_warn "skipping malformed task record: ${f##*/}"
  fi
done
files=("${valid_files[@]+"${valid_files[@]}"}")

# Build filtered array via single jq pass.
# Filter values are passed via --arg to avoid injection (projects / due
# values with quotes would otherwise break the filter string).
# Empty-string args get selected-out by a guard in the filter itself.
if (( ${#files[@]} == 0 )); then
  records='[]'
else
  records="$(jq -s \
    --arg all "$all" \
    --arg pri "$pri" \
    --arg project "$project" \
    --arg due "$due" \
    '
      map(
        select($all == "true" or .status == "open")
        | select($pri == "" or .priority == $pri)
        | select($project == "" or .project == $project)
        | select($due == "" or .due == $due)
      )
      | sort_by(.seq)
    ' "${files[@]}")"
fi

count="$(jq 'length' <<< "$records")"

if [[ "$want_json" == "true" ]]; then
  printf '%s\n' "$records"
  exit 0
fi

if [[ "$want_yaml" == "true" ]]; then
  printf '%s\n' "$records" | yq -P eval '.' -
  exit 0
fi

if (( count == 0 )); then
  if [[ "$all" == "true" ]]; then
    printf '  no tasks\n'
  else
    printf '  no open tasks\n'
  fi
  exit 0
fi

_use_color() {
  [[ -z "${NO_COLOR:-}" ]]
}

_pr_color() {
  if ! _use_color; then
    printf '%s' "$1"
    return
  fi
  case "$1" in
    high) printf '\033[31m%s\033[0m' "$1" ;;
    med)  printf '\033[33m%s\033[0m' "$1" ;;
    low)  printf '\033[90m%s\033[0m' "$1" ;;
    *)    printf '%s' "$1" ;;
  esac
}

if _use_color; then
  printf '\n  \033[1m%-24s %-6s %-40s %-10s %s\033[0m\n' "SLUG" "PRI" "DESCRIPTION" "DUE" "PROJECT"
else
  printf '\n  %-24s %-6s %-40s %-10s %s\n' "SLUG" "PRI" "DESCRIPTION" "DUE" "PROJECT"
fi
while IFS=$'\t' read -r slug desc priority due_s project_s; do
  [[ -z "$slug" ]] && continue
  [[ "$due_s" == "null" ]] && due_s="—"
  if _use_color; then
    # Data row uses %-15s for PRI to absorb ANSI escapes (~9 bytes of
    # \033[NNm...\033[0m) so visible alignment matches the header's %-6s.
    printf '  %-24s %-15s %-40s %-10s %s\n' \
      "$slug" "$(_pr_color "$priority")" "$desc" "$due_s" "$project_s"
  else
    printf '  %-24s %-6s %-40s %-10s %s\n' \
      "$slug" "$priority" "$desc" "$due_s" "$project_s"
  fi
done < <(jq -r '.[] | [.slug, .desc, .priority, (.due // "null"), .project] | @tsv' <<< "$records")
printf '\n'
