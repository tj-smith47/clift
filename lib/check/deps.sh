#!/usr/bin/env bash
# Validates hard and soft dependencies for clift.
# Two levels:
#   clift_check_deps_fast — command presence only (per-invocation)
#   clift_check_deps_full — also validates versions and metadata (compile-time)

if [[ -n "${_CLIFT_DEPS_LOADED:-}" ]]; then return 0 2>/dev/null || true; fi
_CLIFT_DEPS_LOADED=1

# Fast check — called by router on every invocation
clift_check_deps_fast() {
  # Hard dependency: bash 4.0+ (associative arrays, mapfile, ${var^^})
  if (( BASH_VERSINFO[0] < 4 )); then
    echo "error: bash 4.0+ is required (found ${BASH_VERSION}). Install a newer bash via your package manager." >&2
    return 1
  fi

  # Hard dependency: jq
  if ! command -v jq &>/dev/null; then
    echo "error: jq is required but not installed. See https://jqlang.github.io/jq/download/" >&2
    return 1
  fi

  # Hard dependency: yq
  if ! command -v yq &>/dev/null; then
    echo "error: yq is required but not installed. See https://github.com/mikefarah/yq" >&2
    return 1
  fi

  # Soft dependency: gum
  if command -v gum &>/dev/null; then
    export GUM_AVAILABLE=true
  else
    export GUM_AVAILABLE=false
    if [[ "${DEPS_WARN_GUM:-}" == "true" ]]; then
      echo "warn: gum not found — interactive prompts will use basic read fallback. See https://github.com/charmbracelet/gum" >&2
    fi
  fi

  # cfgd availability (optional backend for deps/updates)
  if command -v cfgd &>/dev/null; then
    export CFGD_AVAILABLE=true
  else
    export CFGD_AVAILABLE=false
  fi
}

# Full check — called by compile.sh only (includes version metadata)
clift_check_deps_full() {
  clift_check_deps_fast || return 1

  # Framework metadata: version export + task version validation
  if [[ -n "${FRAMEWORK_DIR:-}" ]] && [[ -f "$FRAMEWORK_DIR/.clift.yaml" ]]; then
    CLIFT_VERSION="$(yq '.version' "$FRAMEWORK_DIR/.clift.yaml")"
    export CLIFT_VERSION

    local _min_task_version
    _min_task_version="$(yq '.min_task_version // ""' "$FRAMEWORK_DIR/.clift.yaml")"

    if [[ -n "$_min_task_version" ]] && command -v task &>/dev/null; then
      local _current_task_version
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
  fi
}
