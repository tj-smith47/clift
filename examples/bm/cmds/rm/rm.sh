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
  bm_argv_parse '[{"name":"force","type":"bool"}]' "$@"
fi

name="${CLIFT_POS_1:-}"
force="${CLIFT_FLAGS[force]:-}"

[[ -n "$name" ]] || clift_exit 2 "usage: bm rm <name> [--force]"

bm_store_get "$name" >/dev/null 2>&1 \
  || clift_exit 1 "no bookmark named: $name"

if [[ "$force" != "true" ]]; then
  if [[ ! -t 0 ]]; then
    clift_exit 2 "refusing to remove '$name' without --force on non-tty"
  fi
  read -r -p "remove bookmark '$name'? [y/N] " ans
  case "$ans" in
    y|Y|yes|YES) ;;
    *) log_info "aborted"; exit 0 ;;
  esac
fi

bm_store_remove "$name"
log_success "removed: $name"
