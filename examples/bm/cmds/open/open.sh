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
  bm_argv_parse '[{"name":"browser","type":"string"}]' "$@"
fi

name="${CLIFT_POS_1:-}"
browser="${CLIFT_FLAGS[browser]:-}"

[[ -n "$name" ]] || clift_exit 2 "usage: bm open <name> [--browser CMD]"

row="$(bm_store_get "$name" 2>/dev/null)" \
  || clift_exit 1 "no bookmark named: $name"
url="$(jq -r '.url' <<< "$row")"

# Browser resolution: explicit --browser → $BROWSER → platform default.
if [[ -z "$browser" ]]; then
  if [[ -n "${BROWSER:-}" ]]; then
    browser="$BROWSER"
  elif [[ "$(uname)" == "Darwin" ]]; then
    browser="open"
  else
    browser="xdg-open"
  fi
fi

command -v "$browser" >/dev/null 2>&1 \
  || clift_exit 1 "browser not found: $browser"

log_info "opening $url with $browser"
"$browser" "$url"
