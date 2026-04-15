# clift documentation

User-facing documentation for clift, the CLI framework built on go-task.

## Topics

- [Architecture](architecture.md) — hot-path overview, component boundaries.
- [Modes](modes.md) — standard vs task invocation modes.
- [Flags](flags.md) — schema, validation, persistent flags, reading parsed values.
- [Scripts](scripts.md) — command scripts and the env-var contract.
- [Cache](cache.md) — `.clift/` layout and staleness rules.
- [Errors](errors.md) — error-message conventions and exit codes.

## CLI-author reference

Deeper references for people building a CLI on top of clift. Future Phase 3/4 docs (e.g. `cli/caching.md`, `cli/overrides.md`) land in this section.

- [go-task features](cli/task-features.md) — passthrough task fields (`deps`, `preconditions`, `sources`, etc.) available in command Taskfiles.
- [Overrides](cli/overrides.md) — override-slot loader, per-command + CLI-global tiers, callback signature.

For the canonical go-task reference, see [taskfile.dev](https://taskfile.dev).
