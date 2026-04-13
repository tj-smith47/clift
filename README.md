<h1 align="center">clift</h1>
<p align="center"><em>Command Line Interface Framework in Task</em></p>
<p align="center">A batteries-included, language-agnostic framework for building custom CLIs using <a href="https://taskfile.dev">go-task</a>.<br>You write your command logic in any language — clift provides the UX.</p>

---

## Table of Contents

- [Quick Start](#quick-start)
- [Features](#features)
- [Requirements](#requirements)
- [How It Works](#how-it-works)
- [Modes](#modes)
- [Creating Commands](#creating-commands)
- [Argument Parsing](#argument-parsing)
- [Global Flags](#global-flags)
- [Logging](#logging)
- [Shell Completions](#shell-completions)
- [Configuration](#configuration)
- [Updating](#updating)
- [Versioning & cfgd](#versioning--cfgd)
- [License](#license)

## Quick Start

```bash
# Prerequisites: bash 4+, task (go-task), jq, yq
# Optional: gum (for pretty prompts)

# Clone the framework
git clone <repo-url> ~/.clift

# Bootstrap a new CLI (standard mode — Cobra-like UX)
CLIFT_MODE=standard task --taskfile ~/.clift/Taskfile.yaml setup:cli -- ~/.config/mycli

# Source your shell and start using it
source ~/.bashrc
mycli                         # see available commands
mycli new cmd                 # scaffold your first command
mycli greet --name world      # run it with flags
mycli greet --help            # per-command help
```

## Features

- Cobra-style help system with grouped commands
- Typed flag parsing (bool, string, int, list) with defaults, required flags, and short aliases
- Did-you-mean error suggestions (Levenshtein)
- Themed logging (7 built-in themes + custom color schemes)
- Interactive prompts (gum with read fallback)
- Config management (get/set/show/edit/theme)
- Command scaffolding with `new cmd`
- Global flags: `--verbose`, `--quiet`, `--no-color`, `--help`, `--version`
- Shell completions with flag support (bash, zsh)
- Framework self-update
- Optional versioning and distribution via [cfgd](https://github.com/tj-smith47/cfgd)
- `NO_COLOR` standard support

## Requirements

| Dependency | Required | Purpose |
|---|---|---|
| bash 4.0+ | Yes | Associative arrays, `${var^^}`, used throughout |
| [Task](https://taskfile.dev) v3.0+ | Yes | Task runner that powers the CLI |
| [jq](https://jqlang.github.io/jq/) | Yes | JSON processing for help and config |
| [yq](https://github.com/mikefarah/yq) | Yes | YAML processing for metadata |
| [gum](https://github.com/charmbracelet/gum) | No | Enhanced interactive prompts (falls back to `read`) |

> **macOS note:** macOS ships bash 3.2. Install bash 4+ via `brew install bash`.

## How It Works

clift is a framework repo that provides shared libraries (`lib/`) for help, logging, routing, argument parsing, config, and more. When you bootstrap a CLI with `setup:cli`, it creates a project directory with:

```
~/.config/mycli/
  .env                       # CLI_NAME, CLI_VERSION, FRAMEWORK_DIR, LOG_THEME
  Taskfile.yaml              # includes framework libs + your commands
  cmds/
    greet/
      Taskfile.yaml          # task definition (desc, routing, help)
      greet.{sh,py,go,rs,…}  # your command logic, any language
```

In standard mode, your CLI is a wrapper script on PATH that provides Cobra-style `mycli cmd subcmd --flag` UX. In task mode, it's a shell alias that invokes `task` directly. The framework's router handles global flags, logging setup, and dispatching to your command scripts. Commands are Taskfile includes -- each command lives in `cmds/<name>/` with its own Taskfile and script.

See [docs/architecture.md](docs/architecture.md) for the full call stack.

## Modes

clift CLIs support two argument-format styles, chosen at setup time:

- **Standard mode** -- `mycli cmd subcmd --flag value` (Cobra-like, recommended)
- **Task mode** -- `mycli cmd:subcmd -- --flag value` (raw go-task semantics)

Standard mode gives you space-separated subcommands, `--flag` parsing, did-you-mean errors, and shell completions with flag support. See [docs/modes.md](docs/modes.md).

## Creating Commands

```bash
mycli new cmd
# Prompts for: command name, short description
# Generates: cmds/<name>/Taskfile.yaml + <name>.sh
```

The generated script comes pre-wired with logging and the flag env var contract:

```bash
#!/usr/bin/env bash
set -euo pipefail

source "${FRAMEWORK_DIR}/lib/log/log.sh"

# Flag values arrive as CLIFT_FLAG_<NAME> (uppercased, dashes→underscores).
# Positional args: CLIFT_POS_1, CLIFT_POS_2, ... CLIFT_POS_COUNT.
log_info "Hello from mycommand"
```

Subcommands work via task namespacing. A command `deploy` can have subcommands `deploy:staging` and `deploy:prod` by adding tasks to its Taskfile.

## Argument Parsing

Declare flags in your command's `Taskfile.yaml` under `vars.FLAGS`. The router parses them before your script runs and exports them as env vars:

```yaml
# cmds/deploy/Taskfile.yaml
vars:
  FLAGS:
    - {name: target, short: t, type: string, default: staging, desc: "Target env"}
    - {name: force, short: f, type: bool, desc: "Skip confirmation"}
```

```bash
# cmds/deploy/deploy.sh
target="${CLIFT_FLAG_TARGET}"       # "staging" (default applied)
if [[ "${CLIFT_FLAG_FORCE:-}" == "true" ]]; then ...
file="${CLIFT_POS_1:?missing file}" # positional args
```

See [docs/flags.md](docs/flags.md) for the full schema and [docs/scripts.md](docs/scripts.md) for the env var contract.

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
| `icons` | `→ message` |
| `icons-color` | `→ message` (colored) |
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
log_suggest "hint text (dimmed, suppressed by --quiet)"
die "fatal error" 1
```

### Custom format strings

For the `custom` theme, define format strings in your `.env`:

```bash
LOG_FMT_INFO=":: %s"
LOG_FMT_WARN="!! %s"
LOG_FMT_ERROR="** %s"
LOG_FMT_SUCCESS="++ %s"
LOG_FMT_DEBUG=".. %s"
```

### Custom color schemes

Any theme's colors can be overridden via `LOG_CLR_*` env vars in `.env`. Values are ANSI escape sequences.

| Variable | Controls | Default |
|---|---|---|
| `LOG_CLR_INFO` | Info messages | Blue (`\033[0;34m`) |
| `LOG_CLR_WARN` | Warnings | Yellow (`\033[0;33m`) |
| `LOG_CLR_ERROR` | Errors | Red (`\033[0;31m`) |
| `LOG_CLR_SUCCESS` | Success messages | Green (`\033[0;32m`) |
| `LOG_CLR_DEBUG` | Debug messages | Cyan (`\033[0;36m`) |
| `LOG_CLR_DIM` | Suggestions | Dim (`\033[2m`) |

**Example: Dracula color scheme**

```bash
# .env — Dracula palette over the default icons-color theme
LOG_CLR_INFO=\033[38;2;139;233;253m
LOG_CLR_WARN=\033[38;2;255;184;108m
LOG_CLR_ERROR=\033[38;2;255;85;85m
LOG_CLR_SUCCESS=\033[38;2;80;250;123m
LOG_CLR_DEBUG=\033[38;2;189;147;249m
LOG_CLR_DIM=\033[38;2;98;114;164m
```

**Example: Catppuccin Mocha**

```bash
LOG_CLR_INFO=\033[38;2;137;180;250m
LOG_CLR_WARN=\033[38;2;249;226;175m
LOG_CLR_ERROR=\033[38;2;243;139;168m
LOG_CLR_SUCCESS=\033[38;2;166;227;161m
LOG_CLR_DEBUG=\033[38;2;203;166;247m
LOG_CLR_DIM=\033[38;2;108;112;134m
```

## Shell Completions

```bash
# Bash (add to ~/.bashrc)
eval "$(mycli completion:bash)"

# Zsh (add to ~/.zshrc)
eval "$(mycli completion:zsh)"
```

## Configuration

```bash
mycli config show              # display all config
mycli config get -- LOG_THEME  # get a single value
mycli config set -- LOG_THEME brackets-color
mycli config theme             # interactive theme picker
mycli config edit              # open .env in $EDITOR
```

Configuration lives in `.env` at the CLI project root. Key variables:

| Variable | Description |
|---|---|
| `CLI_NAME` | Name of your CLI |
| `CLI_VERSION` | Version string |
| `FRAMEWORK_DIR` | Path to the clift framework |
| `CLI_DIR` | Path to your CLI project |
| `LOG_THEME` | Active logging theme |

## Updating

```bash
mycli update    # pulls latest framework from git
```

## Versioning & cfgd

clift CLIs can be versioned and distributed via [cfgd](https://github.com/tj-smith47/cfgd), a declarative machine configuration tool. **cfgd is never required.** Everything works without it.

### Setup

```bash
# During initial setup
CFGD_VERSIONING=true task --taskfile ~/.clift/Taskfile.yaml setup:cli -- ~/my-cli

# Or add to an existing CLI
task setup:versioning -- ~/my-cli
```

### Version Commands

| Command | Description |
|---|---|
| `version` | Show current version and cfgd status |
| `version setup` | Set up cfgd versioning (installs cfgd if needed) |
| `version upgrade` | Upgrade to the latest version via cfgd |
| `version set -- <ver>` | Pin to a specific version (e.g., `v1.2.3`) |

### Publishing

```bash
git tag "mycli/v1.0.0"
git push origin --tags
```

Consumers upgrade with `mycli version upgrade` or pin with `mycli version set -- v1.0.0`.

### cfgd integration details

By default, `version setup` treats the CLI as a **standalone module** in its own git repo. To add it to an existing cfgd config repo:

```bash
CFGD_CONFIG_DIR=~/dotfiles CFGD_PROFILES=dev mycli version setup
```

To manage the framework itself with cfgd, copy `cfgd/clift/module.yaml` into your config repo's `modules/` directory. This declares `go-task`, `jq`, `yq`, and `gum` as packages and clones the framework repo.

When cfgd manages your installation, `mycli update` detects this and directs you to use cfgd instead. The cfgd daemon handles dependency healing, file protection, and pinned updates. See the [cfgd docs](https://github.com/tj-smith47/cfgd) for details.

### Without cfgd

If cfgd is not installed, nothing changes:
- `deps.sh` checks for `jq` and `yq` (required) and `gum` (optional)
- `mycli update` uses `git pull`
- `.clift.yaml` documents dependencies for humans to install manually

## License

MIT -- see [LICENSE](LICENSE).
