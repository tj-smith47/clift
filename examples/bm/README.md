# bm — bookmark manager (clift example)

A small, end-to-end clift example that fits on one screen of `tree`. Pure
bash, single `jq` dependency, NDJSON storage, no network.

## What it shows

| Feature | Demonstrated by |
|---|---|
| string + list flag, pattern validation, positional | `bm add <url> --name --tag` |
| choices flag, int flag, command alias | `bm list --format json --limit 5` |
| dynamic completion on a positional | `bm open <TAB>` |
| bool flag | `bm rm <name> --force` |
| mutually-exclusive flag group | `bm tag <name> --add foo --remove bar` |
| persistent flag with choices | `bm --profile work add ...` |
| dynamic completion on a flag value | `bm add --tag <TAB>` |

## Try it

```bash
cd examples/bm
clift setup:cli .                 # writes bin/bm + RC entry
./bin/bm add https://taskfile.dev --name task --tag rust --tag build
./bin/bm list
./bin/bm list --format json
./bin/bm open task
./bin/bm tag task --add cli
./bin/bm rm task --force
```

Per-profile stores live under `${BM_HOME:-$XDG_DATA_HOME/bm}/<profile>/store`.
