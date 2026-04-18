# go-task features in clift commands

clift commands are go-task tasks under the hood. Any [task field](https://taskfile.dev/reference/schema/#task) you declare on a task passes through untouched — clift only wraps the `cmd:` dispatch and never rewrites the surrounding fields. A short tour of the most useful ones below; see [taskfile.dev](https://taskfile.dev) for the canonical reference.

## deps

Tasks listed in `deps:` run before the current task (in parallel with each other). Use for setup work that should complete before your command body.

```yaml
tasks:
  default:
    deps: [build:assets]
    cmd: bash deploy.sh
```

## preconditions

Shell expressions that must succeed before the task runs; fail the whole task with a custom message otherwise. Unlike `deps`, preconditions don't invoke another task — they just gate execution.

```yaml
preconditions:
  - sh: 'test -f config.yaml'
    msg: "config.yaml missing — run `mycli init` first"
```

## requires

Declares env vars that must be set and non-empty before the task runs. Cheaper than a precondition for the common "this task needs $PROFILE" case.

```yaml
requires:
  vars: [PROFILE]
```

## sources / generates / method

Fingerprint-based up-to-date checks. `task` hashes `sources:` and compares to the last-successful run; if unchanged and `generates:` still exist, the task is skipped. `method:` is `checksum` (default), `timestamp`, or `none`.

```yaml
sources: ["src/**/*.go"]
generates: ["bin/app"]
method: checksum
```

## status

Custom up-to-date check — a shell expression that returns 0 to mean "already done, skip me". Use when sources/generates don't fit (e.g. "container is already running").

```yaml
status:
  - "docker ps --filter name=api --filter status=running -q | grep -q ."
```

## dotenv

Per-task env-file loading. The root Taskfile already loads the CLI's `.env`; use task-level `dotenv:` for secrets or overrides scoped to one command.

```yaml
dotenv: [".env.staging"]
```

## set

Shell options passed to the task's shell invocation. Equivalent to `set -o <opt>` at the top of the cmd. Common choices: `pipefail`, `errexit`, `nounset`.

clift's router already runs user scripts under `set -euo pipefail`; `set:` on a task affects go-task's shell (e.g. for inline `cmd:` blocks), not your routed `.sh` script.

```yaml
set: [pipefail, errexit]
```

## prompt / interactive

`prompt:` asks the user to confirm before running (good for destructive commands). `interactive: true` tells go-task the task needs a TTY (don't capture output, don't run in parallel groups that buffer).

`prompt:` only fires when attached to an interactive TTY; non-interactive runs (CI) auto-skip the confirmation. Pass `--yes` to go-task (or confirm your CI has no TTY) for predictable behavior.

```yaml
prompt: "This will drop the staging DB. Continue?"
interactive: true
```

## silent

Suppresses go-task's own `task: [name] <cmd>` echo line. clift sets this at the root Taskfile for every CLI already; override per-task if you want verbose echoing for one command during development.

```yaml
silent: true
```

## summary

Long-form description shown by `task --summary <name>`. clift's own `mycli <cmd> --help` already renders this, so scaffolded commands use it for the usage text.

```yaml
summary: |
  Deploy an application to the given environment.

  Examples:
    mycli deploy prod
    mycli deploy --profile=staging prod
```

## `--task:*` runner flag passthrough

Some go-task runner flags (the ones you'd normally pass to `task` itself, not declare on a task) are useful from the user's CLI surface — the obvious cases being `--watch`, `--dry`, `--list-all`. clift exposes these via a `--task:` prefix:

```bash
mycli --task:watch deploy prod        # re-run on file changes
mycli --task:dry deploy prod          # print plan, don't execute
mycli --task:list-all                 # list every available task
mycli --task:interval 500ms watch greet
```

The wrapper consumes these tokens before dispatch, strips the `--task:` prefix, and forwards them to the underlying `task` invocation. Flags that don't accept a value (`--task:watch`) are recognised standalone; flags that do accept a value (`--task:interval`) take the next token, or an inline `--task:interval=500ms` form.

### Whitelist

Only these go-task flags are exposed:

| Flag | Type | Forwards as |
|---|---|---|
| `--task:watch` | bool | `--watch` |
| `--task:dry` | bool | `--dry` |
| `--task:parallel` | bool | `--parallel` |
| `--task:status` | bool | `--status` |
| `--task:summary` | bool | `--summary` |
| `--task:list` | bool | `--list` |
| `--task:list-all` | bool | `--list-all` |
| `--task:force` | bool | `--force` |
| `--task:silent` | bool | `--silent` |
| `--task:interval <dur>` | value | `--interval <dur>` |
| `--task:concurrency <n>` | value | `--concurrency <n>` |

Unknown `--task:foo` is a hard error with the whitelist surfaced — typos won't silently pass through.

### `mycli watch <cmd>`

Because `--task:watch` is the most-used runner-flag, clift exposes a shorthand: `mycli watch <cmd> [args...]` is rewritten to `mycli --task:watch <cmd> [args...]` before dispatch.

```bash
mycli watch build              # equivalent to: mycli --task:watch build
mycli watch deploy --force     # equivalent to: mycli --task:watch deploy --force
mycli watch                    # error: watch requires a command
```

The reservation only matches a literal `watch` as the first argv token — a nested namespace like `watch:foo` (single token containing a colon) is unaffected and dispatches normally.

A user-defined command literally named `watch` at the top level (or an alias resolving to the bare token `watch`) would collide silently — the wrapper's rewrite fires before the cache is even loaded. The framework rejects this at compile time (`new:cmd` / `setup:cli` / cache rebuild) with a hard error so you find out at scaffold time, not at the next `mycli watch <cmd>` invocation. Rename to `watcher`, `monitor`, etc. to avoid the conflict. The same rule applies to the hidden `_complete` token, though the framework's existing `^_` task-name filter already prevents it from being declared.

### Position rules

- `--task:*` flags may appear anywhere in argv; the wrapper scans the whole argv before dispatch.
- Tokens after a bare `--` terminator are treated as literal positionals — `mycli build -- --task:watch foo.txt` passes `--task:watch foo.txt` as raw arguments to your script.
- The whitelist is enforced before any value token is consumed: `mycli --task:typo 500ms greet` errors on `--task:typo` without eating `500ms`.

---

For fields not covered here, see the [go-task schema reference](https://taskfile.dev/reference/schema/). Everything documented there is supported — clift does not strip or rewrite task fields at compile time.
