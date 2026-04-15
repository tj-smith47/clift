# Flag Schema

Flags are declared inside your command's `Taskfile.yaml` under `vars.FLAGS`.

## Location

Three layers, merged at precompile time:

1. **Framework globals** (`lib/flags/globals.json`) -- `--help`, `--verbose`, `--quiet`, `--no-color`, `--version`. Merged into every parsed command at compile time (from the root Taskfile's `vars.FLAGS`) and at runtime (from `globals.json`).
2. **Command Taskfile** -- top-level `vars.FLAGS`. Applies to the command and all its subcommands.
3. **Subcommand** -- `tasks.<sub>.vars.FLAGS`. Applies to that one subcommand.

Later layers override earlier ones on `name` or `short` collision. That's how per-command short override works.

## Schema

Each flag is a map:

| Key | Required | Type | Rules |
|---|---|---|---|
| `name` | yes | string | `^[a-z][a-z0-9-]*$` -- lowercase, dash-separated, no underscores |
| `short` | no | single char | `^[a-zA-Z0-9]$` |
| `aliases` | no | list of string | Alternate long names. Each must match the `name` regex and cannot collide with any other flag's name or alias in the same layer. |
| `type` | yes | enum | `bool` \| `string` \| `int` \| `list` |
| `default` | no | string | Ignored for bool; for list, comma-separated (e.g. `"a,b,c"`) |
| `desc` | no | string | Help text |
| `required` | no | bool | Error if absent; cannot combine with `default` |
| `deprecated` | no | string | Deprecation message. Using the flag emits `warning: --<name> is deprecated: <msg>` to stderr once per invocation and marks the flag `(deprecated)` in help output. Empty string is treated as "not deprecated". |
| `hidden` | no | bool | If `true`, the flag is omitted from `--help` and shell completion but still parses normally when invoked. Useful for internal/experimental flags. |

## Reserved names

`help`, `verbose`, `quiet`, `no-color`, `version` are reserved. Additionally, `task`, `mode`, and names starting with `arg-` are reserved to avoid env-var namespace collisions (`CLIFT_TASK`, `CLIFT_MODE`, `CLIFT_ARG_*`). You can override the *short* alias (e.g., `-v` = `--value`) but not the long name.

## Examples

### Bool

```yaml
- {name: force, short: f, type: bool, desc: "Skip confirmation"}
```

Script reads: `${CLIFT_FLAG_FORCE:-false}` -- `"true"` or unset.

### String with default

```yaml
- {name: target, short: t, type: string, default: staging, desc: "Target env"}
```

Script reads: `${CLIFT_FLAG_TARGET}` -- always set (default applied if absent).

### Int, required

```yaml
- {name: count, short: c, type: int, required: true, desc: "Retry count"}
```

Parser validates integer; negative values (`--count -5`) work.

### List

```yaml
- {name: tag, type: list, default: "a,b", desc: "Tags"}
```

Script reads: `CLIFT_FLAG_TAG_1`, `CLIFT_FLAG_TAG_2`, ..., `CLIFT_FLAG_TAG_COUNT`.

### Aliases

```yaml
- {name: format, aliases: [output, fmt], type: string, default: json, desc: "Output format"}
```

Users can invoke any of `--format`, `--output`, or `--fmt` -- all resolve to the same canonical flag, so the script reads `${CLIFT_FLAG_FORMAT}` regardless of which spelling was used. Aliases share the same `CLIFT_FLAG_<NAME>` env var as the canonical name. Aliases are rendered alongside the canonical long flag in `--help` output.

### Hidden

```yaml
- {name: secret, type: string, hidden: true, desc: "Internal flag"}
```

`--secret=x` is accepted by the parser and surfaces as `CLIFT_FLAG_SECRET`, but is absent from `--help` and completion. Use for flags you don't want to advertise (experiments, deprecated shims before removal, internal tooling hooks).

### Deprecated

```yaml
- {name: old, type: string, deprecated: "use --new instead", desc: "legacy flag"}
```

Whenever the user supplies `--old` (or an alias, or the short form), the parser emits `warning: --old is deprecated: use --new instead` to stderr and continues to honor the flag's value. The warning fires at most once per invocation. In `--help` output the flag's description column gets a trailing ` (deprecated)` marker. An empty `deprecated: ""` is treated as "not deprecated" — no warning, no help marker.

## Persistent flags

Use persistent flags when multiple commands share the same flag (profile, verbosity, config-path). For flags specific to one command, prefer per-command `FLAGS`.

CLI-wide flags (e.g., `--profile`, `--config-file`) that every command should accept belong in the root Taskfile under `vars.PERSISTENT_FLAGS`. They're merged into every command's flag table at compile time and may appear either before or after the command token — Cobra's `PersistentFlags()` equivalent:

```yaml
vars:
  PERSISTENT_FLAGS:
    - {name: profile, short: p, type: string, default: "default", desc: "Profile name"}
```

Both `mycli --profile=staging deploy prod` and `mycli deploy prod --profile=staging` work. When both positions are supplied, last-write-wins (the post-command value replaces the pre-command value). Persistent flags are accessible via the same `CLIFT_FLAG_<NAME>` / `${CLIFT_FLAGS[name]}` machinery as per-command flags — no script change required.

Rules:

- A persistent flag cannot share its `name`, `aliases`, or `short` with a reserved framework global (`help`, `verbose`, `quiet`, `no-color`, `version`) or with any per-command flag. Compile fails with an error naming both layers.
- Persistent flags cannot declare `group`, `exclusive`, or `requires` (not yet supported — declare these on per-command flags only). Cross-layer group semantics are a scope decision, not a philosophical restriction.
- All other flag attributes (`type`, `default`, `required`, `deprecated`, `hidden`, `aliases`) work identically to per-command flags.

### Internal protocol: `CLIFT_PERSIST_BOUND`

`CLIFT_PERSIST_BOUND` is an internal wrapper-to-parser protocol. The wrapper exports the space-separated list of persistent flag names it early-bound (pre-command occurrences) so the parser can skip default application for those names — a wrapper-bound value is a user value and must outrank a default. Users should not set this manually; it is not part of the public contract and may change between releases.

## Validation

Schemas are validated at scaffold time by `new:cmd` and `new:subcmd`, at `setup:cli`, and at cache rebuild. Errors surface immediately, not at first invocation.
