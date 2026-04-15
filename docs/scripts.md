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

## Shell options and auto-load

User scripts are sourced by the clift boot wrapper (`lib/runtime/exec.sh`) in
the same process where `set -euo pipefail` is established. Two consequences:

- **Scripts inherit `errexit`, `nounset`, and `pipefail` by default.** If you
  need to opt out for a region of your script, call `set +e` (or `set +u`,
  `set +o pipefail`) locally, then restore with `set -e`. You do not need to
  re-enable these at the top of your own script — they are already on.
- **Log helpers (`log_info`, `log_error`, `log_warn`, `log_success`,
  `log_debug`, `log_suggest`, `die`) are auto-loaded.** An explicit
  `source "${FRAMEWORK_DIR}/lib/log/log.sh"` line is no longer required in
  new scripts. Existing scripts that still source it keep working — the
  source guard makes the second load a no-op.
- **Use `${BASH_SOURCE[0]}` (not `$0`) to locate your script.** Because the
  boot wrapper `source`s the user script, `$0` resolves to the boot wrapper
  (or parent bash), not the script path. `${BASH_SOURCE[0]}` still resolves
  to the user script correctly.

## Example script

```bash
#!/usr/bin/env bash
# set -euo pipefail is already in effect; redeclare only if you prefer
# to be explicit. Use `set +e` locally for opt-out regions.

# log_info / log_error / log_warn / log_success / log_debug / die are
# auto-loaded — no explicit source needed.

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

## Hidden commands

Add `vars.HIDDEN: true` to a command's Taskfile to omit it from `--help` listings and shell completion while keeping it fully executable:

```yaml
# cmds/internal/Taskfile.yaml
version: '3'
vars:
  HIDDEN: true
  FLAGS: []
tasks:
  default:
    cmd: "'{{.FRAMEWORK_DIR}}/lib/router/router.sh' '{{.TASK}}'"
```

Use for debug tooling, deprecated commands during a removal window, or internal hooks. Typing `mycli internal` still works — the dispatcher never filters hidden commands.

### Casing rationale

`vars.HIDDEN` is ALL_CAPS to match the existing `vars.FLAGS` / `vars.PERSISTENT_FLAGS` **section marker** convention. Per-flag `hidden:` (see `docs/flags.md`) is lowercase because it's a flag **attribute**, not a section. The asymmetry is intentional.

