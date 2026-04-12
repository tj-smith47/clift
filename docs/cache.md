# The `.clift/` Cache

Every built CLI has a precompiled cache at `${CLI_DIR}/.clift/` that powers the runtime:

## Files

- **`tasks.json`** -- output of `task --list-all --json --nested` at build time. Used by the wrapper for command-path resolution and by help/completion.
- **`flags.json`** -- merged flag tables per task. Each key is a task name; each value is either an array of flag maps or `{"legacy": true}`.
- **`checksum`** -- max mtime (integer seconds) across all relevant Taskfiles. Used to detect staleness.

## When it rebuilds

- On `setup:cli`
- On `new:cmd` / `new:subcmd` (scaffold)
- **Automatically** when the runtime finds the cache stale (any Taskfile mtime newer than `checksum`)

You can hand-edit a Taskfile and run `mycli something` -- the wrapper detects the staleness and rebuilds before dispatching.

## Committing vs gitignoring

Both work:

- **Commit `.clift/`** for deterministic CI and reproducible builds. Runtime still auto-rebuilds on staleness, so local edits work fine.
- **Gitignore `.clift/`** if you prefer a clean repo. The cache regenerates on first use.

## Force rebuild

```bash
rm -rf ${CLI_DIR}/.clift
# next invocation rebuilds automatically
```
