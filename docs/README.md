# clift documentation

User-facing documentation for clift, the CLI framework built on go-task.

## Topics

- [Architecture](architecture.md) — hot-path overview, component boundaries.
- [Modes](modes.md) — standard vs task invocation modes.
- [Flags](flags.md) — schema, value validation (`choices:` / `pattern:`), persistent flags, flag aliases, mutex / required-together groups, hidden flags, deprecated markers, reading parsed values.
- [Scripts](scripts.md) — command scripts and the env-var contract.
- [Cache](cache.md) — `.clift/` layout, staleness rules, and `--no-cache` / `CLIFT_CACHE=rebuild|bypass` control.
- [Errors](errors.md) — error-message conventions and exit codes.

## CLI-author reference

Deeper references for people building a CLI on top of clift.

- [go-task features](cli/task-features.md) — `--task:*` passthrough (`watch`, `dry`, `parallel`, `interval`, …), `mycli watch <cmd>` shortcut, plus passthrough task fields (`deps`, `preconditions`, `sources`, etc.) available in command Taskfiles.
- [Overrides](cli/overrides.md) — override-slot loader, per-command + CLI-global tiers, callback signature. Slots: `help_list`, `help_detail`, `version_print`, `log` (shadow), `command_pre`, `command_post`.
- [Completion](cli/completion.md) — static completion derived from the cache, plus dynamic flag-value completers via `clift_complete_<task>_<flag>`.

For the canonical go-task reference, see [taskfile.dev](https://taskfile.dev).
