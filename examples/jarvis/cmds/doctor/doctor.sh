#!/usr/bin/env bash
set -euo pipefail

# Resolve framework/CLI dirs with fallback so this script runs standalone in tests.
: "${FRAMEWORK_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)}"
: "${CLI_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# shellcheck source=/dev/null
source "${FRAMEWORK_DIR}/lib/log/log.sh"
# shellcheck source=/dev/null
source "${CLI_DIR}/lib/state/profile.sh"

# CLIFT_FLAGS may not be declared when invoked standalone.
if ! declare -p CLIFT_FLAGS >/dev/null 2>&1; then
  declare -A CLIFT_FLAGS=()
fi

path_flag="${CLIFT_FLAGS[path]:-}"

state_dir="$(state_profile_dir)"

if [[ "$path_flag" == "true" ]]; then
  printf '%s\n' "$state_dir"
  exit 0
fi

printf '%-15s %-20s %s\n' "profile" "${JARVIS_PROFILE:-default}" "state at $state_dir"

if [[ -f "$state_dir/state.version" ]]; then
  schema="v$(< "$state_dir/state.version")"
  printf '%-15s %-20s %s\n' "state schema" "$schema" "up to date"
else
  printf '%-15s %-20s %s\n' "state schema" "uninitialized" "run any jarvis command once to initialize"
fi

# Integration checks (expand per-phase; P0 stubs only the presence probe pattern)
# Per-binary version probe — some tools (dasel) expose version via subcommand, not --flag.
probe_version() {
  case "$1" in
    dasel) dasel version 2>/dev/null | head -1 ;;
    *)     "$1" --version 2>&1 | head -1 ;;
  esac
}

for bin in jq dasel rg jira; do
  if command -v "$bin" >/dev/null 2>&1; then
    ver="$(probe_version "$bin" || true)"
    printf '\u2713 %-13s %-20s %s\n' "$bin" "$ver" "available"
  else
    printf '\u2717 %-13s %-20s %s\n' "$bin" "missing" "install $bin"
  fi
done
