#!/usr/bin/env bash
# Generates shell completion scripts for DIYCLI.
# Usage: completion.sh <FORMAT> <TASKFILE_PATH> <CLI_NAME>
# FORMAT: bash or zsh

set -euo pipefail

FORMAT="${1:-}"
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
