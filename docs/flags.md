# Flag Schema

Flags are declared inside your command's `Taskfile.yaml` under `vars.FLAGS`.

## Location

Three layers, merged at precompile time:

1. **Framework globals** (`lib/flags/globals.json`) -- `--help`, `--verbose`, `--quiet`, `--no-color`, `--no-cache`, `--version`. Merged into every parsed command at compile time (from the root Taskfile's `vars.FLAGS`) and at runtime (from `globals.json`). `--no-cache` is a cache-control override owned by the wrapper — it overrides the `CLIFT_CACHE` env var when both are set; see [docs/cache.md](cache.md#cache-control).
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
| `choices` | no | list of string | Enumerated allowed values. Value must be one of the listed strings (case-sensitive). Invalid at runtime with `error: flag '--<name>' requires one of: a, b, c, got '<val>'`. For `type: list`, each element is validated. Cannot combine with `type: bool`. For `type: int`, each choice must itself parse as an integer (compile error otherwise). A `default` that is not in `choices` is a compile error. Rendered in `--help` as `(one of: a, b, c)`. |
| `pattern` | no | string | Bash-compatible regex (`[[ =~ ]]`). Value must match. Anchor with `^…$` yourself — not auto-wrapped. Invalid at runtime with `error: flag '--<name>' requires value matching pattern '<regex>', got '<val>'`. For `type: list`, each element is validated. Cannot combine with `type: bool`. Pattern is syntax-checked at compile time. Rendered in `--help` as `(matches: <pattern>)`. May be combined with `choices` (both checks run; choices first). |

## Reserved names

`help`, `verbose`, `quiet`, `no-color`, `no-cache`, `version` are reserved. Additionally, `task`, `mode`, and names starting with `arg-` are reserved to avoid env-var namespace collisions (`CLIFT_TASK`, `CLIFT_MODE`, `CLIFT_ARG_*`). You can override the *short* alias (e.g., `-v` = `--value`) but not the long name.

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

Repeatable / list flags accept two user-facing forms:

- Repeated flag: `mycli build --tag a --tag b --tag c`
- Comma-separated value: `mycli build --tag=a,b,c`

Both forms produce identical env vars — `a,b,c` in every case. With the `default: "a,b"` above, absent-on-command-line resolves to two elements (`a` and `b`).

Script reads (indexed env vars, subshell-safe):

```bash
for ((i=1; i<=${CLIFT_FLAG_TAG_COUNT:-0}; i++)); do
  v="CLIFT_FLAG_TAG_$i"
  echo "${!v}"
done
```

Or via the associative array (bash 4.2+, main process only — see [Accessing parsed flags](#accessing-parsed-flags-from-your-script)):

```bash
# Comma-joined string: "a,b,c". Lossy if an element contains a literal comma —
# use the indexed env vars above for that case.
IFS=',' read -ra tags <<< "${CLIFT_FLAGS[tag]:-}"
```

### Choices

```yaml
- {name: level, type: string, choices: [low, mid, high], default: mid, desc: "Verbosity"}
```

`--level=bogus` fails at runtime: `error: flag '--level' requires one of: low, mid, high, got 'bogus'`. Help rendering appends ` (one of: low, mid, high)` to the description. For `type: list`, each comma-split element must be in `choices`; the first invalid element is the one named in the error.

### Pattern

```yaml
- {name: tag, type: string, pattern: "^v[0-9]+\\.[0-9]+\\.[0-9]+$", desc: "Semver tag"}
```

`--tag=v1` fails at runtime: `error: flag '--tag' requires value matching pattern '^v[0-9]+\.[0-9]+\.[0-9]+$', got 'v1'`. The regex is evaluated by bash's `[[ =~ ]]`; anchor with `^…$` yourself. `pattern` and `choices` may be combined; both must pass. For `type: list`, the pattern is applied per element.

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

## Value validation

Two optional fields constrain accepted values beyond the type check: `choices` (enumerated allow-list) and `pattern` (regex). Both apply after the type check and after default application, so a stale default that is not in `choices` surfaces as a runtime error even when the user supplied no value.

### choices

```yaml
- {name: level, type: string, choices: [low, mid, high], default: mid, desc: "Log level"}
```

Value must be an exact-string match (case-sensitive) against one of the entries. For `type: list`, every element is validated; the first failing element reports the error naming the bad value. Combining `choices` with `type: bool` is a compile error (a bool carries no user-supplied value). For `type: int`, every entry in the list must itself parse as an integer — `choices: ["one", "two"]` on an int flag is a compile error, since no user value could ever satisfy both the type and the choice list. An empty `choices: []` is rejected at compile (no value could pass). A non-array `choices` value (e.g., `choices: "a,b,c"`) is a compile error — the field must be a YAML list. A `default` that is not a member of `choices` is rejected at compile (catches narrowing `choices` without updating a stale default).

### pattern

```yaml
- {name: ref, type: string, pattern: "^v[0-9]+\\.[0-9]+\\.[0-9]+$", desc: "Semver tag"}
```

Regex is applied with bash's `[[ =~ ]]` operator. Anchor with `^…$` yourself — the framework does not wrap. The pattern is syntax-checked at compile time (an invalid regex is rejected with a clear error; malformed patterns cannot ship). An empty `pattern: ""` is a compile error. A pattern containing a literal newline is rejected at compile (the runtime `[[ =~ ]]` test can't match across newlines — almost always a YAML block-literal mishap). Same list / bool rules as `choices`.

### Combining choices and pattern

The two fields may appear on the same flag. Both checks run; `choices` is checked first, so a value failing both fails against `choices`. In `--help`, both suffixes render: `(one of: s1, s2) (matches: ^s[0-9]+$)`.

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

- A persistent flag cannot share its `name`, `aliases`, or `short` with a reserved framework global (`help`, `verbose`, `quiet`, `no-color`, `no-cache`, `version`) or with any per-command flag. Compile fails with an error naming both layers.
- Persistent flags cannot declare `group`, `exclusive`, or `requires` (not yet supported — declare these on per-command flags only). Cross-layer group semantics are a scope decision, not a philosophical restriction.
- All other flag attributes (`type`, `default`, `required`, `deprecated`, `hidden`, `aliases`) work identically to per-command flags.

### Internal protocol: `CLIFT_PERSIST_BOUND`

`CLIFT_PERSIST_BOUND` is an internal wrapper-to-parser protocol. The wrapper exports the space-separated list of persistent flag names it early-bound (pre-command occurrences) so the parser can skip default application for those names — a wrapper-bound value is a user value and must outrank a default. Users should not set this manually; it is not part of the public contract and may change between releases.

## Accessing parsed flags from your script

Every parsed flag is exposed via **two** populated surfaces. Pick whichever reads best — they always agree on the same value.

### `${CLIFT_FLAGS[name]}` -- associative array, dash-preserving

```bash
if [[ "${CLIFT_FLAGS[dry-run]:-}" == "true" ]]; then
  log_info "dry run"
fi
target="${CLIFT_FLAGS[target]:-staging}"
```

Keys match the declared flag `name` exactly — including dashes. `CLIFT_FLAGS[dry-run]`, not `CLIFT_FLAGS[DRY_RUN]`. Absent keys mean "not provided and no default" (use `${CLIFT_FLAGS[key]:-fallback}` as normal).

Requires bash 4.2+ (clift's documented floor). The framework materializes the array from a tempfile during the runtime prelude, then unlinks the file eagerly. As a result, **`CLIFT_FLAGS` is main-process only** — subshells (`$(bash -c …)`, `(…)` blocks that fork, etc.) cannot re-source the prelude to rebuild it (the tempfile is gone) and bash assoc arrays don't cross process boundaries. Subshells must read the env-var form below, which inherits natively.

### `${CLIFT_FLAG_<UPPER>}` -- env var, underscore-substituted (back-compat)

```bash
if [[ "${CLIFT_FLAG_DRY_RUN:-}" == "true" ]]; then
  log_info "dry run"
fi
target="${CLIFT_FLAG_TARGET:-staging}"
```

Name is uppercased and dashes become underscores (`dry-run` → `DRY_RUN`). These env vars are inherited by subshells (`$(bash -c …)`) natively.

### List flags

Both surfaces see list flags:

| Access | Value |
|---|---|
| `${CLIFT_FLAGS[tag]}` | comma-joined: `"a,b,c"` |
| `CLIFT_FLAG_TAG_1`, `CLIFT_FLAG_TAG_2`, … | per-element |
| `CLIFT_FLAG_TAG_COUNT` | element count |

Splitting `${CLIFT_FLAGS[tag]}` on `,` is lossy if an element itself contains a comma — use the indexed env vars for that case.

### Persistent flags

Persistent flags (declared in the root `vars.PERSISTENT_FLAGS`) appear in `CLIFT_FLAGS` under their declared name like any other flag. Wrapper pre-binds and post-command occurrences resolve to a single final value (last-write-wins) before the array is materialized.

## Validation

Schemas are validated at scaffold time by `new:cmd` and `new:subcmd`, at `setup:cli`, and at cache rebuild. Errors surface immediately, not at first invocation.
