# clift

A batteries-included, language-agnostic framework for building custom CLIs using [go-task](https://taskfile.dev).

You write your command logic in any language -- shell, Python, Go, whatever -- and clift provides the CLI UX: help system, argument parsing, config management, logging, and more.

## Quick Start

```bash
# Prerequisites: task (go-task), jq, yq
# Optional: gum (for pretty prompts)

# Clone the framework
git clone <repo-url> ~/.clift

# Bootstrap a new CLI
task --taskfile ~/.clift/Taskfile.yaml setup:cli -- ~/.config/mycli

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
- Optional versioning via cfgd (upgrade, pin, distribute)
- `NO_COLOR` standard support

## Requirements

| Dependency | Required | Purpose |
|---|---|---|
| [Task](https://taskfile.dev) v3.0+ | Yes | Task runner that powers the CLI |
| [jq](https://jqlang.github.io/jq/) | Yes | JSON processing for help and config |
| [yq](https://github.com/mikefarah/yq) | Yes | YAML processing for metadata |
| [gum](https://github.com/charmbracelet/gum) | No | Enhanced interactive prompts (falls back to `read`) |

## How It Works

clift is a framework repo that provides shared libraries (`lib/`) for help, logging, routing, argument parsing, config, and more. When you bootstrap a CLI with `setup:cli`, it creates a project directory with:

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
| `FRAMEWORK_DIR` | Path to the clift framework |
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

## Team Setup

When sharing a CLI with your team, include the `.clift.yaml` file in your CLI's directory. It documents what dependencies your CLI needs:

```yaml
name: my-team-cli
version: 1.0.0
description: "Internal deployment tools"

dependencies:
  required:
    - jq
    - kubectl
  optional:
    - gum
    - fzf
```

Teammates can read this file to know what to install before using the CLI.

## Updating

```bash
mycli update    # pulls latest framework from git
```

## Versioning

clift CLIs can be versioned and distributed via [cfgd](https://github.com/tj-smith47/cfgd). Versioning is opt-in — enable it during setup or add it later.

### Enable During Setup

```bash
CFGD_VERSIONING=true task --taskfile ~/.clift/Taskfile.yaml setup:cli -- ~/my-cli
```

This installs cfgd (if missing), configures the CLI as a cfgd module, and adds the `version:*` commands.

### Add to an Existing CLI

From the framework directory:

```bash
task setup:versioning -- ~/my-cli
```

Or from within the CLI itself (if version namespace is manually included):

```bash
mycli version:setup
```

### Version Commands

Once versioning is enabled, these commands are available:

| Command | Description |
|---|---|
| `version` | Show current version and cfgd status |
| `version:setup` | Set up cfgd versioning (installs cfgd if needed) |
| `version:upgrade` | Upgrade to the latest version via cfgd |
| `version:update` | Alias for `version:upgrade` |
| `version:set -- <ver>` | Pin to a specific version (e.g., `v1.2.3`) |

### Standalone vs Config Repo Mode

By default, `version:setup` treats the CLI as a **standalone module** in its own git repo. To add it to an existing cfgd config repo instead, set these environment variables:

| Variable | Description |
|---|---|
| `CFGD_CONFIG_DIR` | Path to your cfgd config repo (e.g., `~/dotfiles`) |
| `CFGD_PROFILES` | Comma-separated profiles to add the module to (e.g., `dev,work`) |

```bash
CFGD_CONFIG_DIR=~/dotfiles CFGD_PROFILES=dev mycli version:setup
```

### Publishing a Version

After versioning is set up, tag releases using cfgd's convention:

```bash
git tag "mycli/v1.0.0"
git push origin --tags
```

Consumers upgrade with `mycli version:upgrade` or pin with `mycli version:set -- v1.0.0`.

## cfgd Integration

[cfgd](https://github.com/...) is a declarative machine configuration tool. When available, clift uses it as a backend for dependency management, updates, and drift detection. **cfgd is never required.** Everything works without it.

### Framework Module

To manage the clift framework with cfgd, copy `cfgd/clift/module.yaml` into your cfgd config's `modules/` directory:

```bash
cp ~/.clift/cfgd/clift/module.yaml ~/dotfiles/modules/clift/module.yaml
```

This module declares `go-task`, `jq`, `yq`, and `gum` as packages and clones the framework repo. Add it to your profile:

```yaml
# profiles/work.yaml
spec:
  modules:
    - clift
```

Then `cfgd apply` installs everything.

### CLI Modules

When you bootstrap a CLI with `setup:cli`, a `module.yaml` is generated alongside it. This module depends on `clift`, declares your CLI's dependencies from `.clift.yaml`, and configures the shell alias. Copy it to your cfgd config to distribute the CLI to other machines or teammates.

### Update Modes

When cfgd manages your framework installation, `mycli update` detects this and directs you to use cfgd instead. How updates work depends on how you pin the module:

| Pin style | module.yaml source | How to update | What you get |
|---|---|---|---|
| **Tag** | `...git@v0.2.0` | `cfgd module upgrade clift --ref v0.3.0` | Explicit version bumps |
| **Latest** | (any) | `cfgd module upgrade clift` | Bumps lockfile to repo HEAD |

Both styles lock to a specific commit SHA in `modules.lock`. Between upgrades, the version never changes — even if new commits are pushed upstream.

### Daemon Behavior

If the cfgd daemon is enabled, it periodically verifies that managed installations match their lockfile pin:

- **Dependency healing** — if `jq` or `gum` gets uninstalled, the daemon reinstalls them on the next reconcile cycle
- **File protection** — if framework files are accidentally modified, the daemon restores them to the pinned state
- **No surprise updates** — the daemon enforces the current pin, it does not pull new versions. Updates are always explicit via `cfgd module upgrade`

What happens on drift depends on your `driftPolicy` (`Auto`, `NotifyOnly`, or `Prompt`) — see cfgd docs.

### Without cfgd

If cfgd is not installed, nothing changes:
- `deps.sh` checks for `jq` and `gum` directly
- `mycli update` uses `git pull` as before
- `.clift.yaml` documents dependencies for humans to install manually

## License

MIT -- see [LICENSE](LICENSE).
