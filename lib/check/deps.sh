#!/usr/bin/env bash
# Validates dependencies for DIYCLI.
# Reads required/optional deps from .task-cli.yaml (framework and CLI).
# Required deps: exit 1 if missing (with install hint).
# Optional deps: warn but continue.
# Also validates task version and exports framework version.

set -euo pipefail

_check_cmd() {
  command -v "$1" &>/dev/null
}

# Parse deps from a .task-cli.yaml file using jq
# Args: <yaml_path> <dep_type: required|optional>
# Outputs: name<TAB>install_hint per line
_read_deps() {
  local yaml_file="$1" dep_type="$2"
  [[ ! -f "$yaml_file" ]] && return 0

  # Convert simple YAML dep list to JSON for jq
  # Handles both "- name: x" objects and bare "- x" strings
  local in_section=false
  local current_name="" current_install=""

  while IFS= read -r line; do
    # Detect section headers
    if [[ "$line" =~ ^[[:space:]]*${dep_type}:[[:space:]]*(.*) ]]; then
      in_section=true
      # Check for inline empty array
      local rest="${BASH_REMATCH[1]}"
      if [[ "$rest" == "[]" ]]; then
        in_section=false
      fi
      continue
    fi

    # Exit section on next top-level key or different section
    if $in_section && [[ "$line" =~ ^[[:space:]]{0,2}[a-z] ]] && [[ ! "$line" =~ ^[[:space:]]{4} ]]; then
      in_section=false
      # Flush last entry
      if [[ -n "$current_name" ]]; then
        printf '%s\t%s\n' "$current_name" "$current_install"
        current_name="" current_install=""
      fi
      continue
    fi

    if ! $in_section; then
      continue
    fi

    # Parse list entries
    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]*(.*) ]]; then
      # Flush previous entry
      if [[ -n "$current_name" ]]; then
        printf '%s\t%s\n' "$current_name" "$current_install"
        current_install=""
      fi
      current_name="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^[[:space:]]*install:[[:space:]]*(.*) ]]; then
      current_install="${BASH_REMATCH[1]}"
      # Strip surrounding quotes
      current_install="${current_install#\"}"
      current_install="${current_install%\"}"
    elif [[ "$line" =~ ^[[:space:]]*-[[:space:]]+(.*) ]]; then
      # Bare string entry: "- jq"
      if [[ -n "$current_name" ]]; then
        printf '%s\t%s\n' "$current_name" "$current_install"
      fi
      current_name="${BASH_REMATCH[1]}"
      current_install=""
    fi
  done < "$yaml_file"

  # Flush final entry
  if [[ -n "$current_name" ]]; then
    printf '%s\t%s\n' "$current_name" "$current_install"
  fi
}

# Check dependencies from a config file
# Args: <yaml_path> <label: "Framework"|"CLI">
_check_deps_from() {
  local yaml_file="$1"
  local missing_required=false

  # Check required deps
  while IFS=$'\t' read -r name install_hint; do
    [[ -z "$name" ]] && continue
    if ! _check_cmd "$name"; then
      echo "error: ${name} is required but not installed." >&2
      if [[ -n "$install_hint" ]]; then
        echo "  Install: ${install_hint}" >&2
      fi
      missing_required=true
    fi
  done < <(_read_deps "$yaml_file" "required")

  if $missing_required; then
    exit 1
  fi

  # Check optional deps
  while IFS=$'\t' read -r name install_hint; do
    [[ -z "$name" ]] && continue
    if _check_cmd "$name"; then
      local upper_name="${name^^}"
      upper_name="${upper_name//-/_}"
      export "${upper_name}_AVAILABLE=true"
    else
      local upper_name="${name^^}"
      upper_name="${upper_name//-/_}"
      export "${upper_name}_AVAILABLE=false"
      if [[ "${DEPS_WARN:-}" == "true" ]]; then
        echo "warn: ${name} not found — some features may be limited." >&2
        if [[ -n "$install_hint" ]]; then
          echo "  Install: ${install_hint}" >&2
        fi
      fi
    fi
  done < <(_read_deps "$yaml_file" "optional")
}

# Check framework deps
if [[ -n "${FRAMEWORK_DIR:-}" ]] && [[ -f "$FRAMEWORK_DIR/.task-cli.yaml" ]]; then
  _check_deps_from "$FRAMEWORK_DIR/.task-cli.yaml"

  # Export framework version
  DIYCLI_VERSION="$(grep '^version:' "$FRAMEWORK_DIR/.task-cli.yaml" | sed 's/version:[[:space:]]*//')"
  export DIYCLI_VERSION

  # Task version validation
  _min_task_version="$(grep 'min_task_version' "$FRAMEWORK_DIR/.task-cli.yaml" | sed 's/.*"\(.*\)".*/\1/' || true)"

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

# Check CLI-specific deps
if [[ -n "${CLI_DIR:-}" ]] && [[ -f "$CLI_DIR/.task-cli.yaml" ]]; then
  _check_deps_from "$CLI_DIR/.task-cli.yaml"
fi
