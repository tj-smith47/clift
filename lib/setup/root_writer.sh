#!/usr/bin/env bash
# clift root-skeleton writer
#
# Tier 2F primitive for `clift init --from`. Emits the top-level files of a
# brand-new clift CLI:
#
#   <dest>/.clift.yaml          # name/version/deps + optional framework_namespace
#   <dest>/.env                 # CLI_NAME, CLI_VERSION, CLI_DIR (FRAMEWORK_DIR also)
#   <dest>/Taskfile.yaml        # clift-managed root with framework includes +
#                               # a sentinel where tier 4I will splice the
#                               # converted user-command includes
#   <dest>/Taskfile.user.yaml   # byte-for-byte copy of <source-taskfile>
#   <dest>/bin/<name>           # standard-mode wrapper (rendered from
#                               # lib/wrapper/wrapper.sh.tmpl via the same
#                               # placeholder convention setup.sh uses)
#
# Single entry point:
#   write_cli_skeleton <name> <dest-dir> <source-taskfile> [framework_namespace]
#
# Idempotent: re-running on a partially-written dest-dir overwrites every
# emitted file. The orchestrator (tier 4I) is responsible for collision
# detection BEFORE calling this — once we are invoked, we own these paths.
#
# `framework_namespace` is optional. When set, framework built-ins mount under
# that namespace via the aggregator at lib/_framework_aggregate.yaml (created
# in tier 3G). When unset, framework includes are listed individually at the
# top level (matching today's templates/cli/Taskfile.yaml.tmpl shape).
#
# The stable sentinel `# __USER_INCLUDES__` appears in the generated Taskfile
# as the splice point tier 4I will rewrite to add per-command includes. It is
# always inside the `includes:` block, after the framework rows (or after the
# namespaced aggregator row), so a sed-style insertion is safe.
#
# Conventions: temp-file-and-move (no `sed -i`), `set -euo pipefail`, source
# guard, shellcheck-clean, bash 4.0+. No yq at runtime.

set -euo pipefail

