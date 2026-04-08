#!/usr/bin/env bash
# Validates hard and soft dependencies for DIYCLI.
# Hard deps (jq): exit 1 if missing.
# Soft deps (gum): warn but continue, export GUM_AVAILABLE=true/false.

set -euo pipefail

_check_cmd() {
  command -v "$1" &>/dev/null
}

# Hard dependency: jq
if ! _check_cmd jq; then
  echo "error: jq is required but not installed. See https://jqlang.github.io/jq/download/" >&2
  exit 1
fi

# Soft dependency: gum
if _check_cmd gum; then
  export GUM_AVAILABLE=true
else
  export GUM_AVAILABLE=false
  # Only warn if DEPS_WARN_GUM is set (e.g., during setup)
  if [[ "${DEPS_WARN_GUM:-}" == "true" ]]; then
    echo "warn: gum not found — interactive prompts will use basic read fallback. See https://github.com/charmbracelet/gum" >&2
  fi
fi
