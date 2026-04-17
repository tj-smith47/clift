# Completion

clift generates bash and zsh completion from the compiled `.clift/` cache.
Static candidates (commands, subcommands, flags) come from the cache for
free. For flag **values** that are only known at runtime (regions, branches,
kube contexts, etc.), drop a shell function per the convention below and
clift wires it automatically.

## Installation

During `setup:cli` clift writes a shell-rc entry that sources the completion
output at every shell startup:

```bash
# clift: mycli-completion
source <(mycli completion bash)        # standard mode
source <(mycli completion:bash)        # task mode
```

Skip with `CLIFT_COMPLETIONS=false`; force with `CLIFT_COMPLETIONS=true`
(warns and continues if the shell is not bash or zsh).

Manual install:

```bash
mycli completion bash > ~/.local/share/bash-completion/completions/mycli
mycli completion zsh  > "${fpath[1]}/_mycli"
```

## Static completion

No declaration needed. The generated script reads `.clift/tasks.json` and
`.clift/index.json` on every keystroke:

- subcommand segments at the current depth
- long flag names (`--foo`) and short aliases (`-f`) declared under `FLAGS`
- hidden commands and hidden flags (`hidden: true`) are filtered out
- command aliases (e.g., `dep` for `deploy`) appear as top-level candidates

## Dynamic completers — convention, not declaration

When the user is completing a value after a long flag (`mycli deploy
--region <TAB>`), the generated script calls the hidden `_complete`
subcommand:

```
mycli _complete <task> <flag> <partial-word>
```

`_complete` sources the completion override files and invokes the matching
function. **The function's existence is the registration** — nothing in the
Taskfile declares it.

### Function name

```
clift_complete_<task>_<flag>
```

- Colons in `<task>` → underscores (`deploy:prod` → `deploy_prod`).
- Dashes in `<flag>` → underscores (`dry-run` → `dry_run`).
- Partial word (what the user has typed so far) arrives as `$1`.
- Emit one candidate per line to stdout. Exit code is ignored.

### Where the function lives

Two tiers, first-match wins (per-command first in load order, CLI-global
redefines):

1. Per-command — `$CLI_DIR/cmds/<cmd-seg>/overrides/completion.sh`
2. CLI-global — `$CLI_DIR/.clift/overrides/completion.sh`

`<cmd-seg>` is the **first** colon segment of the task name. `deploy:prod`
looks in `cmds/deploy/overrides/completion.sh` — nested `cmds/deploy/prod/`
is **not** consulted (same rule as every other override slot).

### Example

```bash
# $CLI_DIR/.clift/overrides/completion.sh
clift_complete_deploy_region() {
  local prefix="${1:-}"
  for r in us-east-1 us-west-2 eu-west-1 ap-south-1; do
    [[ "$r" == "$prefix"* ]] && echo "$r"
  done
}

clift_complete_deploy_profile() {
  local prefix="${1:-}"
  aws configure list-profiles 2>/dev/null | grep "^${prefix}"
}
```

`mycli deploy --region <TAB>` now offers the region list;
`mycli deploy --region us-<TAB>` narrows to `us-east-1`, `us-west-2`.

### Failure modes

Tab-completion must never be noisy. The framework enforces this:

- Undefined completer → empty output, subcommand fallback.
- Override file missing → no-op.
- Override file has a syntax error → swallowed, no-op.
- Unsafe task or flag name (anything outside `[a-z0-9_:-]`) → silently rejected.
- Non-zero exit inside the completer → ignored.

A broken completer looks identical to an absent one: the user just gets no
suggestions for that value. Debug by invoking `_complete` directly:

```bash
mycli _complete deploy region us-
```

### Scope and trade-offs

- Long flags only. `-r <TAB>` (short form) falls through to subcommand
  completion — short-to-long mapping would require an extra cache read
  per TAB press.
- Space-separated form only. `--region=us-<TAB>` is treated as flag-name
  completion (consistent with cobra's default UX).
- Bool flags: if the user hits TAB after `--verbose`, `_complete` returns
  nothing and the generator falls through to subcommand completion — the
  useful default.

### Interaction with the override system

Completers share the `.clift/overrides/` and `cmds/<cmd>/overrides/`
directories with framework-slot overrides (`help_list`, `version_print`,
etc.) but use a different naming prefix (`clift_complete_*` vs
`clift_override_*`). The two do not collide.

The `_complete` dispatcher sources override files in a subshell so a
broken override can never poison the wrapper's environment.
