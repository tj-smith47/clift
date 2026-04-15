# Overrides

clift exposes framework behaviour as **override slots**. A CLI author can
replace or wrap any slot by dropping a shell file in a known location; the
runtime sources it and calls the override in place of (or before/after) the
default implementation.

## Two tiers

Overrides resolve with first-hit-wins precedence:

1. **Per-command** — `$CLI_DIR/cmds/<cmd-seg>/overrides/<slot>.sh`. Applies
   only when the invoked task's first segment matches `<cmd-seg>`
   (e.g. `deploy:prod` matches `cmds/deploy/overrides/...`).
2. **CLI-global** — `$CLI_DIR/.clift/overrides/<slot>.sh`. Applies to every
   command in the CLI.

When both files exist for the same slot on the same invocation, the
per-command file is sourced and the CLI-global file is not. No merging.

**Tier depth is one segment.** Only the first segment of a colon-separated
task is used to resolve the per-command tier — `deploy:prod` resolves to
`cmds/deploy/overrides/<slot>.sh`; nested `cmds/deploy/prod/overrides/...`
is NOT consulted. This rule is consistent across every slot.

## Naming convention

Override functions follow one of two patterns:

- **Framework-slot overrides** — `clift_override_<area>_<action>`. Slots are
  reserved by the framework; see the list below.
- **User-keyed dynamic completers** — `clift_complete_<task>_<flag>`. Used by
  the completion system to supply runtime completion candidates for a
  specific flag on a specific command. Keyed by user input, not a fixed slot.
  Documented in the completion reference.

## Callback signature

Every framework-slot override receives the default implementation as its
first argument:

```bash
clift_override_<area>_<action>() {
  local default_fn="$1"
  shift
  # Option A — full override: just produce output, ignore default_fn.
  echo "custom output"

  # Option B — wrap: run the default, decorate around it.
  echo "before"
  "$default_fn" "$@"
  echo "after"

  # Option C — conditional delegation: defer in some cases.
  if [[ "$1" == "fast" ]]; then
    echo "fast path"
  else
    "$default_fn" "$@"
  fi
}
```

Passing the default function explicitly (instead of a fixed symbol name)
keeps user code decoupled from the framework's internal function names.

## Slots

