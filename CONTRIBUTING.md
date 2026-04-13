# Contributing to clift

## Development Setup

```bash
git clone <repo-url> && cd clift
```

Requirements:
- bash 4.0+ (macOS ships 3.2 -- `brew install bash`)
- [Task](https://taskfile.dev) v3.0+
- [jq](https://jqlang.github.io/jq/)
- [yq](https://github.com/mikefarah/yq)
- [BATS](https://github.com/bats-core/bats-core) 1.5.0+ (for running tests)
- [ShellCheck](https://www.shellcheck.net/) (for linting)

## Running Tests

```bash
bats tests/
```

## Linting

```bash
shellcheck lib/**/*.sh
```

## Project Structure

- `lib/` — Framework libraries (one directory per component)
- `templates/` — Templates rendered during CLI bootstrap and command creation
- `tests/` — BATS test suites

Each `lib/` component has a `Taskfile.yaml` (for Task integration) and one or more `.sh` scripts (for logic). No inline bash in Taskfiles — all logic lives in scripts.

## Conventions

- `set -euo pipefail` at the top of every script
- `cmd:` (singular) when a task has one command
- Colon-separated task names (`config:show`), no dashes
- One `Taskfile.yaml` per command directory (for LSP detection)
- Shell scripts handle their own argument parsing and error output

## The `.clift/` cache

Generated CLIs use a precompiled cache at `.clift/` for runtime flag/task lookup. During framework development, if you change parser or compile logic, test CLIs need their cache rebuilt:

```bash
bash lib/flags/compile.sh /path/to/test-cli
```

See [docs/cache.md](docs/cache.md) for details.

## Submitting Changes

1. Create a branch from `master`
2. Make your changes
3. Ensure `bats tests/` passes
4. Ensure `shellcheck lib/**/*.sh` is clean
5. Open a PR with a clear description of what and why

## Planned Features

- **Version tagging workflow** — assisted release tagging for cfgd-versioned CLIs
