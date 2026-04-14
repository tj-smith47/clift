#!/usr/bin/env bash
# Generates shell completion scripts for clift.
# Usage: completion.sh <FORMAT> <TASKFILE_PATH> <CLI_NAME>
# FORMAT: bash or zsh

set -euo pipefail

FORMAT="${1:-}"

# Standard-mode completion: reads from .clift/tasks.json + .clift/index.json
# instead of invoking `task --list-all --json` at generation time.
if [[ "${CLIFT_MODE:-task}" == "standard" ]]; then
  CLI_NAME="${CLI_NAME:-mycli}"

  if [[ -z "$FORMAT" ]]; then
    echo "error: completion.sh requires FORMAT argument" >&2
    exit 1
  fi

  case "$FORMAT" in
    bash)
      cat <<BASH_STD
_${CLI_NAME}_completions() {
  local cli_dir
  cli_dir="\$(dirname "\$(command -v ${CLI_NAME})")"
  cli_dir="\$(cd "\$cli_dir/.." && pwd)"
  local tasks_json="\$cli_dir/.clift/tasks.json"
  local index_json="\$cli_dir/.clift/index.json"

  local cur="\${COMP_WORDS[\$COMP_CWORD]}"

  # Build the command path from words 1..(CWORD-1)
  local cmd_path=""
  local i
  for (( i=1; i<COMP_CWORD; i++ )); do
    local w="\${COMP_WORDS[\$i]}"
    [[ "\$w" == -* ]] && continue
    if [[ -z "\$cmd_path" ]]; then
      cmd_path="\$w"
    else
      cmd_path="\${cmd_path}:\${w}"
    fi
  done

  # Complete flags — hidden flags are filtered out
  if [[ "\$cur" == -* ]] && [[ -f "\$index_json" ]]; then
    local lookup="\${cmd_path}:default"
    [[ -z "\$cmd_path" ]] && lookup=""
    local flags
    flags="\$(jq -r --arg cmd "\$lookup" --arg cmd2 "\$cmd_path" '
      (.tasks[\$cmd].flags // .tasks[\$cmd2].flags // [])
      | if type == "array" then
          .[] | select(.hidden != true) | "--\(.name)", (if .short then "-\(.short)" else empty end)
        else empty end
    ' "\$index_json" 2>/dev/null)"
    COMPREPLY=(\$(compgen -W "\$flags" -- "\$cur"))
    return
  fi

  # Complete subcommands: offer the next segment after cmd_path.
  # Hidden commands (vars.HIDDEN: true) are filtered out via index.json lookup.
  local all_tasks
  all_tasks="\$(jq -r --slurpfile idx "\$index_json" '
    ([\$idx[0].tasks // {} | to_entries[] | select(.value.hidden == true) | .key] // []) as \$hidden |
    [.. | .tasks? // empty | .[]] | .[]
    | select(.name != "default")
    | select(.name | startswith("_") | not)
    | .name as \$n
    | (\$n | gsub(":default\$"; "")) as \$disp
    | select((\$hidden | index(\$n)) == null and (\$hidden | index(\$disp)) == null)
    | \$disp
  ' "\$tasks_json" 2>/dev/null)"
  local prefix="\$cmd_path"
  [[ -n "\$prefix" ]] && prefix="\${prefix}:"
  local candidates
  candidates="\$(echo "\$all_tasks" | grep "^\${prefix}" | sed "s|^\${prefix}||" | cut -d: -f1 | sort -u)"
  COMPREPLY=(\$(compgen -W "\$candidates" -- "\$cur"))
}
complete -F _${CLI_NAME}_completions ${CLI_NAME}
BASH_STD
      ;;
    zsh)
      cat <<ZSH_STD
#compdef ${CLI_NAME}
_${CLI_NAME}() {
  local cli_dir tasks_json index_json
  cli_dir="\${commands[${CLI_NAME}]:h:h}"
  tasks_json="\$cli_dir/.clift/tasks.json"
  index_json="\$cli_dir/.clift/index.json"

  # Build colon-joined command path from words before cursor
  # zsh words[] is 1-indexed; words[1] is the command name itself, so start at 2
  local cmd_path=""
  local i
  for (( i=2; i<CURRENT; i++ )); do
    local w="\${words[\$i]}"
    [[ "\$w" == -* ]] && continue
    if [[ -z "\$cmd_path" ]]; then
      cmd_path="\$w"
    else
      cmd_path="\${cmd_path}:\${w}"
    fi
  done

  # Complete flags — hidden flags are filtered out
  if [[ "\${words[\$CURRENT]}" == -* ]] && [[ -f "\$index_json" ]]; then
    local lookup="\${cmd_path}:default"
    [[ -z "\$cmd_path" ]] && lookup=""
    local -a flags
    flags=(\$(jq -r --arg cmd "\$lookup" --arg cmd2 "\$cmd_path" '
      (.tasks[\$cmd].flags // .tasks[\$cmd2].flags // [])
      | if type == "array" then
          .[] | select(.hidden != true) | "--\(.name)", (if .short then "-\(.short)" else empty end)
        else empty end
    ' "\$index_json" 2>/dev/null))
    _describe 'flag' flags
    return
  fi

  local prefix="\$cmd_path"
  [[ -n "\$prefix" ]] && prefix="\${prefix}:"

  # Subcommands: filter out hidden commands via index.json
  local -a subcmds
  subcmds=(\$(jq -r --slurpfile idx "\$index_json" '
    ([\$idx[0].tasks // {} | to_entries[] | select(.value.hidden == true) | .key] // []) as \$hidden |
    [.. | .tasks? // empty | .[]] | .[]
    | select(.name != "default")
    | select(.name | startswith("_") | not)
    | .name as \$n
    | (\$n | gsub(":default\$"; "")) as \$disp
    | select((\$hidden | index(\$n)) == null and (\$hidden | index(\$disp)) == null)
    | \$disp
  ' "\$tasks_json" 2>/dev/null | grep "^\${prefix}" | sed "s|^\${prefix}||" | cut -d: -f1 | sort -u))
  _describe 'command' subcmds
}
compdef _${CLI_NAME} ${CLI_NAME}
ZSH_STD
      ;;
    *)
      echo "error: unknown format: $FORMAT (use 'bash' or 'zsh')" >&2
      exit 1
      ;;
  esac
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