| Slot | Default rendered by | Callback signature | Notes |
|------|---------------------|--------------------|-------|
| `help_list` | `lib/help/list.sh` | `clift_override_help_list <default_fn> <CLI_DIR>` | Top-level `mycli --help` listing. Only the CLI-global tier applies — there is no "current command" at the top level. |
| `help_detail` | `lib/help/detail.sh` | `clift_override_help_detail <default_fn> <task_name> <CLI_DIR>` | Per-command `mycli <cmd> --help` detail view. Per-command tier (`cmds/<cmd>/overrides/help_detail.sh`) takes precedence over CLI-global. |
| `version_print` | `lib/wrapper/wrapper.sh.tmpl`, `lib/router/router.sh`, `lib/version/version.sh` | `clift_override_version_print <default_fn> <CLI_NAME> <CLI_VERSION> <CLI_DIR>` | Controls the line printed by `mycli --version`, `mycli -V`, and the framework's `mycli version` subcommand. The framework default is `clift_default_version_print`, which prints `"<CLI_NAME> version <CLI_VERSION>"`. Override only replaces that one line — the `version` subcommand's cfgd-status block still follows (see [cfgd-status interleaving](#cfgd-status-interleaving) below). |
| `log` | `lib/log/log.sh` | **shadow-based** — see [Logging slot](#logging-slot-shadow-based-exception) below | Sourced by the prelude AFTER `lib/log/log.sh`. The user redefines any of `log_info`, `log_error`, `log_warn`, `log_success`, `log_debug` directly. **Does not use the `clift_override_<slot>` callback signature.** Per-command tier (`cmds/<cmd>/overrides/log.sh`) takes precedence. |

Additional slots (`command_pre`/`command_post`, …) land with Tasks 3.5 – 3.6.

#### cfgd-status interleaving

The `mycli version` subcommand prints the override output FIRST, then appends
the cfgd-status block when `CFGD_VERSIONING=true` is set in the CLI's
`.env`. An override that fully REPLACES the version line still gets the cfgd
status appended — the slot only governs the version line itself, not the
trailing status block. To suppress or restyle the cfgd block, unset
`CFGD_VERSIONING` or wait for a future `version_status` slot.

### Example: wrap `help_list` with a banner

`.clift/overrides/help_list.sh`:

```bash
clift_override_help_list() {
  local default_fn="$1"; shift
  echo "=== ACME CLI ==="
  "$default_fn" "$@"
  echo "=== docs: https://acme.example/cli ==="
}
```

### Example: replace `help_detail` for one command only

`cmds/deploy/overrides/help_detail.sh`:

```bash
clift_override_help_detail() {
  local default_fn="$1" task_name="$2" cli_dir="$3"
  cat <<'HELP'
deploy — ship the current branch to an environment

Usage:
  mycli deploy <env> [--force]

See also:
  mycli rollback --help
HELP
}
```

## Logging slot (shadow-based exception)

The `log` slot is the one slot that does NOT use the
`clift_override_<slot>(default_fn, …)` callback pattern. Instead, it relies
on bash's "last-defined-wins" function semantics: the user's
`.clift/overrides/log.sh` is sourced AFTER `lib/log/log.sh`, and any
function the user redefines transparently shadows the framework version.

### Why a shadow exception?

Logging is on the hot path of every user script — `log_info`, `log_debug`,
and friends are called hundreds-to-thousands of times per command in larger
scripts. A callback indirection per call (`clift_call_override log_info …`)
would add a measurable overhead at scale. Shadow-redefinition is zero cost
per call: bash resolves the user's function the same way it resolves any
other function.

### Recipe — full replacement

`.clift/overrides/log.sh`:

```bash
log_info() { printf '[INFO ] %s\n' "$*"; }
log_warn() { printf '[WARN ] %s\n' "$*" >&2; }
```

That's the entire override. No `clift_override_log_info` wrapper, no
`default_fn` argument — just redefine the helpers you want to change.

**Definitions only.** Put only function definitions in `log.sh`; executable
code at source-time sees a partial environment. In particular, `CLIFT_FLAGS`
is built by the prelude AFTER this override is sourced — a top-level line
like `if [[ "${CLIFT_FLAGS[verbose]}" == true ]]; then …` in `log.sh`
observes an empty map and will not do what you expect. Reference such state
from inside the redefined helper, where it is evaluated per call.

### Recipe — wrap and delegate to the framework default

To call the framework default from within the override, save the original
under a new name BEFORE redefining:

```bash
# Snapshot the framework's log_info into _orig_log_info, then redefine.
eval "_orig_log_info() $(declare -f log_info | tail -n +2)"
log_info() {
  printf 'BEFORE\n'
  _orig_log_info "$@"
  printf 'AFTER\n'
}
```

The `eval`+`tail -n +2` trick copies the function body; calling
`_orig_log_info` from the override runs the framework's original logic.

**Order matters.** The `declare -f log_info` line MUST run BEFORE you
redefine `log_info`. If you reverse the order — redefine `log_info` first,
then run `declare -f log_info` — `_orig_log_info` captures your override
instead of the framework default, and calling it from the override produces
infinite recursion.

### Subshell inheritance — the export caveat

The shadow contract is "redefine and you win in this shell." Subshell
propagation is a free-but-implementation-dependent bonus on top — rely on
explicit `export -f` when you need it to cross a process boundary.

The bonus works because the framework runs `export -f log_info log_warn
log_error log_success log_debug log_suggest die _clift_log_format` in
`lib/log/log.sh`. Once a function has been exported, bash propagates the
LATEST definition to subshells via `BASH_FUNC_<name>%%` env vars, so in
practice an unexported user redefinition also reaches subshells
(`$(bash -c 'log_info x')`) — bash re-stamps the exported value on every
redefinition.

If you DO disable the framework's exports (or define an entirely new helper
your scripts will call from subshells), `export -f` it yourself to be safe:

```bash
log_info() { printf '[INFO ] %s\n' "$*"; }
export -f log_info
```

### Per-command tier

`cmds/<cmd>/overrides/log.sh` overrides apply only when the invoked task's
first segment matches `<cmd>`. Same first-hit-wins precedence as the
callback-style slots — when both files exist, the per-command file is
sourced and the CLI-global file is not.

### Composition with other slots

Because the log slot is shadow-based, log-helper redefinitions are visible
everywhere in the same process. Callback-slot bodies (`help_list`,
`help_detail`, `version_print`, future `command_pre` / `command_post`, …)
that call `log_info` / `log_error` / `log_debug` pick up log-shadow
overrides automatically — no extra plumbing required.

## How it works

The runtime prelude (`lib/runtime/prelude.sh`) sources
`lib/runtime/overrides.sh`, which exposes **one public function**:

- `clift_call_override <slot> <default_fn> [--task <name>] [args...]` —
  loads the override, then calls `clift_override_<slot>` if defined, else
  calls `default_fn` directly. Framework call sites use this to make every
  slot overridable with one line.

  Positional contract: when `--task <name>` is supplied, it MUST be the
  first pair of args after `<default_fn>`. Everything else is forwarded
  verbatim to the override (or the default).

The internal resolver (`_clift_load_override`) is not part of the public
surface — prefixed with `_` by convention. Call sites should always go
through `clift_call_override`.
