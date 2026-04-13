# Command Scripts

## One script per task

Each task has exactly one script file:

- `deploy` -- `cmds/deploy/deploy.sh`
- `deploy:prod` -- `cmds/deploy/deploy.prod.sh`
- `deploy:prod:us-east-1` -- `cmds/deploy/deploy.prod.us-east-1.sh`

Rule: replace `:` with `.` in the task name. The first colon segment is the directory. No case statements, no shared dispatch.

> **Note:** The one-script-per-task naming convention applies only to commands with `vars.FLAGS` (parsed mode). Passthrough commands (no `vars.FLAGS`) always resolve to the base script: `cmds/<cmd>/<cmd>.sh`.

## Env var contract

When your script runs (in parsed mode), these env vars are set by the router:

| Var | Content |
|---|---|
| `CLIFT_FLAG_<NAME>` | One per flag. `<NAME>` is uppercased, `-` becomes `_`. Unset if the flag is unset (unless a default applies). |
| `CLIFT_POS_1`, `CLIFT_POS_2`, ... | Positional arguments. |
| `CLIFT_POS_COUNT` | Number of positional args. |
| `CLIFT_TASK` | Full task name (e.g. `deploy:prod`). Informational. |
| `CLIFT_FLAG_<NAME>_1`, `..._COUNT` | List-typed flags. |
| `VERBOSE`, `QUIET`, `NO_COLOR` | Backward-compat env vars set from `--verbose`, `--quiet`, `--no-color` flags. Read by `log.sh` for theming. |

## Example script

```bash
#!/usr/bin/env bash
set -euo pipefail

source "${FRAMEWORK_DIR}/lib/log/log.sh"

# Bool flag
if [[ "${CLIFT_FLAG_DRY_RUN:-}" == "true" ]]; then
  log_info "dry run -- no changes will be made"
fi

# String flag with default
target="${CLIFT_FLAG_TARGET:-staging}"

# Required positional
file="${CLIFT_POS_1:?missing file argument}"

# List flag iteration
for i in $(seq 1 "${CLIFT_FLAG_TAG_COUNT:-0}"); do
  var="CLIFT_FLAG_TAG_$i"
  log_info "tag: ${!var}"
done

log_info "deploying ${file} to ${target}"
```

## Passthrough mode

Commands whose Taskfile has **no** `vars.FLAGS` key are passthrough commands. The router skips the parser entirely and execs the script with raw positional args (`$1`, `$2`, etc.). No `CLIFT_FLAG_*` env vars, no `--help` interception, no did-you-mean. The script handles its own arguments.

This is a valid choice for simple commands that don't need flags, or for scripts in other languages that have their own argument parsing.

