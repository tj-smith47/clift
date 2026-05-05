#!/usr/bin/env bash
# Compare local CLI version against latest available.
# Usage: check.sh <CLI_DIR> <FRAMEWORK_DIR>
#
# Two modes, auto-detected:
#   - cfgd-managed: a `.cfgd-managed` marker exists. Reads installed and
#     latest_available from `cfgd module list --json` for this CLI.
#   - Standalone:   `git fetch --tags` then walk local tags matching either
#     `vX.Y.Z` or `<cli-name>/vX.Y.Z`; compare highest to .clift.yaml.
#
# Output:
#   `up to date (vX.Y.Z)`     when local matches latest
#   `vX.Y.Z → vA.B.C available`  when an upgrade exists
#
# Flags: --json (machine output), -q/--quiet (print only when an update exists).
# Exit 0 either way; exit 1 only on tooling failure (network, missing git, etc.).

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

JSON=0
QUIET=0

for a in ${args[@]+"${args[@]}"}; do
  case "$a" in
    --json) JSON=1 ;;
    -q|--quiet) QUIET=1 ;;
    -h|--help)
      cat <<EOF
Usage: ${CLI_NAME:-clift} version:check [--json] [-q|--quiet]

Compare the installed version against the latest available.
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
[[ -f "$CLIFT_YAML" ]] || die ".clift.yaml not found at ${CLIFT_YAML}"

cli_name="$(yq '.name' "$CLIFT_YAML" 2>/dev/null || echo '')"
[[ -z "$cli_name" || "$cli_name" == "null" ]] && die "could not read .name from ${CLIFT_YAML}"

local_version="$(yq '.version' "$CLIFT_YAML" 2>/dev/null || echo '')"
[[ -z "$local_version" || "$local_version" == "null" ]] && die "could not read .version from ${CLIFT_YAML}"
local_version="${local_version#v}"

# _semver_max — print the lexically-greatest semver from stdin (one tag per
# line, with or without `v` / `<name>/v` prefixes). Empty stdin → empty stdout.
_semver_max() {
  awk -F'.' '
    {
      v = $0
      sub(/^.*\//, "", v)   # strip "<name>/" prefix
      sub(/^v/, "", v)
      if (v !~ /^[0-9]+\.[0-9]+\.[0-9]+$/) next
      n = split(v, p, ".")
      cur = (p[1] * 1000000) + (p[2] * 1000) + p[3]
      if (cur > best) { best = cur; bestv = v }
    }
    END { if (bestv) print bestv }
  '
}

latest=""
mode="standalone"

if [[ -f "${CLI_DIR}/.cfgd-managed" ]] && command -v cfgd >/dev/null 2>&1; then
  mode="cfgd"
  if json="$(cfgd module list --json 2>/dev/null)"; then
    # Try a few field shapes — cfgd's JSON surface has shifted across versions.
    latest="$(printf '%s' "$json" | jq -r --arg n "$cli_name" '
      .. | objects | select(.name? == $n) | (.latest_available // .latest // .available // empty)
    ' 2>/dev/null | head -n1)"
  fi
  # Fall back to git-tag walk if cfgd didn't return anything usable.
fi

if [[ -z "$latest" ]]; then
  cd "$CLI_DIR"
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    die "${CLI_DIR} is not a git repository (and not cfgd-managed)"
  fi
  # Best-effort fetch; offline machines still get a useful answer from local tags.
  git fetch --tags --quiet 2>/dev/null || true
  # Match either "vX.Y.Z" or "<cli-name>/vX.Y.Z".
  latest="$(git tag --list "v*" "${cli_name}/v*" 2>/dev/null | _semver_max)"
fi

# Output -----------------------------------------------------------------------

up_to_date=0
if [[ -z "$latest" ]] || [[ "$latest" == "$local_version" ]]; then
  up_to_date=1
elif [[ "$(printf '%s\n%s\n' "$latest" "$local_version" | _semver_max)" == "$local_version" ]]; then
  # local > latest (e.g., unreleased dev bump). Treat as up-to-date for output.
  up_to_date=1
fi

if (( JSON )); then
  jq -nc \
    --arg name "$cli_name" \
    --arg local "$local_version" \
    --arg latest "${latest:-$local_version}" \
    --arg mode "$mode" \
    --argjson up_to_date "$up_to_date" \
    '{
      name: $name,
      mode: $mode,
      local: ("v" + $local),
      latest: ("v" + $latest),
      up_to_date: ($up_to_date == 1)
    }'
  exit 0
fi

if (( up_to_date )); then
  (( QUIET )) || printf 'up to date (v%s)\n' "$local_version"
else
  printf 'v%s → v%s available\n' "$local_version" "$latest"
fi
