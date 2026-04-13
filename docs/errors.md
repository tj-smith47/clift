# Errors

All clift errors print to stderr with an `error:` prefix and consistent formatting. Did-you-mean suggestions use Levenshtein distance (threshold <= 2).

## Parser errors

| Error | Trigger | Fix |
|---|---|---|
| `error: unknown flag '--froce'` + `did you mean '--force'?` | Flag not in merged table | Check spelling; run `<cli> <cmd> --help` |
| `error: required flag '--target' not provided` | `required: true` flag absent | Pass the flag |
| `error: flag '--target' requires a value` | Value-taking flag at end of argv with no value | Provide a value |
| `error: flag '--count' requires an integer, got 'abc'` | `type: int` got non-numeric | Pass a number |
| `error: short flag '-t' cannot appear in cluster '-vt'` + `'-t' is declared by command flag 'target' (type: string) as non-bool` | Non-bool flag in a cluster | Split the cluster: `-v -t value` |

## Wrapper errors (standard mode)

| Error | Trigger | Fix |
|---|---|---|
| `error: unknown command 'deplo'` + `did you mean 'deploy'?` | First token not a known task | Check spelling |
| `error: flags must come after the command` | Flag first (except `--help`/`--version`) | Move flags after the command |
| `error: subcommand must come before flags` | Subcommand token appears after a flag | Reorder: `mycli deploy prod --verbose` |

## Validator errors (scaffold and compile time)

| Error | Trigger | Fix |
|---|---|---|
| `error: <path>:vars.FLAGS[N]: flag name 'dry_run' must match ^[a-z][a-z0-9-]*$ (no underscores, lowercase)` | Underscore in name | Use `dry-run` |
| `error: flag name 'help' is reserved (framework global)` | Using a framework-global name | Pick a different name |
| `error: flag name 'task' is reserved (env-var namespace collision)` | Collides with `CLIFT_TASK` | Pick a different name |
| `error: flag name 'mode' is reserved (env-var namespace collision)` | Collides with `CLIFT_MODE` | Pick a different name |
| `error: flag 'force' missing 'type'` | No `type` key | Add `type: bool` (or appropriate) |
| `error: duplicate flag name 'force' within layer` | Two flags with same name | Remove one |

## Setup errors

| Error | Trigger |
|---|---|
| `error: CLIFT_MODE must be 'task' or 'standard'` | Invalid mode value |
| `error: CLI_NAME must be lowercase alphanumeric` | Invalid characters in CLI name |

## Runtime errors

| Error | Trigger |
|---|---|
| `error: bash 4.0+ is required` | Running on macOS stock bash 3.2 |
| `error: script not found for task '...'` | Scaffold bug or deleted script |
