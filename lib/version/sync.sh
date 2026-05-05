#!/usr/bin/env bash
# Regenerate module.yaml from .clift.yaml.
# Usage: sync.sh <CLI_DIR> <FRAMEWORK_DIR>
#
# .clift.yaml is the single source of truth for CLI metadata (name,
# description). module.yaml is a cfgd manifest derived from it; cfgd uses git
# tags for the version field so this script doesn't touch versions, only
# metadata that can drift after manual edits.
#
# Idempotent: prints nothing and exits 0 when files already match. Prints a
# unified diff and writes when changes are needed.
#
# Flags: --dry-run (show diff, don't write).

set -euo pipefail

CLI_DIR="${1:-}"
FRAMEWORK_DIR="${2:-}"

if [[ -z "$CLI_DIR" || -z "$FRAMEWORK_DIR" ]]; then
  echo "error: CLI_DIR and FRAMEWORK_DIR required" >&2
  exit 1
fi
shift 2 || true

# shellcheck source=../log/log.sh
source "${FRAMEWORK_DIR}/lib/log/log.sh"

args=()
if [[ -n "${CLIFT_ARG_COUNT:-}" ]]; then
  for ((i=1; i<=CLIFT_ARG_COUNT; i++)); do
    var="CLIFT_ARG_$i"
    args+=("${!var}")
  done
elif (( $# > 0 )); then
  args=("$@")
fi

DRY_RUN=0
QUIET=0

for a in ${args[@]+"${args[@]}"}; do
  case "$a" in
    --dry-run) DRY_RUN=1 ;;
    --quiet|-q) QUIET=1 ;;
    -h|--help)
      cat <<EOF
Usage: ${CLI_NAME:-clift} version:sync [--dry-run]

Regenerate module.yaml from .clift.yaml. Idempotent.
EOF
      exit 0
      ;;
    *)
      log_error "unexpected argument: $a"
      exit 2
      ;;
  esac
done

CLIFT_YAML="${CLI_DIR}/.clift.yaml"
MODULE_YAML="${CLI_DIR}/module.yaml"

[[ -f "$CLIFT_YAML" ]] || die ".clift.yaml not found at ${CLIFT_YAML}"

if [[ ! -f "$MODULE_YAML" ]]; then
  (( QUIET )) || log_info "module.yaml not present; nothing to sync (run 'version:setup' first)"
  exit 0
fi

cli_name="$(yq '.name' "$CLIFT_YAML" 2>/dev/null || echo '')"
[[ -z "$cli_name" || "$cli_name" == "null" ]] && die "could not read .name from ${CLIFT_YAML}"
desc="$(yq '.description' "$CLIFT_YAML" 2>/dev/null || echo '')"
[[ -z "$desc" || "$desc" == "null" ]] && desc="${cli_name} CLI"

_tmp="$(mktemp)"
trap 'rm -f "$_tmp"' EXIT

_YQ_NAME="$cli_name" _YQ_DESC="$desc" \
  yq '.metadata.name = strenv(_YQ_NAME) | .metadata.description = strenv(_YQ_DESC)' \
  "$MODULE_YAML" > "$_tmp"

if cmp -s "$_tmp" "$MODULE_YAML"; then
  (( QUIET )) || log_info "module.yaml is up to date"
  exit 0
fi

# Show diff.
if (( ! QUIET )); then
  diff -u "$MODULE_YAML" "$_tmp" || true
fi

if (( DRY_RUN )); then
  (( QUIET )) || log_info "(dry-run) would write ${MODULE_YAML}"
  exit 0
fi

mv "$_tmp" "$MODULE_YAML"
trap - EXIT
(( QUIET )) || log_success "synced ${MODULE_YAML} from .clift.yaml"
