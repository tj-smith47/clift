#!/usr/bin/env bash
# Shows CLI version and cfgd versioning status.
# Usage: version.sh <CLI_DIR> <FRAMEWORK_DIR>

set -euo pipefail

CLI_DIR="${1:-}"
FRAMEWORK_DIR="${2:-}"

if [[ -z "$CLI_DIR" || -z "$FRAMEWORK_DIR" ]]; then
  echo "error: CLI_DIR and FRAMEWORK_DIR required" >&2
  exit 1
fi

source "${FRAMEWORK_DIR}/lib/log/log.sh"
# shellcheck source=../runtime/overrides.sh
source "${FRAMEWORK_DIR}/lib/runtime/overrides.sh"

cli_name="${CLI_NAME:-unknown}"
cli_version="${CLI_VERSION:-0.0.0}"

_clift_version_print_default() { echo "$1 version $2"; }
clift_call_override version_print _clift_version_print_default \
  "$cli_name" "$cli_version" "$CLI_DIR"

if [[ "${CFGD_VERSIONING:-}" != "true" ]]; then
  exit 0
fi

echo ""

if ! command -v cfgd &>/dev/null; then
  log_warn "cfgd not installed"
  log_suggest "Run '${cli_name} version:setup' to install"
  exit 0
fi

if [[ -f "${CLI_DIR}/.cfgd-managed" ]]; then
  log_info "Managed by cfgd"
else
  log_info "cfgd versioning enabled (not yet applied)"
  log_suggest "Run 'cfgd apply' to activate"
fi
