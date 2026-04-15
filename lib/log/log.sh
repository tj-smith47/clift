#!/usr/bin/env bash
# clift Logging System
# Provides: log_info, log_warn, log_error, log_success, log_debug, log_suggest, die
# Reads LOG_THEME, LOG_COLOR, NO_COLOR, VERBOSE, QUIET from environment.
# Themes: icons, icons-color, brackets, brackets-color, minimal, minimal-color, custom

if [[ -n "${_CLIFT_LOG_LOADED:-}" ]]; then return 0 2>/dev/null || true; fi
_CLIFT_LOG_LOADED=1

# Exit code constants
export EXIT_OK=0
export EXIT_ERROR=1
export EXIT_USAGE=2
export EXIT_NOT_FOUND=127

# ANSI color codes — overridable via LOG_CLR_* env vars for custom color schemes.
_CLR_RESET="${LOG_CLR_RESET:-\033[0m}"
_CLR_GREEN="${LOG_CLR_SUCCESS:-\033[0;32m}"
_CLR_YELLOW="${LOG_CLR_WARN:-\033[0;33m}"
_CLR_RED="${LOG_CLR_ERROR:-\033[0;31m}"
_CLR_BLUE="${LOG_CLR_INFO:-\033[0;34m}"
_CLR_CYAN="${LOG_CLR_DEBUG:-\033[0;36m}"
_CLR_DIM="${LOG_CLR_DIM:-\033[2m}"

# NO_COLOR standard: https://no-color.org
if [[ -n "${NO_COLOR:-}" ]]; then
  _CLR_RESET='' _CLR_GREEN='' _CLR_YELLOW='' _CLR_RED=''
  _CLR_BLUE='' _CLR_CYAN='' _CLR_DIM=''
fi

# Resolve theme (default: icons-color)
_LOG_THEME="${LOG_THEME:-icons-color}"

_log_format() {
  local level="$1"
  shift
  local msg="$*"

  local prefix=""
  local color=""

  case "$_LOG_THEME" in
    icons|icons-color)
      case "$level" in
        info)    prefix="→"; color="$_CLR_BLUE" ;;
        warn)    prefix="⚠"; color="$_CLR_YELLOW" ;;
        error)   prefix="✗"; color="$_CLR_RED" ;;
        success) prefix="✓"; color="$_CLR_GREEN" ;;
        debug)   prefix="●"; color="$_CLR_CYAN" ;;
      esac
      if [[ "$_LOG_THEME" == "icons-color" ]]; then
        printf '%b%s%b %s\n' "$color" "$prefix" "$_CLR_RESET" "$msg"
      else
        printf "%s %s\n" "$prefix" "$msg"
      fi
      ;;
    brackets|brackets-color)
      case "$level" in
        info)    prefix="[INFO]"; color="$_CLR_BLUE" ;;
        warn)    prefix="[WARN]"; color="$_CLR_YELLOW" ;;
        error)   prefix="[ERROR]"; color="$_CLR_RED" ;;
        success) prefix="[OK]"; color="$_CLR_GREEN" ;;
        debug)   prefix="[DEBUG]"; color="$_CLR_CYAN" ;;
      esac
      if [[ "$_LOG_THEME" == "brackets-color" ]]; then
        printf '%b%s%b %s\n' "$color" "$prefix" "$_CLR_RESET" "$msg"
      else
        printf "%s %s\n" "$prefix" "$msg"
      fi
      ;;
    minimal|minimal-color)
      case "$level" in
        info)    prefix=""; color="$_CLR_BLUE" ;;
        warn)    prefix="warn: "; color="$_CLR_YELLOW" ;;
        error)   prefix="error: "; color="$_CLR_RED" ;;
        success) prefix=""; color="$_CLR_GREEN" ;;
        debug)   prefix="debug: "; color="$_CLR_CYAN" ;;
      esac
      if [[ "$_LOG_THEME" == "minimal-color" ]]; then
        printf '%b%s%s%b\n' "$color" "$prefix" "$msg" "$_CLR_RESET"
      else
        printf "%s%s\n" "$prefix" "$msg"
      fi
      ;;
    custom)
      local fmt=""
      case "$level" in
        info)    fmt="${LOG_FMT_INFO:-→ %s}" ;;
        warn)    fmt="${LOG_FMT_WARN:-⚠ %s}" ;;
        error)   fmt="${LOG_FMT_ERROR:-✗ %s}" ;;
        success) fmt="${LOG_FMT_SUCCESS:-✓ %s}" ;;
        debug)   fmt="${LOG_FMT_DEBUG:-● %s}" ;;
      esac
      if [[ "${LOG_COLOR:-true}" == "true" ]]; then
        case "$level" in
          info)    color="$_CLR_BLUE" ;;
          warn)    color="$_CLR_YELLOW" ;;
          error)   color="$_CLR_RED" ;;
          success) color="$_CLR_GREEN" ;;
          debug)   color="$_CLR_CYAN" ;;
        esac
        local _formatted
        # shellcheck disable=SC2059
        printf -v _formatted "${fmt}" "$msg"
        printf '%b%s%b\n' "$color" "$_formatted" "$_CLR_RESET"
      else
        # shellcheck disable=SC2059
        printf "${fmt}\n" "$msg"
      fi
      ;;
    *)
      printf "%s: %s\n" "$level" "$msg"
      ;;
  esac
}

log_info()    { [[ "${QUIET:-}" == "true" ]] && return 0; _log_format info "$@"; }
log_warn()    { _log_format warn "$@" >&2; }
log_error()   { _log_format error "$@" >&2; }
log_success() { [[ "${QUIET:-}" == "true" ]] && return 0; _log_format success "$@"; }
log_debug()   { [[ "${VERBOSE:-}" != "true" ]] && return 0; _log_format debug "$@" >&2; }
log_suggest() { [[ "${QUIET:-}" == "true" ]] && return 0; printf '%b  %s%b\n' "$_CLR_DIM" "$*" "$_CLR_RESET" >&2; }

die() { log_error "$1"; exit "${2:-1}"; }

# Export log helpers so subshells spawned by user scripts (e.g.
# `$(bash -c '…')`) inherit them without having to re-source this file.
# `_log_format` is the private formatter that every public helper delegates
# to — it must be exported alongside them or subshells hit "command not found".
# The theme + color vars must also be exported so subshell output matches
# parent styling instead of falling through to the default case.
# `clift_exit` is added in Task 3.6 — do not list it here until it exists.
export -f log_info log_error log_warn log_success log_debug log_suggest die _log_format 2>/dev/null || true
export _LOG_THEME _CLR_RESET _CLR_GREEN _CLR_YELLOW _CLR_RED _CLR_BLUE _CLR_CYAN _CLR_DIM
