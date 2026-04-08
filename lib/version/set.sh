#!/usr/bin/env bash
# Pins the CLI to a specific version via cfgd.
# Usage: set.sh <CLI_DIR> <FRAMEWORK_DIR> <VERSION>

set -euo pipefail

CLI_DIR="${1:-}"
FRAMEWORK_DIR="${2:-}"
VERSION="${3:-}"

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

if [[ -z "$VERSION" ]]; then
  log_error "Usage: ${cli_name} version:set -- <version>"
  log_suggest "Example: ${cli_name} version:set -- v1.2.3"
  exit "$EXIT_USAGE"
fi

# Apply tag convention: cli-name/vX.Y.Z
ref="$VERSION"
if [[ "$ref" != "${cli_name}/"* ]]; then
  ref="${cli_name}/${VERSION}"
fi

log_info "Pinning ${cli_name} to ${VERSION}..."

if ! cfgd module upgrade "$cli_name" --ref "$ref"; then
  die "Failed to pin version. Check that tag '${ref}' exists."
fi

log_success "Pinned ${cli_name} to ${VERSION}"
log_suggest "Run 'cfgd apply' to apply the change"
