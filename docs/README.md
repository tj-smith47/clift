# clift documentation

User-facing documentation for clift, the CLI framework built on go-task.

Start with the [repo README](../README.md) for an install and a five-minute
tour. This directory holds the deep references you'll reach for as you build
out a CLI.

## Getting started

New to clift? Read in this order:

1. [Modes](modes.md) — **standard** (wrapper on PATH, Cobra-like) vs **task**
   (shell alias, raw go-task). Chosen at setup; changes how you invoke the CLI.
2. [Scripts](scripts.md) — what your command script looks like, the `CLIFT_FLAG_*`
   / `CLIFT_POS_*` / `CLIFT_FLAGS` env-var contract, subshell caveats,
   passthrough mode (commands with no `vars.FLAGS`), and `vars.HIDDEN: true`
   for hidden commands.
3. [Flags](flags.md) — schema reference: types, defaults, required, choices,
   pattern, aliases, hidden, deprecated, mutex / required-together groups,
   CLI-level persistent flags, and the reserved globals.
4. [Errors](errors.md) — error-message conventions and exit codes you can
   return from your scripts.

## Reference

Deeper material for anyone building a CLI on top of clift.

- [Architecture](architecture.md) — hot-path overview (wrapper → router →
  parser → script), per-stage timing, and component boundaries.
- [Cache](cache.md) — the `.clift/` layout, how staleness is detected via the
  `sources` manifest, and the `--no-cache` / `CLIFT_CACHE=rebuild|bypass`
  control modes.
- [Overrides](cli/overrides.md) — the override-slot loader. Per-command +
  CLI-global tiers (per-command wins, except `help_list`). Slots:
  `help_list`, `help_detail`, `version_print`, `log` (shadow-based),
  `command_pre`, `command_post`; plus the `clift_exit` helper.
- [Completion](cli/completion.md) — bash/zsh completion scripts. Static
  candidates from the cache, dynamic flag-value completers via
  `clift_complete_<task>_<flag>`, and the reserved `_complete` subcommand
  protocol.
- [go-task features](cli/task-features.md) — the `--task:*` passthrough
  (`watch`, `dry`, `parallel`, `status`, `summary`, `interval`, …), the
  `mycli watch <cmd>` shortcut, the reserved command-name list, and the
  per-task fields (`deps`, `preconditions`, `sources`, `status`, `dotenv`,
  `run`, `silent`, `platforms`, `generates`, `method`) that pass straight
  through to the go-task runner.

## External

- [taskfile.dev](https://taskfile.dev) — canonical go-task reference.
