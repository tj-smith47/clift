# Errors

All clift errors print to stderr with consistent formatting. Did-you-mean suggestions use Levenshtein distance (threshold <= 2).

## Parser errors

| Error | Trigger | Fix |
|---|---|---|
| `unknown flag '--froce'` + `did you mean '--force'?` | Flag not in merged table | Check spelling; run `<cli> <cmd> --help` |
| `required flag '--target' not provided` | `required: true` flag absent | Pass the flag |
| `flag '--target' requires a value` | Value-taking flag at end of argv with no value | Provide a value |
| `flag '--count' requires an integer, got 'abc'` | `type: int` got non-numeric | Pass a number |
| `short flag '-t' cannot appear in cluster '-vt'` | Non-bool flag in a cluster | Split the cluster: `-v -t value` |

## Wrapper errors (standard mode)

| Error | Trigger | Fix |
|---|---|---|
| `unknown command 'deplo'` + `did you mean 'deploy'?` | First token not a known task | Check spelling |
| `flags must come after the command` | Flag first (except `--help`/`--version`) | Move flags after the command |
| `subcommand must come before flags` | Subcommand token appears after a flag | Reorder: `mycli deploy prod --verbose` |

## Validator errors (scaffold and compile time)

| Error | Trigger | Fix |
|---|---|---|
| `flag name 'dry_run' must match [a-z][a-z0-9-]*` | Underscore in name | Use `dry-run` |
| `flag name 'help' is reserved` | Using a framework-global name | Pick a different name |
| `flag 'force' missing 'type'` | No `type` key | Add `type: bool` (or appropriate) |
| `duplicate flag name 'force' within layer` | Two flags with same name | Remove one |
| `flag name 'task' is reserved` | Env-var namespace collision | Pick a different name |

## Setup errors

| Error | Trigger |
|---|---|
| `CLIFT_MODE must be 'task' or 'standard'` | Invalid mode value |

## Runtime errors

| Error | Trigger |
|---|---|
| `script not found for task '...'` | Scaffold bug or deleted script |
