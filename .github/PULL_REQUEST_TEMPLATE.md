## Summary

<!-- Brief description of what this PR does -->

## Type of Change

- [ ] Bug fix
- [ ] New feature
- [ ] Enhancement to existing feature
- [ ] Refactoring (no functional change)
- [ ] Documentation
- [ ] CI/CD

## Changes Made

-

## Checklist

### Code Quality
- [ ] All user-facing output goes through the `log_*` helpers (`log_info`, `log_warn`, `log_error`, `log_success`, `log_debug`, `log_suggest`) — no bare `echo` / `printf` for status messages
- [ ] Scripts start with `set -euo pipefail` and quote expansions defensively
- [ ] No hard-coded paths; respect `FRAMEWORK_DIR`, `CLI_DIR`, and the documented env vars
- [ ] Consumer-facing surface unchanged, or breaking change called out explicitly (flag schema, `CLIFT_FLAG_*` / `CLIFT_POS_*` contract, override hooks, completion contract)

### Testing
- [ ] `bats tests/*.bats` passes
- [ ] `shellcheck lib/**/*.sh` passes (and any new scripts touched)
- [ ] `task lint` / `task test` (or the project's `Taskfile.yaml` equivalents) pass
- [ ] New code has bats coverage; coverage stays at or above the existing threshold (`scripts/coverage.sh`)
- [ ] Bats tests use the standard helper that engages the filesystem tripwire (no untracked writes to real `$HOME`)

### Documentation
- [ ] README.md updated (if user-facing change)
- [ ] Relevant doc under `docs/` updated (flags, scripts, modes, cache, completion, etc.)
- [ ] Help text / `--help` output updated (if adding or changing commands or flags)
- [ ] Demo VHS tape(s) re-recorded if the change affects an existing demo

## Testing Done

<!-- How did you test this? Include the consumer-CLI invocation, any sample Taskfile.yaml,
     and the relevant `--verbose` output if behavior is observable through logs. -->

## Related Issues

<!-- Link to related issues: Fixes #123, Relates to #456 -->
