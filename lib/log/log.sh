#!/usr/bin/env bash
# DIYCLI Logging System
# Provides: log_info, log_warn, log_error, log_success
# Reads LOG_THEME and LOG_COLOR from environment.
# Themes: icons, icons-color, brackets, brackets-color, minimal, minimal-color, custom

# ANSI color codes
_CLR_RESET='\033[0m'
_CLR_GREEN='\033[0;32m'
_CLR_YELLOW='\033[0;33m'
_CLR_RED='\033[0;31m'
_CLR_BLUE='\033[0;34m'

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
      esac
      if [[ "$_LOG_THEME" == "icons-color" ]]; then
        printf "${color}%s${_CLR_RESET} %s\n" "$prefix" "$msg"
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
      esac
      if [[ "$_LOG_THEME" == "brackets-color" ]]; then
        printf "${color}%s${_CLR_RESET} %s\n" "$prefix" "$msg"
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
      esac
      if [[ "$_LOG_THEME" == "minimal-color" ]]; then
        printf "${color}%s%s${_CLR_RESET}\n" "$prefix" "$msg"
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
      esac
      if [[ "${LOG_COLOR:-true}" == "true" ]]; then
        case "$level" in
          info)    color="$_CLR_BLUE" ;;
          warn)    color="$_CLR_YELLOW" ;;
          error)   color="$_CLR_RED" ;;
          success) color="$_CLR_GREEN" ;;
        esac
        printf "${color}${fmt}${_CLR_RESET}\n" "$msg"
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

log_info()    { _log_format info "$@"; }
log_warn()    { _log_format warn "$@" >&2; }
log_error()   { _log_format error "$@" >&2; }
log_success() { _log_format success "$@"; }