# shellcheck disable=SC2317  # `exit 0` fallback fires only if file is run directly
if [[ -n "${_CLIFT_ROOT_WRITER_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
_CLIFT_ROOT_WRITER_LOADED=1

_CLIFT_ROOT_WRITER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_CLIFT_ROOT_WRITER_FRAMEWORK_DIR="$(cd "$_CLIFT_ROOT_WRITER_DIR/../.." && pwd)"

# Stable splice marker for tier 4I orchestration. Tier 4I greps for this exact
# line, replaces it with one include block per converted user command. Keep
# both the comment and the underscore-flanked sentinel — the comment lives on
# in the rewritten output as a human-readable "User commands" header.
readonly _CLIFT_ROOT_USER_INCLUDES_SENTINEL='  # __USER_INCLUDES__'

# write_cli_skeleton <name> <dest-dir> <source-taskfile> [framework_namespace]
#
# Returns 0 on success. Exits nonzero with `error: ...` on stderr for
# missing args or unreadable inputs.
write_cli_skeleton() {
  if [[ $# -lt 3 ]]; then
    echo "error: write_cli_skeleton requires <name> <dest-dir> <source-taskfile> [framework_namespace]" >&2
    return 1
  fi

  local name="$1"
  local dest="$2"
  local src="$3"
  local fwns="${4:-}"

  if [[ -z "$name" ]]; then
    echo "error: write_cli_skeleton: <name> is empty" >&2
    return 1
  fi
  if [[ -z "$dest" ]]; then
    echo "error: write_cli_skeleton: <dest-dir> is empty" >&2
    return 1
  fi
  if [[ ! -e "$src" ]]; then
    echo "error: write_cli_skeleton: source taskfile not found: ${src}" >&2
    return 1
  fi
  if [[ ! -f "$src" ]]; then
    echo "error: write_cli_skeleton: source taskfile is not a regular file: ${src}" >&2
    return 1
  fi
  if [[ ! -r "$src" ]]; then
    echo "error: write_cli_skeleton: source taskfile not readable: ${src}" >&2
    return 1
  fi

  # Resolve dest to absolute. Mirrors setup.sh's portable approach (no
  # GNU `realpath -m`): cd into the parent, pwd, then re-attach basename.
  mkdir -p "$dest"
  local dest_abs
  dest_abs="$(cd "$dest" && pwd)"

  # Resolve source to absolute too — Taskfile.user.yaml is a copy, but
  # the comment in the generated wrapper benefits from a clean reference.
  local src_abs
  src_abs="$(cd "$(dirname "$src")" && pwd)/$(basename "$src")"

  local framework_dir="$_CLIFT_ROOT_WRITER_FRAMEWORK_DIR"

  _clift_root_write_clift_yaml  "$name" "$dest_abs" "$fwns"
  _clift_root_write_env         "$name" "$dest_abs" "$framework_dir"
  _clift_root_write_taskfile    "$name" "$dest_abs" "$fwns"
  _clift_root_copy_user_taskfile "$src_abs" "$dest_abs"
  _clift_root_write_wrapper     "$name" "$dest_abs" "$framework_dir"
}

# .clift.yaml — name, version, description, min_task_version, dependencies.
# `framework_namespace` is emitted only when non-empty so the schema field
# stays optional in `.clift.yaml` consumers (per prompt: "don't write
# framework_namespace: ''" when unset).
_clift_root_write_clift_yaml() {
  local name="$1" dest="$2" fwns="$3"
  local out="${dest}/.clift.yaml"
  local tmp
  tmp="$(mktemp "${out}.XXXXXX")"

  {
    printf 'name: %s\n' "$name"
    printf 'version: 0.1.0\n'
    printf 'description: ""\n'
    if [[ -n "$fwns" ]]; then
      printf 'framework_namespace: %s\n' "$fwns"
    fi
    printf 'min_task_version: "3.0.0"\n'
    printf 'dependencies:\n'
    printf '  required:\n'
    printf '    - jq\n'
    printf '    - yq\n'
    printf '  optional:\n'
    printf '    - gum\n'
  } > "$tmp"

  mv "$tmp" "$out"
}

# .env — only the contract fields the prompt enumerates plus FRAMEWORK_DIR
# (every clift CLI needs the framework path on dotenv-load; the wrapper
# template references it via %%FRAMEWORK_DIR%% but the dotenv lookup makes
# task-mode dispatch work too).
_clift_root_write_env() {
  local name="$1" dest="$2" framework_dir="$3"
  local out="${dest}/.env"
  local tmp
  tmp="$(mktemp "${out}.XXXXXX")"

  {
    printf 'CLI_NAME=%s\n' "$name"
    printf 'CLI_VERSION=%s\n' "0.1.0"
    printf 'CLI_DIR=%s\n' "$dest"
    printf 'FRAMEWORK_DIR=%s\n' "$framework_dir"
    printf 'CLIFT_MODE=%s\n' "standard"
    printf 'LOG_THEME=%s\n' "minimal"
  } > "$tmp"

  mv "$tmp" "$out"
}

# Taskfile.yaml — clift-managed root.
#
# Two shapes:
#   framework_namespace SET   → single include row mounting the aggregator
#   framework_namespace UNSET → individual rows for each framework lib
#
# Both shapes end the includes block with the user-includes sentinel so
# tier 4I has one line to splice. The sentinel is OUTSIDE the framework
# rows so tier 4I never confuses its substitution target.
_clift_root_write_taskfile() {
  local name="$1" dest="$2" fwns="$3"
  local out="${dest}/Taskfile.yaml"
  local tmp
  tmp="$(mktemp "${out}.XXXXXX")"

  {
    printf "version: '3'\n"
    printf '\n'
    printf 'silent: true\n'
    printf 'output:\n'
    printf '  group:\n'
    printf "    begin: ''\n"
    printf "    end: ''\n"
    printf 'set: [errexit, pipefail]\n'
    printf "dotenv: ['.env']\n"
    printf '\n'
    printf 'vars:\n'
    printf '  FLAGS:\n'
    printf '    - {name: help,     short: h, type: bool, desc: "Show help"}\n'
    printf '    - {name: verbose,  short: v, type: bool, desc: "Verbose output"}\n'
    printf '    - {name: quiet,    short: q, type: bool, desc: "Suppress info/success output"}\n'
    printf '    - {name: no-color,           type: bool, desc: "Disable color output"}\n'
    printf '    - {name: no-cache,           type: bool, desc: "Force-rebuild the .clift cache before this command"}\n'
    printf '    - {name: version,            type: bool, desc: "Show version"}\n'
    printf '\n'
    printf 'includes:\n'
    if [[ -n "$fwns" ]]; then
      # Aggregator mode — namespace the user-facing framework commands
      # under <fwns>:*. Underscored infrastructure includes (`_help`,
      # `_log`) MUST stay at the top level: the wrapper's `--help`
      # short-circuit invokes `task ... _help:list` directly, and the
      # router sources `_log` for themed logging. They are framework-
      # internal, never user-facing, and their underscore prefix keeps
      # them out of the user's command tree, so they cannot collide
      # with imported task names.
      printf '  _help:\n'
      printf "    taskfile: '{{.FRAMEWORK_DIR}}/lib/help'\n"
      printf '  _log:\n'
      printf "    taskfile: '{{.FRAMEWORK_DIR}}/lib/log'\n"
      printf '  %s:\n' "$fwns"
      printf "    taskfile: '{{.FRAMEWORK_DIR}}/lib/_framework_aggregate.yaml'\n"
    else
      # Per-command mode — same shape as templates/cli/Taskfile.yaml.tmpl.
      printf '  _help:\n'
      printf "    taskfile: '{{.FRAMEWORK_DIR}}/lib/help'\n"
      printf '  _log:\n'
      printf "    taskfile: '{{.FRAMEWORK_DIR}}/lib/log'\n"
      printf '  new:\n'
      printf "    taskfile: '{{.FRAMEWORK_DIR}}/lib/scaffold'\n"
      printf '  config:\n'
      printf "    taskfile: '{{.FRAMEWORK_DIR}}/lib/config'\n"
      printf '  update:\n'
      printf "    taskfile: '{{.FRAMEWORK_DIR}}/lib/update'\n"
      printf '  completion:\n'
      printf "    taskfile: '{{.FRAMEWORK_DIR}}/lib/completion'\n"
      printf '  version:\n'
      printf "    taskfile: '{{.FRAMEWORK_DIR}}/lib/version'\n"
    fi
    printf '\n'
    printf '  # User commands\n'
    printf '%s\n' "$_CLIFT_ROOT_USER_INCLUDES_SENTINEL"
    printf '\n'
    printf 'tasks:\n'
    printf '  default:\n'
    printf '    desc: "Show help"\n'
    printf '    cmd:\n'
    # `_help` is mounted at the top level in BOTH modes (see the
    # includes block above). The wrapper's `--help` short-circuit hits
    # `_help:list` directly, so this default-task path matches.
    printf '      task: _help:list\n'
  } > "$tmp"

  mv "$tmp" "$out"
}

# Taskfile.user.yaml — verbatim copy of the source. `cp -- "$src" "$dest"`
# preserves byte-for-byte content, including any trailing newline conventions
# the user wrote. We use `--` so a source path starting with `-` won't be
# misinterpreted as a flag.
_clift_root_copy_user_taskfile() {
  local src="$1" dest="$2"
  cp -- "$src" "${dest}/Taskfile.user.yaml"
}

# bin/<name> — standard-mode wrapper. Renders lib/wrapper/wrapper.sh.tmpl
# via the same %%PLACEHOLDER%% convention setup.sh uses (line 196-198).
# Bash parameter expansion instead of sed — immune to delimiter/metacharacter
# injection from paths (matching setup.sh's _render_template helper).
_clift_root_write_wrapper() {
  local name="$1" dest="$2" framework_dir="$3"
  local tmpl="${framework_dir}/lib/wrapper/wrapper.sh.tmpl"
  local out_dir="${dest}/bin"
  local out="${out_dir}/${name}"

  if [[ ! -f "$tmpl" ]]; then
    echo "error: write_cli_skeleton: wrapper template missing: ${tmpl}" >&2
    return 1
  fi

  mkdir -p "$out_dir"

  local tmp
  tmp="$(mktemp "${out}.XXXXXX")"

  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line//%%FRAMEWORK_DIR%%/$framework_dir}"
    line="${line//%%CLI_DIR%%/$dest}"
    line="${line//%%CLI_NAME%%/$name}"
    line="${line//%%CLI_VERSION%%/0.1.0}"
    line="${line//%%LOG_THEME%%/minimal}"
    line="${line//%%CLIFT_MODE%%/standard}"
    printf '%s\n' "$line"
  done < "$tmpl" > "$tmp"

  mv "$tmp" "$out"
  chmod +x "$out"
}

# When invoked directly (`bash root_writer.sh <name> <dest> <src> [ns]`)
# act as a thin CLI for shell-side smoke testing. Sourced usage skips this
# branch via the load-guard at the top of the file.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  write_cli_skeleton "$@"
fi
