# Security Policy

## Supported Versions

| Version | Supported          |
|---------|--------------------|
| 0.x.x   | :white_check_mark: |

## Reporting a Vulnerability

**Do not open a public issue for security vulnerabilities.**

Instead, please report security issues privately via GitHub Security Advisories:
<https://github.com/tj-smith47/clift/security/advisories/new>

Include:

- Description of the vulnerability
- Steps to reproduce
- Impact assessment
- Any suggested fix (optional)

### Response Timeline

- **48 hours** — Acknowledgment of receipt
- **7 days** — Initial assessment and severity rating
- **30-90 days** — Resolution, depending on complexity

## Threat Surface

clift is a CLI framework — it provides shared bash libraries plus a Taskfile-based
router that other CLIs are built on top of. Most of its security posture is
*inherited risk* to the CLIs that consume it.

- **Consumer-CLI privilege** — clift-based CLIs run with the privileges of the
  invoking user. clift itself does not perform privileged operations, but a
  consumer CLI built on clift can (e.g., running `sudo`, modifying system files).
  Treat the framework's surface as in-process with the consumer.
- **Taskfile and command loading** — clift loads `Taskfile.yaml` files and per-command
  scripts from the consumer's CLI project directory (`cmds/<name>/Taskfile.yaml`,
  `cmds/<name>/<name>.{sh,py,go,rs,...}`). A malicious or attacker-controlled CLI
  project directory can trigger arbitrary subprocess execution when the wrapper is
  invoked. Do not run an untrusted clift CLI project without inspecting its
  Taskfiles and command scripts first.
- **Subprocess execution and env propagation** — the router parses flags and
  exports them to command scripts as `CLIFT_FLAG_*` environment variables (plus
  `CLIFT_POS_*` for positional args). Consumers control what gets executed, but
  framework bugs in env handling, exit-code propagation, or argument quoting
  could leak values or misreport failure to callers.
- **YAML / JSON parsing** — Taskfile parsing is delegated to `yq`, and help/config
  data flows through `jq`. Standard parser-trust assumptions apply: a malicious
  Taskfile is treated as code by both clift and `task`.
- **Shell completions** — generated bash/zsh completion is cache-derived from the
  consumer's Taskfiles. Dynamic flag-value completers (`clift_complete_*` functions
  in `.clift/overrides/completion.sh`) execute during shell tab-completion with
  the user's shell environment. Untrusted override files are equivalent to
  arbitrary code execution at tab time.
- **Self-update path** — `mycli update` performs a `git fetch` and fast-forward against the framework
  checkout. Standard git transport security applies; the consumer is trusting
  whatever remote their framework clone points at.
- **No network surface in the framework itself** — clift does not open sockets,
  fetch remote resources at runtime, or expose listeners. All network operations
  are consumer-defined.

## Best Practices

- Validate Taskfile.yaml and command scripts before importing a clift CLI project
  from a third party — `cmds/<name>/Taskfile.yaml` is executable definition, not
  configuration data.
- Pin clift to a specific version or commit when distributing a CLI to teammates
  (e.g., via cfgd module versioning) rather than tracking the framework branch.
- Review subprocess invocations and any `sudo`/privilege escalation in your
  command scripts; clift does not sandbox them.
- Avoid placing untrusted content in `$CLI_DIR/.clift/overrides/completion.sh` —
  completer functions run inside the user's shell.
- Keep `bash`, `task`, `jq`, and `yq` patched to current versions. clift's surface
  is only as safe as its underlying tools.
- Run consumer CLIs as a least-privileged user where possible; reserve elevation
  for commands that explicitly need it.
