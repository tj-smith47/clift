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

## The `_complete` subcommand (reserved protocol)

`_complete` is a **reserved top-level token** (alongside `watch`) — compile.sh
rejects any user task or alias declared with that name. It's the protocol the
generated completion script calls at TAB-press time; users never invoke it
directly except for debugging (see [Failure modes](#failure-modes)).

```
mycli _complete <task> <flag> <partial-word>
```

The generated script wraps `_complete` calls in a subshell; failures stay
silent so tab-completion never becomes noisy (full list in Failure modes
below). See [docs/cli/task-features.md](task-features.md) for the full
reserved-name list.

## Dynamic completers — convention, not declaration

When the user is completing a value after a long flag (`mycli deploy
--region <TAB>`), the generated script calls the `_complete` subcommand
above. `_complete` sources the completion override files and invokes the
matching function. **The function's existence is the registration** —
nothing in the Taskfile declares it.

### Function name

```
clift_complete_<task>_<flag>
```

- Colons in `<task>` → underscores (`deploy:prod` → `deploy_prod`).
- Dashes in `<flag>` → underscores (`dry-run` → `dry_run`).
- Partial word (what the user has typed so far) arrives as `$1`.
- Emit one candidate per line to stdout. Exit code is ignored.

### Where the function lives

Two tiers, **last-write-wins**: both files are sourced by `_complete`, in
per-command → CLI-global order. If both define the same function, the CLI-
global redefinition replaces the per-command one.

> **Note:** This precedence is **inverted** relative to the callback-slot
> overrides in [docs/cli/overrides.md](overrides.md) (where per-command
> wins by first-match). Completers use last-write-wins because both files
> are sourced unconditionally at dispatch time. A completer copy-pasted
> from a callback-slot example will get the direction backwards — set the
> authoritative version in `.clift/overrides/completion.sh` and treat per-
> command files as local fallbacks, not the other way around.

1. Per-command — `$CLI_DIR/cmds/<cmd-seg>/overrides/completion.sh` (sourced first)
2. CLI-global — `$CLI_DIR/.clift/overrides/completion.sh` (sourced last; wins)

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

### Positional completion

The same convention extends to **positional arguments** — use `pos<N>` in
place of the flag name. `N` is the 1-indexed position of the current token
after the fully-resolved task path, counting only non-flag words.

```
clift_complete_<task>_pos<N>
```

At `mycli deploy <TAB>` the completion script calls
`mycli _complete deploy pos1 <partial>`, which sources the override files
and invokes `clift_complete_deploy_pos1` if defined. Intervening flags
(`mycli deploy --force <TAB>`) do **not** advance the positional counter —
the TAB after `--force` still resolves to `pos1`.

Discovery, precedence, and failure-mode rules are identical to flag-value
completers (see above): live in the same override files, CLI-global wins
by last-write, missing functions fall through to subcommand completion.

```bash
# $CLI_DIR/cmds/deploy/overrides/completion.sh
clift_complete_deploy_pos1() {
  local prefix="${1:-}"
  for t in prod-east prod-west staging dev; do
    [[ "$t" == "$prefix"* ]] && printf '%s\n' "$t"
  done
}
```

`mycli deploy <TAB>` now offers `prod-east prod-west staging dev`;
`mycli deploy prod-<TAB>` narrows to `prod-east prod-west`.

**Higher positions** (`pos2`, `pos3`, …) work the same way. The
generator reads `.clift/index.json` at TAB-press time, walks non-flag
words longest-prefix against the real task table, and uses the first
unmatched word as the start of positionals. `mycli deploy prod-east
<TAB>` resolves `cmd_path` to `deploy` (because `deploy:prod-east` is
not a real task) and dispatches `pos2`, not `pos1` against a fictional
task.

```bash
clift_complete_deploy_pos2() {
  local prefix="${1:-}"
  for stage in canary stable rollback; do
    [[ "$stage" == "$prefix"* ]] && printf '%s\n' "$stage"
  done
}
```

### Interaction with the override system

Completers share the `.clift/overrides/` and `cmds/<cmd>/overrides/`
directories with framework-slot overrides (`help_list`, `version_print`,
etc.) but use a different naming prefix (`clift_complete_*` vs
`clift_override_*`). The two do not collide.

The `_complete` dispatcher sources override files in a subshell so a
broken override can never poison the wrapper's environment.
