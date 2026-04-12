# Flag Schema

Flags are declared inside your command's `Taskfile.yaml` under `vars.FLAGS`.

## Location

Three layers, merged at precompile time:

1. **Root Taskfile** -- framework globals (`--help`, `--verbose`, `--quiet`, `--no-color`, `--version`). Shipped with every CLI.
2. **Command Taskfile** -- top-level `vars.FLAGS`. Applies to the command and all its subcommands.
3. **Subcommand** -- `tasks.<sub>.vars.FLAGS`. Applies to that one subcommand.

Later layers override earlier ones on `name` or `short` collision. That's how per-command short override works.

## Schema

Each flag is a map:

| Key | Required | Type | Rules |
|---|---|---|---|
| `name` | yes | string | `^[a-z][a-z0-9-]*$` -- lowercase, dash-separated, no underscores |
| `short` | no | single char | `^[a-zA-Z0-9]$` |
| `type` | yes | enum | `bool` \| `string` \| `int` \| `list` |
| `default` | no | string | Ignored for bool; for list, comma-separated (e.g. `"a,b,c"`) |
| `desc` | no | string | Help text |
| `required` | no | bool | Error if absent; cannot combine with `default` |

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

## Validation

Schemas are validated at scaffold time by `new:cmd` and `new:subcmd`, at `setup:cli`, and at cache rebuild. Errors surface immediately, not at first invocation.
