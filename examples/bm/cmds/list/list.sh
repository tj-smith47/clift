#!/usr/bin/env bash
set -euo pipefail

: "${FRAMEWORK_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)}"
: "${CLI_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# shellcheck source=/dev/null
source "${FRAMEWORK_DIR}/lib/log/log.sh"
# shellcheck source=/dev/null
source "${CLI_DIR}/lib/store.sh"
# shellcheck source=/dev/null
source "${CLI_DIR}/lib/fmt.sh"

if ! declare -p CLIFT_FLAGS >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${CLI_DIR}/lib/argv.sh"
  bm_argv_parse \
    '[{"name":"tag","type":"list"},
      {"name":"format","type":"string"},
      {"name":"limit","type":"string"}]' \
    "$@"
fi

format="${CLIFT_FLAGS[format]:-table}"
limit="${CLIFT_FLAGS[limit]:-}"

# Build requested-tags JSON array from the list flag.
tag_count="${CLIFT_FLAG_TAG_COUNT:-0}"
want_tags="[]"
if (( tag_count > 0 )); then
  arr=()
  for (( i=1; i<=tag_count; i++ )); do
    var="CLIFT_FLAG_TAG_${i}"
    arr+=("${!var}")
  done
  want_tags="$(printf '%s\n' "${arr[@]}" | jq -R . | jq -cs .)"
fi

# Filter pipeline: apply tag filter first, then row cap. Both are
# pass-throughs when the corresponding flag is unset.
filtered() {
  bm_store_list \
    | jq -c --argjson want "$want_tags" '
        if ($want | length) == 0 then .
        else . as $row | if [.tags[] | IN($want[])] | any then $row else empty end
        end'
}

if [[ -n "$limit" ]]; then
  rows="$(filtered | head -n "$limit")"
else
  rows="$(filtered)"
fi

case "$format" in
  table) printf '%s\n' "$rows" | bm_fmt_table ;;
  json)  printf '%s\n' "$rows" | bm_fmt_json ;;
  yaml)  printf '%s\n' "$rows" | bm_fmt_yaml ;;
  *)     clift_exit 2 "--format must be table|json|yaml (got: $format)" ;;
esac
