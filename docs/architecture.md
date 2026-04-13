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
|   1. mode detection                          |
|   2. reconstruct argv                        |
|   3. load .clift/flags.json for this task    |
|   4. passthrough? exec with argv              |
|   5. clift_parse_args -> CLIFT_FLAG_*        |
|   6. intercept --help, --version             |
|   7. passthrough dispatch                    |
|   8. exec cmds/deploy/deploy.prod.sh         |
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
- **`lib/router/router.sh`** -- single runtime entry for both modes
- **`lib/help/`** -- list and detail renderers, consume `.clift/flags.json`
- **`lib/completion/`** -- shell completion generator, consumes `.clift/` too

## Invariants

- Flag parsing happens exactly once per invocation, in the router.
- The wrapper never parses flags.
- The precompiled cache is the only runtime source of truth for task lists and flag tables.
- Standard and task modes share the same router, parser, and cache -- mode affects only entry-point generation and argv reconstruction.
