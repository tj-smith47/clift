#!/usr/bin/env bash
set -euo pipefail

source "${FRAMEWORK_DIR}/lib/log/log.sh"

body="${CLIFT_POS_1:-}"
pin="${CLIFT_FLAGS[pin]:-}"

if [[ -z "$body" ]]; then
  clift_exit 2 "usage: jarvis note <text> [--tag NAME]... [--pin]"
fi

# List flags: per-element via CLIFT_FLAG_<NAME>_<N>, COUNT via _COUNT suffix.
tag_count="${CLIFT_FLAG_TAG_COUNT:-0}"
tags=()
for (( i=1; i<=tag_count; i++ )); do
  var="CLIFT_FLAG_TAG_${i}"
  tags+=("${!var}")
done

id=$((RANDOM % 900 + 100))

log_success "note #${id} saved"
printf '  body: %s\n' "$body"
if (( tag_count > 0 )); then
  printf '  tags: '
  printf '#%s ' "${tags[@]}"
  printf '\n'
fi
[[ "$pin" == "true" ]] && printf '  📌 pinned\n'
