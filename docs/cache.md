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

## Cache control

Override the cache's automatic behavior via the `CLIFT_CACHE` env var or the
`--no-cache` global flag.

### `--no-cache`

```bash
mycli --no-cache deploy prod
```

Force the cache to rebuild before running the command. Equivalent to
`CLIFT_CACHE=rebuild`. The flag is recognized by the wrapper and stripped
from argv before dispatch — user commands never see it. The scan stops at
`--` per bash convention, so `mycli greet -- --no-cache` passes the token
through as a literal positional.

Use this after editing a Taskfile by hand when you want to confirm the
next invocation reads fresh state.

### `CLIFT_CACHE=rebuild`

Force a rebuild without the flag — useful for scripted workflows and CI
steps that need to guarantee a fresh cache without parsing argv.

```bash
CLIFT_CACHE=rebuild mycli deploy prod
```

Explicit rebuild requests always compile, even under lock contention: if
two concurrent processes both set `CLIFT_CACHE=rebuild`, the winner of the
lock compiles and the loser waits, and when the loser acquires the lock it
compiles again. This matches the user intent — every explicit rebuild
request actually rebuilds.

### `CLIFT_CACHE=bypass`

Skip the cache machinery entirely. `clift_ensure_cache` becomes a no-op —
no staleness check, no rebuild, no `.clift/` directory creation. If a
cache already exists it is still read for dispatch; if it does not exist
the wrapper falls through to go-task directly (which emits its own
unknown-task error for unrecognized commands).

```bash
CLIFT_CACHE=bypass mycli somecmd
```

Use this when debugging the cache system itself, or when you're confident
the stored cache is up-to-date and want to skip the stat-based staleness
check on every invocation.

### When to use which

- **Regular development:** leave `CLIFT_CACHE` unset. The stat-based
  staleness check rebuilds automatically when any tracked Taskfile changes.
- **After hand-editing a Taskfile:** `--no-cache` on the next command
  makes the rebuild explicit.
- **In CI:** `CLIFT_CACHE=rebuild` on the first command in a fresh
  workspace makes the build step deterministic without relying on mtimes.
- **Debugging the cache itself:** `CLIFT_CACHE=bypass` to isolate
  cache-related behavior from command-dispatch behavior.

### Unknown values

`CLIFT_CACHE` values other than `rebuild` or `bypass` (including empty and
unset) fall through to the default stat-based staleness check. No error is
emitted — the env var is additive, not a gate.
