# DIYCLI

A batteries-included, language-agnostic framework for building custom CLIs using [go-task](https://taskfile.dev).

You write your command logic in any language -- shell, Python, Go, whatever -- and DIYCLI provides the CLI UX: help system, argument parsing, config management, logging, and more.

## Quick Start

```bash
# Prerequisites: task (go-task), jq
# Optional: gum (for pretty prompts)

# Clone the framework
git clone <repo-url> ~/.diycli

# Bootstrap a new CLI
task --taskfile ~/.diycli/Taskfile.yaml setup:cli -- ~/.config/mycli

# Source your shell and start using it
source ~/.bashrc
mycli                    # see available commands
mycli new:cmd            # create your first command
```

## Features

- Cobra-style help system with grouped commands
- Themed logging (7 built-in themes + custom)
- Argument parsing (flags, booleans, positionals)
- Interactive prompts (gum with read fallback)
- Config management (get/set/show/edit/theme)
- Command scaffolding with `new:cmd`
- Global flags: `--verbose`, `--quiet`, `--no-color`, `--help`, `--version`
- Shell completions (bash, zsh)
- Framework self-update
- `NO_COLOR` standard support

## Requirements

| Dependency | Required | Purpose |
|---|---|---|
| [Task](https://taskfile.dev) v3.0+ | Yes | Task runner that powers the CLI |
| [jq](https://jqlang.github.io/jq/) | Yes | JSON processing for help and config |
| [gum](https://github.com/charmbracelet/gum) | No | Enhanced interactive prompts (falls back to `read`) |

## How It Works

DIYCLI is a framework repo that provides shared libraries (`lib/`) for help, logging, routing, argument parsing, config, and more. When you bootstrap a CLI with `setup:cli`, it creates a project directory with:

```
~/.config/mycli/
  .env               # CLI_NAME, CLI_VERSION, FRAMEWORK_DIR, LOG_THEME
  Taskfile.yaml       # includes framework libs + your commands
  cmds/
    greet/
      Taskfile.yaml   # task definition (desc, routing, help)
      greet.sh        # your command logic (any language)
```

Your CLI is a shell alias that invokes `task` with your project's Taskfile. The framework's router handles global flags, logging setup, and dispatching to your command scripts. Commands are Taskfile includes -- each command lives in `cmds/<name>/` with its own Taskfile and script.

## Creating Commands

```bash
mycli new:cmd
# Prompts for: command name, short description
# Generates: cmds/<name>/Taskfile.yaml + <name>.sh
```

The generated script comes pre-wired with logging and argument parsing:

```bash
#!/usr/bin/env bash
set -euo pipefail

source "${FRAMEWORK_DIR}/lib/log/log.sh"
source "${FRAMEWORK_DIR}/lib/args/args.sh"

# Parse arguments
source <(parse_args "$@" --flags "")

# Command logic here
log_info "Hello from mycommand"
```

Subcommands work via task namespacing. A command `deploy` can have subcommands `deploy:staging` and `deploy:prod` by adding tasks to its Taskfile.

## Argument Parsing

Source `args.sh` and use `parse_args` in your command scripts:

```bash
source "${FRAMEWORK_DIR}/lib/args/args.sh"
source <(parse_args "$@" --flags "force,dry_run")

# --name=world     -> NAME=world
# --force          -> FORCE=true  (boolean, declared in --flags)
# hello            -> ARG_1=hello (positional)
# ARG_COUNT is always set
```

## Configuration

```bash
mycli config:show              # display all config
mycli config:get -- LOG_THEME  # get a single value
mycli config:set -- LOG_THEME brackets-color
mycli config:theme             # interactive theme picker
mycli config:edit              # open .env in $EDITOR
```

Configuration lives in `.env` at the CLI project root. Key variables:

| Variable | Description |
|---|---|
| `CLI_NAME` | Name of your CLI |
| `CLI_VERSION` | Version string |
| `FRAMEWORK_DIR` | Path to the DIYCLI framework |
| `CLI_DIR` | Path to your CLI project |
| `LOG_THEME` | Active logging theme |

## Global Flags

These flags are handled by the router and available to all commands:

| Flag | Short | Description |
|---|---|---|
| `--help` | `-h` | Show help for the current command |
| `--version` | `-V` | Print CLI version |
| `--verbose` | `-v` | Enable debug log output |
| `--quiet` | `-q` | Suppress info/success messages |
| `--no-color` | | Disable colored output |

The `NO_COLOR` environment variable is also respected per [no-color.org](https://no-color.org).

## Logging

Seven built-in themes control how log messages are formatted:

| Theme | Example output |
|---|---|
| `icons` | `-> message` |
| `icons-color` | `-> message` (colored) |
| `brackets` | `[INFO] message` |
| `brackets-color` | `[INFO] message` (colored) |
| `minimal` | `message` |
| `minimal-color` | `message` (colored) |
| `custom` | User-defined via `LOG_FMT_*` vars |

Log functions available in your scripts after sourcing `log.sh`:

```bash
log_info "informational"
log_warn "warning"
log_error "something broke"
log_success "done"
log_debug "only shown with --verbose"
die "fatal error" 1
```

For the `custom` theme, define format strings in your `.env`:

```bash
LOG_FMT_INFO=":: %s"
LOG_FMT_WARN="!! %s"
LOG_FMT_ERROR="** %s"
LOG_FMT_SUCCESS="++ %s"
LOG_FMT_DEBUG=".. %s"
```

## Shell Completions

```bash
# Bash (add to ~/.bashrc)
eval "$(mycli completion:bash)"

# Zsh (add to ~/.zshrc)
eval "$(mycli completion:zsh)"
```

## Updating

```bash
mycli update    # pulls latest framework from git
```

## License

MIT -- see [LICENSE](LICENSE).
