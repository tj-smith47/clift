# Architecture

```
User types: mycli deploy prod --force
            |
            v
+---------------------+          +--------------------+
| wrapper (standard)  |          | alias (task)       |
| bin/mycli script    |          | shell alias line   |
+---------+-----------+          +---------+----------+
          |                                |
          | CLIFT_ARG_* env vars           | task -- args (CLI_ARGS)
          v                                v
+----------------------------------------------+
| task --taskfile <root> deploy:prod           |
|   -> runs cmds/deploy's task "prod"          |
+-----------------------+----------------------+
                        |
                        v
+----------------------------------------------+
| lib/router/router.sh                         |
|   1. dep check (bash 4+, jq, yq)            |
|   2. reconstruct argv (CLIFT_ARG_* or args)  |
|   3. early passthrough (no root Taskfile?)    |
|   4. ensure cache fresh                      |
|   5. load index.json flags + merge globals   |
|   6. passthrough? exec script with raw argv  |
|   7. clift_parse_args -> CLIFT_FLAG_*        |
|   8. intercept --help, --version             |
|   9. emit VERBOSE / QUIET / NO_COLOR compat  |
|  10. resolve script, exec                    |
+-----------------------+----------------------+
                        |
                        v
             Your script reads env vars
```

## Key pieces

- **`lib/wrapper/wrapper.sh.tmpl`** -- standard-mode entry point (generated per CLI)
- **`lib/setup/`** -- installs alias or wrapper + PATH, scrubs opposite on switch
- **`lib/flags/compile.sh`** -- builds `.clift/` cache from Taskfiles
- **`lib/flags/validate.sh`** -- schema validator (runs at scaffold and compile time)
- **`lib/flags/parser.sh`** -- argparser, emits `CLIFT_FLAG_*` / `CLIFT_POS_*`
- **`lib/flags/errors.sh`** -- error formatting, did-you-mean (Levenshtein)
- **`lib/router/router.sh`** -- single runtime entry for both modes
- **`lib/cache.sh`** -- portable mtime + staleness check (reads `.clift/sources`)
- **`lib/check/deps.sh`** -- dependency validation (bash 4.0+, jq, yq)
- **`lib/scaffold/scaffold.sh`** -- command scaffolding (`new:cmd`)
- **`lib/help/`** -- list and detail renderers, consume `.clift/index.json`
- **`lib/completion/`** -- shell completion generator (bash + zsh, with flag completion)

## Invariants

- Flag parsing happens exactly once per invocation, in the router.
- The wrapper never parses flags -- it only resolves the command path.
- The precompiled cache is the only runtime source of truth for task lists and flag tables.
- Standard and task modes share the same router, parser, and cache -- mode affects only entry-point generation and argv reconstruction.
- No `yq` at runtime. `yq` runs only during `compile.sh` (cold path).
