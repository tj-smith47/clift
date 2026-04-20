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

  # Task 5.5: dynamic completer for flag values. When prev is a long flag
  # and cur is a value slot (doesn't start with -), delegate to the hidden
  # \`_complete\` subcommand. If the completer is undefined or returns no
  # candidates, fall through to subcommand completion — ensures users with
  # bool flags still get expected behavior at \`--verbose <TAB>\`.
  if [[ -n "\$cmd_path" ]] && (( COMP_CWORD >= 1 )); then
    local _prev="\${COMP_WORDS[\$((COMP_CWORD-1))]}"
    if [[ "\$_prev" == --?* ]] && [[ "\$cur" != -* ]]; then
      local _flag="\${_prev#--}"
      _flag="\${_flag%%=*}"
      local _dyn
      _dyn="\$(${CLI_NAME} _complete "\$cmd_path" "\$_flag" "\$cur" 2>/dev/null)"
      if [[ -n "\$_dyn" ]]; then
        COMPREPLY=(\$(compgen -W "\$_dyn" -- "\$cur"))
        return
      fi
    fi
  fi

  # Task P1.1: dynamic completer for positional slots. After a task path is
  # resolved and the current word is not a flag value (prev != --foo) and
  # not itself a flag, delegate to \`_complete <task> pos<N>\` for the
  # cursor slot. If undefined or empty, fall through to subcommand
  # completion so unaffected commands keep working.
  #
  # NOTE: this block currently supports pos1 only. cmd_path greedily
  # colon-joins every non-flag word before the cursor, so the counter
  #   N = _nf - (colons in cmd_path)
  # collapses to 1 whenever a prior positional value is also a valid
  # path-segment token — \`mycli deploy foo <TAB>\` yields cmd_path
  # \`deploy:foo\` and dispatches pos1 (against a non-existent task),
  # not pos2. Correct pos2+ dispatch needs cache-aware resolution of
  # where the real task path ends, which requires reading
  # .clift/tasks.json at completion time. Tracked as a known limitation
  # (see docs/cli/completion.md and .claude/known-bugs.md); design
  # completers against pos1 only until cache-aware dispatch lands.
  if [[ -n "\$cmd_path" ]] && [[ "\$cur" != -* ]]; then
    local _nf=0
    local _j
    for (( _j=1; _j<COMP_CWORD; _j++ )); do
      local _w="\${COMP_WORDS[\$_j]}"
      [[ "\$_w" == -* ]] && continue
      _nf=\$(( _nf + 1 ))
    done
    local _colons="\${cmd_path//[^:]}"
    local _pos_n=\$(( _nf - \${#_colons} ))
    if (( _pos_n >= 1 )); then
      local _posfn="pos\${_pos_n}"
      local _pdyn
      _pdyn="\$(${CLI_NAME} _complete "\$cmd_path" "\$_posfn" "\$cur" 2>/dev/null)"
      if [[ -n "\$_pdyn" ]]; then
        COMPREPLY=(\$(compgen -W "\$_pdyn" -- "\$cur"))
        return
      fi
    fi
  fi

  # Complete subcommands: offer the next segment after cmd_path.
  # Hidden commands (vars.HIDDEN: true) are filtered out via index.json lookup.
  # Task 5.1: aliases declared on a command are included as additional
  # top-level candidates. compile.sh precomputes the user-facing form on
  # each task entry as \`user_aliases\` so we don't re-derive it here.
  local all_tasks
  all_tasks="\$(jq -r --slurpfile idx "\$index_json" '
    [\$idx[0].tasks // {} | to_entries[] | select(.value.hidden == true) | .key] as \$hidden |
    [\$idx[0].tasks // {} | to_entries[]
      | .key as \$k
      | select((\$hidden | index(\$k)) == null)
      | (.value.user_aliases // [])[]
    ] as \$alias_names |
    ([
      [.. | .tasks? // empty | .[]] | .[]
      | select(.name != "default")
      | select(.name | startswith("_") | not)
      | .name as \$n
      | (\$n | gsub(":default\$"; "")) as \$disp
      | select((\$hidden | index(\$n)) == null and (\$hidden | index(\$disp)) == null)
      | \$disp
    ] + \$alias_names) | .[]
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

  # Task 5.5: dynamic completer for flag values (see bash branch for rationale).
  if [[ -n "\$cmd_path" ]] && (( CURRENT >= 2 )); then
    local _prev="\${words[\$((CURRENT-1))]}"
    local _cur="\${words[\$CURRENT]}"
    if [[ "\$_prev" == --?* ]] && [[ "\$_cur" != -* ]]; then
      local _flag="\${_prev#--}"
      _flag="\${_flag%%=*}"
      local -a _dyn
      _dyn=("\${(@f)\$(${CLI_NAME} _complete "\$cmd_path" "\$_flag" "\$_cur" 2>/dev/null)}")
      if (( \${#_dyn[@]} > 0 )) && [[ -n "\${_dyn[1]}" ]]; then
        _describe 'value' _dyn
        return
      fi
    fi
  fi

  # Task P1.1: dynamic completer for positional slots. Supports pos1 only;
  # pos2+ collapses to pos1 because cmd_path greedily colon-joins every
  # non-flag word before the cursor (see bash branch above and
  # docs/cli/completion.md for the full rationale). zsh words[] is
  # 1-indexed; words[1] is the command name itself so non-flag counting
  # starts at index 2.
  if [[ -n "\$cmd_path" ]] && [[ "\${words[\$CURRENT]}" != -* ]]; then
    local _nf=0
    local _j
    for (( _j=2; _j<CURRENT; _j++ )); do
      local _w="\${words[\$_j]}"
      [[ "\$_w" == -* ]] && continue
      _nf=\$(( _nf + 1 ))
    done
    local _colons="\${cmd_path//[^:]}"
    local _pos_n=\$(( _nf - \${#_colons} ))
    if (( _pos_n >= 1 )); then
      local _posfn="pos\${_pos_n}"
      local -a _pdyn
      _pdyn=("\${(@f)\$(${CLI_NAME} _complete "\$cmd_path" "\$_posfn" "\${words[\$CURRENT]}" 2>/dev/null)}")
      if (( \${#_pdyn[@]} > 0 )) && [[ -n "\${_pdyn[1]}" ]]; then
        _describe 'value' _pdyn
        return
      fi
    fi
  fi

  local prefix="\$cmd_path"
  [[ -n "\$prefix" ]] && prefix="\${prefix}:"

  # Subcommands: filter out hidden commands via index.json
  # Task 5.1: aliases included as top-level candidates (see bash branch).
  local -a subcmds
  subcmds=(\$(jq -r --slurpfile idx "\$index_json" '
    [\$idx[0].tasks // {} | to_entries[] | select(.value.hidden == true) | .key] as \$hidden |
    [\$idx[0].tasks // {} | to_entries[]
      | .key as \$k
      | select((\$hidden | index(\$k)) == null)
      | (.value.user_aliases // [])[]
    ] as \$alias_names |
    ([
      [.. | .tasks? // empty | .[]] | .[]
      | select(.name != "default")
      | select(.name | startswith("_") | not)
      | .name as \$n
      | (\$n | gsub(":default\$"; "")) as \$disp
      | select((\$hidden | index(\$n)) == null and (\$hidden | index(\$disp)) == null)
      | \$disp
    ] + \$alias_names) | .[]
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
