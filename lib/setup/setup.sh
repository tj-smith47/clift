#!/usr/bin/env bash
# clift Setup — bootstraps a new CLI in a target directory.
# Usage: setup.sh <TARGET_DIR> <FRAMEWORK_DIR> <CLI_NAME> <CLI_VERSION> <LOG_THEME>

set -euo pipefail

TARGET="${1:-}"
FRAMEWORK_DIR="${2:-}"
CLI_NAME="${3:-}"
CLI_VERSION="${4:-0.1.0}"
LOG_THEME="${5:-icons-color}"
CLIFT_MODE="${6:-}"

if [[ -z "$TARGET" || -z "$FRAMEWORK_DIR" ]]; then
  echo "error: setup.sh requires TARGET_DIR and FRAMEWORK_DIR" >&2
  exit 1
fi

source "${FRAMEWORK_DIR}/lib/log/log.sh"

# Render a template file, replacing %%PLACEHOLDER%% tokens with bash parameter
# expansion. Avoids sed — immune to delimiter/metacharacter injection from paths.
_render_template() {
  local _tmpl="$1" _dest="$2"
  while IFS= read -r _line; do
    _line="${_line//%%FRAMEWORK_DIR%%/$FRAMEWORK_DIR}"
    _line="${_line//%%CLI_DIR%%/$TARGET}"
    _line="${_line//%%CLI_NAME%%/$CLI_NAME}"
    _line="${_line//%%CLI_VERSION%%/$CLI_VERSION}"
    _line="${_line//%%LOG_THEME%%/$LOG_THEME}"
    _line="${_line//%%CLIFT_MODE%%/$CLIFT_MODE}"
    printf '%s\n' "$_line"
  done < "$_tmpl" > "$_dest"
}

# Strip trailing Taskfile.yaml if full path was passed
if [[ "$TARGET" == *.yaml ]] || [[ "$TARGET" == *.yml ]]; then
  TARGET="$(dirname "$TARGET")"
fi

# Resolve to absolute path (portable — no realpath -m which is GNU-only)
if parent="$(cd "$(dirname "$TARGET")" 2>/dev/null && pwd)"; then
  _base="$(basename "$TARGET")"
  if [[ "$_base" == "." ]]; then
    TARGET="$parent"
  else
    TARGET="${parent}/${_base}"
  fi
else
  mkdir -p "$(dirname "$TARGET")"
  _base="$(basename "$TARGET")"
  parent="$(cd "$(dirname "$TARGET")" && pwd)"
  if [[ "$_base" == "." ]]; then
    TARGET="$parent"
  else
    TARGET="${parent}/${_base}"
  fi
fi

# Default CLI_NAME to directory basename
if [[ -z "$CLI_NAME" ]]; then
  CLI_NAME="$(basename "$TARGET")"
fi

# Validate CLI_NAME is a safe shell identifier
if [[ ! "$CLI_NAME" =~ ^[a-z][a-z0-9_-]*$ ]]; then
  die "CLI_NAME must be lowercase alphanumeric (got '${CLI_NAME}')"
fi

# Check for existing installation — offer per-field reconfigure
RECONFIGURE=false
if [[ -f "${TARGET}/.env" ]]; then
  log_warn "CLI already exists at ${TARGET}"
  if [[ "${RECONFIGURE_YES:-}" == "1" ]]; then
    response="y"
  else
    read -rp "Reconfigure? [y/N] " response </dev/tty
  fi
  if [[ ! "$response" =~ ^[Yy] ]]; then
    log_info "Setup cancelled"
    exit 0
  fi
  RECONFIGURE=true

  # Read current values from existing .env as defaults
  _read_env_val() {
    grep "^${1}=" "${TARGET}/.env" 2>/dev/null | head -1 | cut -d= -f2-
  }

  _current_name="$(_read_env_val CLI_NAME)"
  _current_version="$(_read_env_val CLI_VERSION)"
  _current_theme="$(_read_env_val LOG_THEME)"
  _current_mode="$(_read_env_val CLIFT_MODE)"
  CLIFT_MODE="${CLIFT_MODE:-${_current_mode:-}}"

  # Re-prompt with current values as defaults
  THEMES="icons,icons-color,brackets,brackets-color,minimal,minimal-color,custom"
  CLI_NAME=$("${FRAMEWORK_DIR}/lib/prompt/prompt.sh" input 'CLI name' --var _RECONFIG_NAME --default "${_current_name:-$CLI_NAME}")
  CLI_VERSION=$("${FRAMEWORK_DIR}/lib/prompt/prompt.sh" input 'Version' --var _RECONFIG_VERSION --default "${_current_version:-$CLI_VERSION}")
  LOG_THEME=$("${FRAMEWORK_DIR}/lib/prompt/prompt.sh" choose 'Log theme' --var _RECONFIG_THEME --options "$THEMES" --default "${_current_theme:-$LOG_THEME}")
