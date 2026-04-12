#!/usr/bin/env bash
# Generates shell completion scripts for clift.
# Usage: completion.sh <FORMAT> <TASKFILE_PATH> <CLI_NAME>
# FORMAT: bash or zsh

set -euo pipefail

FORMAT="${1:-}"

# Standard-mode completion: reads from .clift/tasks.json + .clift/flags.json
# instead of invoking `task --list-all --json` at generation time.
if [[ "${CLIFT_MODE:-task}" == "standard" ]]; then
  CLI_NAME="${CLI_NAME:-mycli}"

  if [[ -z "$FORMAT" ]]; then
    echo "error: completion.sh requires FORMAT argument" >&2
    exit 1
  fi

  case "$FORMAT" in
    bash)
      cat <<'BASH_STD'
_{{CLI_NAME}}_completions() {
  local cli_dir
  cli_dir="$(dirname "$(command -v {{CLI_NAME}})")"
  cli_dir="$(cd "$cli_dir/.." && pwd)"
  local tasks_json="$cli_dir/.clift/tasks.json"
  local flags_json="$cli_dir/.clift/flags.json"

  local cur="${COMP_WORDS[$COMP_CWORD]}"
  local prev="${COMP_WORDS[$COMP_CWORD-1]}"

  # Complete commands from .clift/tasks.json
  if [[ "$cur" != -* ]]; then
    local commands
    commands="$(jq -r '
      [.. | .tasks? // empty | .[]]
      | .[]
      | select(.name != "default")
      | select(.name | startswith("_") | not)
      | .name | gsub(":default$"; "")
    ' "$tasks_json" 2>/dev/null | sort -u)"
    COMPREPLY=($(compgen -W "$commands" -- "$cur"))
    return
  fi

  # Complete flags from .clift/flags.json
  if [[ -f "$flags_json" ]]; then
    local cmd="${COMP_WORDS[1]:-}"
    local flags
    flags="$(jq -r --arg cmd "$cmd:default" --arg cmd2 "$cmd" '
      (.[$cmd] // .[$cmd2] // [])
      | if type == "array" then
          .[] | "--\(.name)", (if .short then "-\(.short)" else empty end)
        else empty end
    ' "$flags_json" 2>/dev/null)"
    COMPREPLY=($(compgen -W "$flags" -- "$cur"))
  fi
}
complete -F _{{CLI_NAME}}_completions {{CLI_NAME}}
BASH_STD
      # Replace placeholder with actual CLI name
      ;;
    zsh)
      cat <<'ZSH_STD'
#compdef {{CLI_NAME}}
_{{CLI_NAME}}() {
  local cli_dir tasks_json flags_json
  cli_dir="${commands[{{CLI_NAME}}]:h:h}"
  tasks_json="$cli_dir/.clift/tasks.json"
  flags_json="$cli_dir/.clift/flags.json"

  local -a commands
  commands=($(jq -r '
    [.. | .tasks? // empty | .[]]
    | .[]
    | select(.name != "default")
    | select(.name | startswith("_") | not)
    | .name | gsub(":default$"; "")
  ' "$tasks_json" 2>/dev/null | sort -u))
  _describe 'command' commands
}
compdef _{{CLI_NAME}} {{CLI_NAME}}
ZSH_STD
      ;;
    *)
      echo "error: unknown format: $FORMAT (use 'bash' or 'zsh')" >&2
      exit 1
      ;;
  esac | sed "s/{{CLI_NAME}}/$CLI_NAME/g"
  exit 0
fi

TASKFILE_PATH="${2:-}"
CLI_NAME="${3:-}"

if [[ -z "$FORMAT" || -z "$TASKFILE_PATH" || -z "$CLI_NAME" ]]; then
  echo "error: completion.sh requires FORMAT, TASKFILE_PATH, and CLI_NAME" >&2
  exit 1
fi

# Get command names from task JSON, using the same filters as help/list.sh
commands=$(task --list-all --json --taskfile "$TASKFILE_PATH" 2>/dev/null | jq -r '
  .tasks[]
  | select(.name != "default")
  | select(.name | startswith("_") | not)
  | select(.name | test(":[_]") | not)
  | .name
  | gsub(":default$"; "")
' | sort -u)

case "$FORMAT" in
  bash)
    cat <<BASH
_${CLI_NAME}_completions() {
  local commands="${commands//$'\n'/ }"
  COMPREPLY=(\$(compgen -W "\$commands" -- "\${COMP_WORDS[\$COMP_CWORD]}"))
}
complete -F _${CLI_NAME}_completions ${CLI_NAME}
BASH
    ;;
  zsh)
    cat <<ZSH
#compdef ${CLI_NAME}
_${CLI_NAME}() {
  local -a commands=(${commands//$'\n'/ })
  _describe 'command' commands
}
compdef _${CLI_NAME} ${CLI_NAME}
ZSH
    ;;
  *)
    echo "error: unknown format: $FORMAT (use 'bash' or 'zsh')" >&2
    exit 1
    ;;
esac
