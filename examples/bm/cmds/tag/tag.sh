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
    '[{"name":"add","type":"list"},{"name":"remove","type":"list"}]' \
    "$@"
  # Standalone-only mutex check — the router enforces this when invoked
  # via the framework, but direct-invocation tests need the same guard.
  if (( ${CLIFT_FLAG_ADD_COUNT:-0} > 0 && ${CLIFT_FLAG_REMOVE_COUNT:-0} > 0 )); then
    clift_exit 2 "flags --add and --remove (group: mutation) are mutually exclusive"
  fi
fi

name="${CLIFT_POS_1:-}"
[[ -n "$name" ]] || clift_exit 2 "usage: bm tag <name> (--add T... | --remove T...)"

bm_store_get "$name" >/dev/null 2>&1 \
  || clift_exit 1 "no bookmark named: $name"

add_count="${CLIFT_FLAG_ADD_COUNT:-0}"
rem_count="${CLIFT_FLAG_REMOVE_COUNT:-0}"

(( add_count > 0 || rem_count > 0 )) \
  || clift_exit 2 "nothing to do: pass --add T or --remove T"

# Set semantics — duplicates merged, missing removes are silent no-ops.
current="$(bm_store_tags "$name")"

if (( add_count > 0 )); then
  new=()
  for (( i=1; i<=add_count; i++ )); do var="CLIFT_FLAG_ADD_${i}"; new+=("${!var}"); done
  add_json="$(printf '%s\n' "${new[@]}" | jq -R . | jq -cs .)"
  current="$(jq -c --argjson a "$add_json" '. + $a | unique' <<< "$current")"
fi

if (( rem_count > 0 )); then
  drop=()
  for (( i=1; i<=rem_count; i++ )); do var="CLIFT_FLAG_REMOVE_${i}"; drop+=("${!var}"); done
  rem_json="$(printf '%s\n' "${drop[@]}" | jq -R . | jq -cs .)"
  current="$(jq -c --argjson r "$rem_json" 'map(select(. as $x | $r | index($x) | not))' <<< "$current")"
fi

bm_store_set_tags "$name" "$current"
log_success "$name: $(jq -r '. | join(",")' <<< "$current")"
