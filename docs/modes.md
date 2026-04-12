# Modes

clift CLIs can be built in one of two argument-format modes, fixed at setup time:

## Task mode (default)

Invocation: `mycli cmd:subcmd -- --flag value`

- Shell alias points at `task --taskfile <path>`
- Arguments pass through Task's `CLI_ARGS`
- Matches `go-task` semantics exactly
- Works in any shell with no PATH management

## Standard mode

Invocation: `mycli cmd subcmd --flag value`

- Wrapper script in `${CLI_DIR}/bin/${CLI_NAME}`, added to PATH
- Cobra-like UX: space-separated subcommands, flags with or without values, short aliases
- Command path resolved via longest-prefix match against known tasks
- Argv passes via indexed env vars (`CLIFT_ARG_*`) -- preserves quoting and shell metacharacters

## Picking a mode

Default to **task** unless you want Cobra UX. Both modes support the same features -- flag schemas, help, completion, error rendering. Standard mode just changes the invocation surface.

## Switching

Re-run setup with a different `CLIFT_MODE`:

```bash
# Start in task mode
task setup:cli -- /path/to/mycli

# Later, switch to standard mode
CLIFT_MODE=standard task setup:cli -- /path/to/mycli
```

The old mode's entry point is scrubbed automatically (alias removed or PATH line + wrapper deleted). Your commands and scripts are unchanged.
