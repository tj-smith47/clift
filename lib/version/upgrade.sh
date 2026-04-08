#!/usr/bin/env bash
# Upgrades the CLI to the latest version via cfgd.
# Usage: upgrade.sh <CLI_DIR> <FRAMEWORK_DIR>

set -euo pipefail

CLI_DIR="${1:-}"
FRAMEWORK_DIR="${2:-}"

if [[ -z "$CLI_DIR" || -z "$FRAMEWORK_DIR" ]]; then
  echo "error: CLI_DIR and FRAMEWORK_DIR required" >&2
  exit 1
fi

source "${FRAMEWORK_DIR}/lib/log/log.sh"

cli_name="${CLI_NAME:-$(yq '.name' "${CLI_DIR}/.task-cli.yaml" 2>/dev/null)}"

if [[ "${CFGD_VERSIONING:-}" != "true" ]]; then
  die "Versioning is not set up. Run '${cli_name} version:setup' first."
fi

if ! command -v cfgd &>/dev/null; then
  die "cfgd is not installed. Run '${cli_name} version:setup' to install."
fi

log_info "Checking for updates..."

if ! cfgd module upgrade "$cli_name"; then
  die "Upgrade failed. Run 'cfgd module upgrade ${cli_name}' for details."
fi

log_success "Upgrade complete"
log_suggest "Run 'cfgd apply' to apply the update"
