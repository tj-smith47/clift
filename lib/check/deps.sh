#!/usr/bin/env bash
# Validates hard and soft dependencies for clift.
# Hard deps (jq, yq): exit 1 if missing.
# Soft deps (gum): warn but continue, export GUM_AVAILABLE=true/false.
# Also validates task version and exports framework version from .clift.yaml.

set -euo pipefail

_check_cmd() {
  command -v "$1" &>/dev/null
}

# Hard dependency: jq
if ! _check_cmd jq; then
  echo "error: jq is required but not installed. See https://jqlang.github.io/jq/download/" >&2
  exit 1
fi

# Hard dependency: yq
if ! _check_cmd yq; then
  echo "error: yq is required but not installed. See https://github.com/mikefarah/yq" >&2
  exit 1
fi

# Soft dependency: gum
if _check_cmd gum; then
  export GUM_AVAILABLE=true
else
  export GUM_AVAILABLE=false
  if [[ "${DEPS_WARN_GUM:-}" == "true" ]]; then
    echo "warn: gum not found — interactive prompts will use basic read fallback. See https://github.com/charmbracelet/gum" >&2
  fi
fi

# cfgd availability (optional backend for deps/updates)
if _check_cmd cfgd; then
  export CFGD_AVAILABLE=true
else
  export CFGD_AVAILABLE=false
fi

# Framework metadata: version export + task version validation
if [[ -n "${FRAMEWORK_DIR:-}" ]] && [[ -f "$FRAMEWORK_DIR/.clift.yaml" ]]; then
  CLIFT_VERSION="$(yq '.version' "$FRAMEWORK_DIR/.clift.yaml")"
  export CLIFT_VERSION

  _min_task_version="$(yq '.min_task_version // ""' "$FRAMEWORK_DIR/.clift.yaml")"

  if [[ -n "$_min_task_version" ]] && _check_cmd task; then
    _current_task_version="$(task --version | sed 's/.*v\([0-9][0-9.]*\).*/\1/')"

    _version_lt() {
      local -a a b
      IFS='.' read -ra a <<< "$1"
      IFS='.' read -ra b <<< "$2"
      local i
      for (( i=0; i<${#b[@]}; i++ )); do
        local av="${a[i]:-0}"
        local bv="${b[i]:-0}"
        if (( av < bv )); then return 0; fi
        if (( av > bv )); then return 1; fi
      done
      return 1
    }

    if _version_lt "$_current_task_version" "$_min_task_version"; then
      echo "warn: task version $_current_task_version is below minimum $_min_task_version" >&2
    fi

    unset -f _version_lt
  fi

  unset _min_task_version _current_task_version
fi
