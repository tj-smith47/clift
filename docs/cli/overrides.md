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

Populated as Phase 3 tasks land.

<!-- Filled in by Tasks 3.2–3.6:
- `help_list`   — root/help listing (Task 3.2)
- `help_detail` — per-command help (Task 3.2)
- `version_print` — `--version` output (Task 3.3)
- `command_pre`, `command_post` — before/after user script (Task 3.4)
- `log_<level>` — per-level log formatting (Task 3.5)
-->

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