fi

# Default mode: use arg if given, else saved value (from reconfigure), else task
CLIFT_MODE="${CLIFT_MODE:-task}"

case "$CLIFT_MODE" in
  task|standard) ;;
  *) echo "error: CLIFT_MODE must be 'task' or 'standard', got '$CLIFT_MODE'" >&2; exit 1 ;;
esac

# Create directory structure
mkdir -p "${TARGET}/cmds"

# Render .env
ENV_FILE="${TARGET}/.env"
if [[ "$RECONFIGURE" == "true" ]] || [[ ! -f "$ENV_FILE" ]]; then
  # Fresh render (new install or reconfigure)
  _render_template "${FRAMEWORK_DIR}/templates/cli/.env.tmpl" "$ENV_FILE"
else
  # First install but .env somehow exists without reconfigure — update paths only
  _tmp="$(mktemp)"
  while IFS= read -r _line; do
    if [[ "$_line" == "FRAMEWORK_DIR="* ]]; then
      printf 'FRAMEWORK_DIR=%s\n' "$FRAMEWORK_DIR"
    elif [[ "$_line" == "CLI_DIR="* ]]; then
      printf 'CLI_DIR=%s\n' "$TARGET"
    else
      printf '%s\n' "$_line"
    fi
  done < "$ENV_FILE" > "$_tmp"
  mv "$_tmp" "$ENV_FILE"
fi

# Render .clift.yaml (only if not exists)
METADATA="${TARGET}/.clift.yaml"
if [[ ! -f "$METADATA" ]]; then
  _render_template "${FRAMEWORK_DIR}/templates/cli/.clift.yaml.tmpl" "$METADATA"
fi

# Render Taskfile.yaml (only if not exists)
TASKFILE="${TARGET}/Taskfile.yaml"
if [[ ! -f "$TASKFILE" ]]; then
  _render_template "${FRAMEWORK_DIR}/templates/cli/Taskfile.yaml.tmpl" "$TASKFILE"
fi

# Render cfgd module.yaml only when cfgd versioning is requested
MODULE_FILE="${TARGET}/module.yaml"
if [[ "${CFGD_VERSIONING:-}" == "true" ]] && [[ ! -f "$MODULE_FILE" ]]; then
  _render_template "${FRAMEWORK_DIR}/templates/cli/module.yaml.tmpl" "$MODULE_FILE"
fi

# Copy CI workflow only when requested
CI_DIR="${TARGET}/.github/workflows"
if [[ "${CLIFT_CI:-}" == "true" ]] && [[ ! -f "${CI_DIR}/ci.yml" ]]; then
  mkdir -p "$CI_DIR"
  cp "${FRAMEWORK_DIR}/templates/cli/.github/workflows/ci.yml" "${CI_DIR}/ci.yml"
fi

source "${FRAMEWORK_DIR}/lib/setup/rc.sh"

SHELL_NAME="$(basename "${SHELL:-/bin/bash}")"
if [[ -n "${CLIFT_RC_FILE:-}" ]]; then
  RC_FILE="$CLIFT_RC_FILE"
else
  case "$SHELL_NAME" in
    zsh) RC_FILE="$HOME/.zshrc" ;;
    bash) RC_FILE="$HOME/.bashrc" ;;
    *) RC_FILE="$HOME/.${SHELL_NAME}rc" ;;
  esac
fi
touch "$RC_FILE"

# Scrub any existing entries (covers mode switches and completion re-install)
clift_rc_scrub "$RC_FILE" "$CLI_NAME"
clift_rc_scrub "$RC_FILE" "${CLI_NAME}-completion"
if [[ "$CLIFT_MODE" == "task" ]] && [[ -f "${TARGET}/bin/${CLI_NAME}" ]]; then
  rm -f "${TARGET}/bin/${CLI_NAME}"
