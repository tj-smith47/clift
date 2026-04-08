#!/usr/bin/env bash
# DIYCLI Prompt System
# Usage:
#   prompt.sh input  'Label' --var VAR_NAME [--default VALUE]
#   prompt.sh choose 'Label' --var VAR_NAME --options 'a,b,c' [--default VALUE]
#
# Precedence:
#   1. Variable already set in environment → echo it, no prompt
#   2. PROMPT=false → use default or error
#   3. gum available → gum input/choose
#   4. fallback → read -p
#
# Outputs the value to stdout.

set -euo pipefail

_prompt_type=""
_prompt_label=""
_prompt_var=""
_prompt_default=""
_prompt_options=""

_parse_prompt_args() {
  _prompt_type="${1:-}"
  _prompt_label="${2:-}"
  shift 2 || { echo "error: prompt.sh requires type and label" >&2; exit 1; }

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --var)     _prompt_var="$2"; shift 2 ;;
      --default) _prompt_default="$2"; shift 2 ;;
      --options) _prompt_options="$2"; shift 2 ;;
      *) echo "error: unknown prompt.sh flag: $1" >&2; exit 1 ;;
    esac
  done

  if [[ -z "$_prompt_var" ]]; then
    echo "error: prompt.sh requires --var" >&2
    exit 1
  fi
}

_check_existing() {
  local val="${!_prompt_var:-}"
  if [[ -n "$val" ]]; then
    echo "$val"
    return 0
  fi
  return 1
}

_check_no_prompt() {
  if [[ "${PROMPT:-}" == "false" ]]; then
    if [[ -n "$_prompt_default" ]]; then
      echo "$_prompt_default"
      return 0
    else
      echo "error: missing required value for $_prompt_var (PROMPT=false, no default)" >&2
      exit 1
    fi
  fi
  return 1
}

_has_gum() {
  command -v gum &>/dev/null
}

_do_input() {
  local result=""
  if _has_gum; then
    if [[ -n "$_prompt_default" ]]; then
      result=$(gum input --placeholder "$_prompt_label" --value "$_prompt_default")
    else
      result=$(gum input --placeholder "$_prompt_label")
    fi
  else
    local prompt_text="$_prompt_label"
    if [[ -n "$_prompt_default" ]]; then
      prompt_text="$_prompt_label [$_prompt_default]"
    fi
    read -rp "$prompt_text: " result </dev/tty
    if [[ -z "$result" && -n "$_prompt_default" ]]; then
      result="$_prompt_default"
    fi
  fi

  if [[ -z "$result" ]]; then
    echo "error: no value provided for $_prompt_var" >&2
    exit 1
  fi

  echo "$result"
}

_do_choose() {
  if [[ -z "$_prompt_options" ]]; then
    echo "error: --options required for choose type" >&2
    exit 1
  fi

  local result=""
  IFS=',' read -ra opts <<< "$_prompt_options"

  if _has_gum; then
    result=$(printf '%s\n' "${opts[@]}" | gum choose)
  else
    echo "$_prompt_label:" >&2
    local i=1
    for opt in "${opts[@]}"; do
      echo "  $i) $opt" >&2
      ((i++))
    done
    local choice
    read -rp "Select [1-${#opts[@]}]: " choice </dev/tty
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#opts[@]} )); then
      result="${opts[$((choice-1))]}"
    elif [[ -n "$_prompt_default" ]]; then
      result="$_prompt_default"
    else
      echo "error: invalid selection" >&2
      exit 1
    fi
  fi

  echo "$result"
}

main() {
  _parse_prompt_args "$@"

  # Precedence 1: already set
  _check_existing && return 0

  # Precedence 2: PROMPT=false
  _check_no_prompt && return 0

  # Precedence 3 & 4: interactive (gum or read)
  case "$_prompt_type" in
    input)  _do_input ;;
    choose) _do_choose ;;
    *) echo "error: unknown prompt type: $_prompt_type" >&2; exit 1 ;;
  esac
}

main "$@"
