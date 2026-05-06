#!/usr/bin/env bash
set -euo pipefail

: "${FRAMEWORK_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)}"
: "${CLI_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# shellcheck source=/dev/null
source "${FRAMEWORK_DIR}/lib/log/log.sh"
# shellcheck source=/dev/null
source "${CLI_DIR}/lib/store.sh"

if ! declare -p CLIFT_FLAGS >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${CLI_DIR}/lib/argv.sh"
  bm_argv_parse \
    '[{"name":"name","type":"string"},
      {"name":"tag","type":"list"},
      {"name":"description","type":"string"}]' \
    "$@"
fi

url="${CLIFT_POS_1:-}"
name="${CLIFT_FLAGS[name]:-}"
desc="${CLIFT_FLAGS[description]:-}"

[[ -n "$url" ]] || clift_exit 2 "usage: bm add <url> [--name N] [--tag T]... [--description D]"

# URL pattern validation. The flag system does not enforce regex on
# positionals — apps validate domain shape themselves.
[[ "$url" =~ ^https?:// ]] \
  || clift_exit 2 "invalid url: must match ^https?:// (got: $url)"

# Default name: URL host (strip scheme + path).
if [[ -z "$name" ]]; then
  name="${url#*://}"
  name="${name%%/*}"
fi

# Marshal --tag list flag into a positional list for bm_store_add.
tag_count="${CLIFT_FLAG_TAG_COUNT:-0}"
tags=()
for (( i=1; i<=tag_count; i++ )); do
  var="CLIFT_FLAG_TAG_${i}"
  tags+=("${!var}")
done

if ! bm_store_add "$url" "$name" "$desc" ${tags[@]+"${tags[@]}"}; then
  clift_exit 1 "failed to add bookmark: $name"
fi
log_success "$name"