fi

# Replace $HOME prefix with literal $HOME for portable rc entries
_portable_path() {
  local p="$1"
  if [[ -n "${HOME:-}" ]] && [[ "$p" == "$HOME"* ]]; then
    echo "\$HOME${p#"$HOME"}"
  else
    echo "$p"
  fi
}

if [[ "$CLIFT_MODE" == "task" ]]; then
  _ptarget="$(_portable_path "$TARGET")"
  _pfw="$(_portable_path "$FRAMEWORK_DIR")"
  ALIAS_LINE="alias ${CLI_NAME}='FRAMEWORK_DIR=\"${_pfw}\" task --taskfile \"${_ptarget}/Taskfile.yaml\"'"
  clift_rc_write "$RC_FILE" "$CLI_NAME" "$ALIAS_LINE"
else
  mkdir -p "${TARGET}/bin"
  _render_template "${FRAMEWORK_DIR}/lib/wrapper/wrapper.sh.tmpl" "${TARGET}/bin/${CLI_NAME}"
  chmod +x "${TARGET}/bin/${CLI_NAME}"
  _pbin="$(_portable_path "${TARGET}/bin")"
  PATH_LINE="export PATH=\"${_pbin}:\$PATH\""
  clift_rc_write "$RC_FILE" "$CLI_NAME" "$PATH_LINE"
fi

# Completion install — Task 5.3. Controlled by CLIFT_COMPLETIONS:
#   auto (default) → install when shell is bash or zsh; skip otherwise
#   true           → install (requires bash or zsh)
#   false          → skip
# Standard mode uses space-separated `completion bash`; task mode uses
# colon-separated `completion:bash` because the alias dispatches through
# go-task which resolves colon-joined task names.
CLIFT_COMPLETIONS="${CLIFT_COMPLETIONS:-auto}"
COMPLETION_INSTALLED=false
case "$CLIFT_COMPLETIONS" in
  auto|true)
    case "$SHELL_NAME" in
      bash|zsh)
        if [[ "$CLIFT_MODE" == "task" ]]; then
          COMP_LINE="source <(${CLI_NAME} completion:${SHELL_NAME})"
        else
          COMP_LINE="source <(${CLI_NAME} completion ${SHELL_NAME})"
        fi
        clift_rc_write "$RC_FILE" "${CLI_NAME}-completion" "$COMP_LINE"
        COMPLETION_INSTALLED=true
        ;;
      *)
        if [[ "$CLIFT_COMPLETIONS" == "true" ]]; then
          log_warn "CLIFT_COMPLETIONS=true but shell '${SHELL_NAME}' is not supported (bash or zsh only)"
        fi
        ;;
    esac
    ;;
  false) ;;
  *) log_warn "Ignoring unrecognized CLIFT_COMPLETIONS='${CLIFT_COMPLETIONS}' (use auto|true|false)" ;;
esac

# Precompile cache (may fail for fresh CLIs with no user commands yet)
bash "${FRAMEWORK_DIR}/lib/flags/compile.sh" "$TARGET" 2>/dev/null || true

echo ""
if [[ "$RECONFIGURE" == "true" ]]; then
  log_success "${CLI_NAME} reconfigured at ${TARGET}"
else
  log_success "${CLI_NAME} created at ${TARGET}"
  echo ""
  echo "Next steps:"
  echo "  source ${RC_FILE}"
  if [[ "$CLIFT_MODE" == "standard" ]]; then
    echo "  ${CLI_NAME}"
    echo "  ${CLI_NAME} new cmd"
  else
    echo "  ${CLI_NAME}"
    echo "  ${CLI_NAME} new:cmd"
  fi
  if [[ "$COMPLETION_INSTALLED" == "true" ]]; then
    echo ""
    echo "Shell completion for ${SHELL_NAME} installed — takes effect after 'source ${RC_FILE}'."
  fi
fi

# Set up cfgd versioning if requested
if [[ "${CFGD_VERSIONING:-}" == "true" && "$RECONFIGURE" != "true" ]]; then
  echo ""
  log_info "Setting up cfgd versioning..."
  CLI_NAME="$CLI_NAME" CLI_VERSION="$CLI_VERSION" \
    "${FRAMEWORK_DIR}/lib/version/setup.sh" "$TARGET" "$FRAMEWORK_DIR"
fi
