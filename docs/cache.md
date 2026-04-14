# The `.clift/` Cache

Every built CLI has a precompiled cache at `${CLI_DIR}/.clift/` that powers the runtime:

## Files

- **`tasks.json`** -- output of `task --list-all --json --nested` at build time. Used by the wrapper for command-path resolution.
- **`index.json`** -- consolidated per-task cache. Shape:
  ```json
  {
    "tasks": {
      "<name>": {
        "flags":   [...] | {"passthrough": true},
        "aliases": ["d", "dep"],
        "hidden":  false,
        "summary": "..."
      }
    }
  }
  ```
  The router, help, and completion all read from here.
- **`flags.json`** -- legacy flat view `{task: flags}` derived from `index.json` at build time. Kept as a compatibility shim for out-of-tree consumers; new framework code should read `index.json`.
- **`sources`** -- newline-separated list of every Taskfile the cache depends on. Written by `compile.sh`, read by `cache.sh` for mtime-based staleness checks. This is how the runtime knows which files to track without hardcoded globs.
- **`checksum`** -- max mtime (integer seconds) across all files listed in `sources`. Used to detect staleness.

## When it rebuilds

- On `setup:cli`
- On `new:cmd` / `new:subcmd` (scaffold)
- **Automatically** when the runtime finds the cache stale (any tracked Taskfile's mtime newer than `checksum`)

You can hand-edit a Taskfile and run `mycli something` -- the wrapper detects the staleness and rebuilds before dispatching.

## How staleness works

1. `compile.sh` writes `.clift/sources` listing every Taskfile it processed
2. `compile.sh` computes the max mtime across those files and writes it to `.clift/checksum`
3. On each invocation, `cache.sh` reads `.clift/sources`, recomputes the current max mtime, and compares it to `checksum`
4. If they differ (or `checksum` is missing), it forks `compile.sh` to rebuild

## Committing vs gitignoring

Both work:

- **Commit `.clift/`** for deterministic CI and reproducible builds. Runtime still auto-rebuilds on staleness, so local edits work fine.
- **Gitignore `.clift/`** if you prefer a clean repo. The cache regenerates on first use.

## Force rebuild

```bash
rm -rf ${CLI_DIR}/.clift
# next invocation rebuilds automatically
```
