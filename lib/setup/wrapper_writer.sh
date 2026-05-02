#!/usr/bin/env bash
# clift wrapper / cmds-Taskfile writer
#
# Tier 2D + 2E generators for `clift init --from`. Given a single task
# entry from `lib/setup/from_taskfile.sh::read_source` output, emit the
# two artefacts needed under `cmds/<name>/`:
#
#   <dest-dir>/<name>.sh        — wrapper script that execs `task --taskfile
#                                 ${CLI_DIR}/Taskfile.user.yaml` against the
#                                 wrapped task. Three variants:
#                                   * passthrough  — no FLAGS, args via `--`
#                                   * parsed-flag  — FLAGS bind to vars
#                                   * wildcard     — one positional → `*` segment
#
#   <dest-dir>/Taskfile.yaml    — clift-side command Taskfile. Has
#                                 `vars.FLAGS` for parsed-flag tasks; omits
#                                 `vars.FLAGS` entirely for passthrough +
#                                 wildcard (router's true-passthrough mode,
#                                 spec issue #4).
#
# Two entry points:
#   write_wrapper_script <task-json> <dest-dir>
#   write_cmd_taskfile   <task-json> <dest-dir>
#
# Input contract: <task-json> is one entry from the read_source `.tasks[]`
# array — see lib/setup/from_taskfile.sh's header for the schema.
#
# Integration boundary: the reader emits JSON-decoded vars values
# (`false` is JSON `false`, `"true"` is JSON `"true"`). var_inference's
# `infer_flag` expects YAML-literal text, so each vars value is
# re-serialized via `jq -r 'tojson'` before being passed in.

set -euo pipefail

# shellcheck disable=SC2317  # `exit 0` fallback fires only if file is run directly
if [[ -n "${_CLIFT_WRAPPER_WRITER_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
_CLIFT_WRAPPER_WRITER_LOADED=1

_CLIFT_WRAPPER_WRITER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./var_inference.sh
. "$_CLIFT_WRAPPER_WRITER_DIR/var_inference.sh"

# _ww_upper_underscore <name>
# Mirrors the CLIFT_FLAG_<UPPER> contract from the project conventions:
# uppercase, dashes → underscores. Used to construct the env-var name a
# parsed-flag wrapper reads when it forwards the flag value as a go-task
# var assignment.
_ww_upper_underscore() {
  local s="$1"
  s="${s^^}"
  s="${s//-/_}"
  printf '%s' "$s"
}

# _ww_yaml_escape_double <text>
# Escapes <text> for safe inclusion inside a double-quoted YAML scalar:
# backslash → \\, double-quote → \". No newline handling — callers
# must not pass multi-line text through this helper.
_ww_yaml_escape_double() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

# _ww_yaml_aliases <json-array>
# Emits a flow-style YAML alias list (`[a, b]`) from a JSON string array,
# or emits nothing when the array is empty (caller drops the field).
_ww_yaml_aliases() {
  local arr_json="$1"
  local count
  count="$(jq -r 'length' <<< "$arr_json")"
  if [[ "$count" -eq 0 ]]; then
    return 0
  fi
  jq -r '"[" + (map(tostring) | join(", ")) + "]"' <<< "$arr_json"
}

# _ww_substitute_wildcard <task> <target-shell-var>
# Replaces the first `*` in <task> with `${<target-shell-var>}` so a
# wildcard like `deploy:*` becomes `deploy:${target}` and
# `build:*:release` becomes `build:${target}:release`. Pure string
# substitution — no shell expansion.
_ww_substitute_wildcard() {
  local task="$1"
  local var="$2"
  printf '%s' "${task/\*/\$\{${var}\}}"
}

# _ww_build_flags_json <task-json>
# Builds a JSON array of FLAG entries from the task's `requires_vars`
# (each → `infer_required`) and `vars` map (each → `infer_flag`). Emits
# `[]` when both are empty. Bails non-zero if any inference fails.
_ww_build_flags_json() {
  local entry="$1"
  local entries=()

  # Required (string) flags first — preserves declaration order.
  local req_count req_var
  req_count="$(jq -r '.requires_vars | length' <<< "$entry")"
  if [[ "$req_count" -gt 0 ]]; then
    while IFS= read -r req_var; do
      [[ -z "$req_var" ]] && continue
      local req_json
      req_json="$(infer_required "$req_var")" || return 1
      entries+=("$req_json")
    done < <(jq -r '.requires_vars[]' <<< "$entry")
  fi

  # Optional vars: map. Re-serialize each value via tojson so the YAML
  # literal text is what var_inference receives (true → `true`,
  # "true" → `"true"`, 3 → `3`, "myapp" → `"myapp"`, …).
  local var_count
  var_count="$(jq -r '.vars | length' <<< "$entry")"
  if [[ "$var_count" -gt 0 ]]; then
    while IFS=$'\t' read -r vname vyaml; do
      [[ -z "$vname" ]] && continue
      local var_json
      var_json="$(infer_flag "$vname" "$vyaml")" || return 1
      entries+=("$var_json")
    done < <(jq -r '.vars | to_entries[] | "\(.key)\t\(.value | tojson)"' <<< "$entry")
  fi

  if [[ ${#entries[@]} -eq 0 ]]; then
    printf '[]'
    return 0
  fi
  printf '%s\n' "${entries[@]}" | jq -cs '.'
}

# _ww_render_flags_yaml <flags-json>
# Renders a JSON array of FLAG entries as the YAML fragment that goes
# under `vars.FLAGS:` — one flow-style mapping per line, indented six
# spaces (matches templates/command/Taskfile.yaml.tmpl shape).
_ww_render_flags_yaml() {
  local flags_json="$1"
  jq -r '
    .[] |
    "      - "
    + "{name: " + .name
    + ", type: " + .type
    + (if has("required") and .required then ", required: true" else "" end)
    + (if has("default") then
        ", default: " + (
          if (.default | type) == "string" then ("\"" + (.default | tostring | gsub("\\\\"; "\\\\") | gsub("\""; "\\\"")) + "\"")
          elif (.default | type) == "boolean" then (.default | tostring)
          elif (.default | type) == "number" then (.default | tostring)
          else (.default | tojson)
          end
        )
       else "" end)
    + "}"
  ' <<< "$flags_json"
}

# write_wrapper_script <task-json> <dest-dir> [override-script-name]
# Writes <dest-dir>/<name>.sh and chmods +x. Variant chosen from the
# `passthrough` / `wildcard` flags on the task entry.
#
# When [override-script-name] is provided, the wrapper is written to
# <dest-dir>/<override>.sh instead of deriving the filename from the
# task's clift-side `name`. Used by the orchestrator to relocate a
# bare-top wrapper (e.g. `lint.sh` → `lint.default.sh`) when a
# dispatcher script needs to claim the `<top>.sh` slot for a namespace
# group with multiple tasks.
#
# Returns 0 on success, nonzero on bad input.
write_wrapper_script() {
  if [[ $# -lt 2 ]]; then
    echo "error: wrapper_writer: write_wrapper_script requires <task-json> <dest-dir> [override-script-name]" >&2
    return 1
  fi
  local entry="$1"
  local dest_dir="$2"
  local override_name="${3:-}"

  if [[ ! -d "$dest_dir" ]]; then
    echo "error: wrapper_writer: dest dir not found: ${dest_dir}" >&2
    return 1
  fi

  local name task wildcard passthrough
  name="$(jq -r '.name'        <<< "$entry")"
  task="$(jq -r '.task'        <<< "$entry")"
  wildcard="$(jq -r '.wildcard'    <<< "$entry")"
  passthrough="$(jq -r '.passthrough' <<< "$entry")"

  if [[ -z "$name" || "$name" == "null" ]]; then
    echo "error: wrapper_writer: task entry missing .name" >&2
    return 1
  fi
  if [[ -z "$task" || "$task" == "null" ]]; then
    echo "error: wrapper_writer: task entry missing .task" >&2
    return 1
  fi

  # Wrappers live under cmds/<top>/. By default the filename mirrors the
  # clift task name (colons → dots) so namespaced subcommands like
  # `db:migrate` land at `cmds/db/db.migrate.sh` without colliding. The
  # caller may override when it wants a different filename — see the
  # dispatcher coordination above.
  local script_name
  if [[ -n "$override_name" ]]; then
    script_name="$override_name"
  else
    script_name="${name//:/.}"
  fi
  local dest="${dest_dir}/${script_name}.sh"

  # Single-quoted heredoc — no shell expansion inside the body. The
  # literal task name is interpolated via printf %q after the heredoc
  # write so backslashes / single-quotes / spaces survive intact.
  local task_quoted
  task_quoted="$(printf '%q' "$task")"

  if [[ "$wildcard" == "true" ]]; then
    # Wildcard variant: one positional → substituted into the `*` slot.
    # Wildcard tasks are imported as router-passthrough (no FLAGS), so
    # the router execs us with the user's argv as `$1`, `$2`, ... — NOT
    # via CLIFT_POS_*. Read $1 directly with the `:?` guard so
    # `mycli deploy` (no target) fails with a clear usage line.
    local target_expr
    target_expr="$(_ww_substitute_wildcard "$task" "target")"
    cat > "$dest" <<WRAPPER
#!/usr/bin/env bash
# Generated by \`clift init --from\`
# Wraps go-task wildcard: ${task} (from Taskfile.user.yaml)
set -euo pipefail
target="\${1:?Usage: ${name} <TARGET>}"
exec task --silent --taskfile "\${CLI_DIR}/Taskfile.user.yaml" "${target_expr}"
WRAPPER
  elif [[ "$passthrough" == "true" ]]; then
    # Passthrough variant: forward positional args via go-task's `--`
    # separator. The router's true-passthrough path execs this script with
    # the user's argv as `$@` (no FLAGS table, no CLIFT_POS_* exports), so
    # we forward `$@` directly. The exec line uses bash's nested-quoting
    # idiom — `"${arr[@]+"${arr[@]}"}"` — which expands to nothing when the
    # array is empty and to each element quoted otherwise. Inner
    # double-quotes are intentional and unescaped.
    cat > "$dest" <<WRAPPER
#!/usr/bin/env bash
# Generated by \`clift init --from\`
# Wraps go-task task: ${task} (from Taskfile.user.yaml)
set -euo pipefail
exec task --silent --taskfile "\${CLI_DIR}/Taskfile.user.yaml" ${task_quoted} -- "\${@}"
WRAPPER
  else
    # Parsed-flag variant: each var conditionally forwards as a
    # `KEY=value` assignment to go-task only when the parser exported the
    # corresponding CLIFT_FLAG_<UPPER> env var. This keeps `set -u` happy
    # and — critically — preserves go-task's source defaults for bool
    # vars the user did NOT pass on the command line. Required vars are
    # always exported by the parser, so their assignment fires every run.
    # Required vars come first, then vars-map keys — matches the
    # FLAGS-list order used by write_cmd_taskfile.
    local -a flag_uppers=()
    local v upper

    while IFS= read -r v; do
      [[ -z "$v" ]] && continue
      upper="$(_ww_upper_underscore "$v")"
      flag_uppers+=("$upper")
    done < <(jq -r '.requires_vars[]' <<< "$entry")

    while IFS= read -r v; do
      [[ -z "$v" ]] && continue
      upper="$(_ww_upper_underscore "$v")"
      flag_uppers+=("$upper")
    done < <(jq -r '.vars | keys_unsorted[]' <<< "$entry")

    # Literal-text emission: every printf format string below is intentionally
    # single-quoted so `${CLI_DIR}`, `{{.CLI_ARGS}}`, etc. survive verbatim
    # into the rendered wrapper. shellcheck's SC2016 ("expressions don't
    # expand in single quotes") is the goal here, not a bug.
    {
      printf '#!/usr/bin/env bash\n'
      # shellcheck disable=SC2016
      printf '# Generated by `clift init --from`\n'
      printf '# Wraps go-task task: %s (from Taskfile.user.yaml)\n' "$task"
      printf 'set -euo pipefail\n'
      if [[ ${#flag_uppers[@]} -eq 0 ]]; then
        # No vars: still emit a parsed-flag wrapper (caller chose this
        # variant) — exec line without trailing assignments.
        # shellcheck disable=SC2016
        printf 'exec task --silent --taskfile "${CLI_DIR}/Taskfile.user.yaml" %s\n' "$task_quoted"
      else
        printf '_args=()\n'
        local u
        for u in "${flag_uppers[@]}"; do
          # Each line: forward `KEY=value` only when the env var exists.
          # Using `${VAR+x}` keeps the test set-u-safe; the inner `${VAR}`
          # is guarded by the test result so it never expands when unset.
          # shellcheck disable=SC2016
          printf '[[ -n "${CLIFT_FLAG_%s+x}" ]] && _args+=("%s=${CLIFT_FLAG_%s}")\n' \
            "$u" "$u" "$u"
        done
        # Use the nested-quoting idiom so an empty array expands to nothing
        # instead of tripping `set -u` ("unbound variable" on empty arrays).
        # shellcheck disable=SC2016
        printf 'exec task --silent --taskfile "${CLI_DIR}/Taskfile.user.yaml" %s "${_args[@]+"${_args[@]}"}"\n' "$task_quoted"
      fi
    } > "$dest"
  fi

  chmod +x "$dest"
}

# _ww_emit_task_block <entry> <task-key>
# Emits a single `tasks:` entry under key <task-key> for the given task
# JSON. Used by write_cmd_taskfile when emitting either a lone `default`
# block or one block per sub-task in a multi-task Taskfile. Output goes
# to stdout (caller redirects to the destination file).
_ww_emit_task_block() {
  local entry="$1"
  local key="$2"

  local task desc summary aliases_json wildcard passthrough
  task="$(jq -r '.task'        <<< "$entry")"
  desc="$(jq -r '.desc'        <<< "$entry")"
  summary="$(jq -r '.summary'  <<< "$entry")"
  aliases_json="$(jq -c '.aliases' <<< "$entry")"
  wildcard="$(jq -r '.wildcard'    <<< "$entry")"
  passthrough="$(jq -r '.passthrough' <<< "$entry")"

  # Wildcard tasks override desc to inject the <TARGET> hint so
  # `mycli <cmd> --help` reads as `<cmd> <TARGET>`. When the source desc
  # is empty we synthesize a placeholder pointing at the source task.
  if [[ "$wildcard" == "true" ]]; then
    if [[ -z "$desc" ]]; then
      desc="Wraps go-task wildcard ${task}"
    else
      desc="${desc} <TARGET>"
    fi
  fi

  local desc_yaml
  desc_yaml="$(_ww_yaml_escape_double "$desc")"

  local aliases_yaml=""
  aliases_yaml="$(_ww_yaml_aliases "$aliases_json")"

  printf '  %s:\n' "$key"
  printf '    desc: "%s"\n' "$desc_yaml"
  if [[ -n "$summary" ]]; then
    printf '    summary: |\n'
    # Indent each summary line by six spaces under the literal block.
    while IFS= read -r line; do
      printf '      %s\n' "$line"
    done <<< "$summary"
  fi
  if [[ -n "$aliases_yaml" ]]; then
    printf '    aliases: %s\n' "$aliases_yaml"
  fi

  # Parsed-flag tasks: emit `vars.FLAGS:` block. Passthrough + wildcard
  # tasks: omit the block entirely (router's true-passthrough mode).
  if [[ "$passthrough" != "true" && "$wildcard" != "true" ]]; then
    local flags_json flags_yaml
    flags_json="$(_ww_build_flags_json "$entry")" || return 1
    printf '    vars:\n'
    printf '      FLAGS:\n'
    flags_yaml="$(_ww_render_flags_yaml "$flags_json")"
    if [[ -n "$flags_yaml" ]]; then
      printf '%s\n' "$flags_yaml"
    fi
  fi
  printf '    cmd: "CLI_ARGS='"'"'{{.CLI_ARGS}}'"'"' '"'"'{{.FRAMEWORK_DIR}}/lib/router/router.sh'"'"' '"'"'{{.TASK}}'"'"'"\n'
}

# _ww_task_block_key <entry> <top>
# Computes the YAML map key for a task entry inside cmds/<top>/Taskfile.yaml.
#   bare top (`build`)        → `default`
#   namespace default
#     (task = `lint:default`) → `default`
#   namespace sub
#     (task = `lint:eslint`)  → `eslint`
#   wildcard (`deploy:*`,
#     name = `deploy`)        → `default`
#   nested wildcard
#     (task = `db:*:reset`,
#      name = `db:reset`)     → `reset`
# In other words: take the clift-side `name`, strip the leading `<top>`
# segment, and use what's left (or `default` when nothing remains).
_ww_task_block_key() {
  local entry="$1"
  local top="$2"
  local name
  name="$(jq -r '.name' <<< "$entry")"
  if [[ "$name" == "$top" ]]; then
    printf 'default'
  elif [[ "$name" == "${top}:"* ]]; then
    printf '%s' "${name#"${top}":}"
  else
    # Defensive: a task whose name doesn't share <top> shouldn't reach
    # this writer (the orchestrator groups by top before calling). Fall
    # back to `default` rather than emit invalid YAML.
    printf 'default'
  fi
}

# write_dispatcher_script <top> <dest-dir>
# Writes <dest-dir>/<top>.sh as a tiny dispatcher used when multiple tasks
# share a top-level segment (`lint:default` + `lint:eslint`). Reason: the
# router's passthrough path resolves every task in the group to
# `cmds/<top>/<top>.sh` regardless of sub-segment, so a single physical
# script must handle both `mycli lint` and `mycli lint eslint` correctly.
# The dispatcher reads CLIFT_TASK (exported by the router) and execs the
# matching per-task wrapper (`<top>.<sub>.sh`), with the bare top
# falling through to its own wrapper (suffix `.sh`).
#
# Per-task wrappers are still written by write_wrapper_script — this
# function only emits the dispatch shim. Single-task groups never call
# this; their single wrapper IS `<top>.sh` directly.
write_dispatcher_script() {
  if [[ $# -lt 2 ]]; then
    echo "error: wrapper_writer: write_dispatcher_script requires <top> <dest-dir>" >&2
    return 1
  fi
  local top="$1"
  local dest_dir="$2"

  if [[ ! -d "$dest_dir" ]]; then
    echo "error: wrapper_writer: dest dir not found: ${dest_dir}" >&2
    return 1
  fi

  local dest="${dest_dir}/${top}.sh"

  # Single-quoted heredoc — the body uses framework-runtime env vars
  # (CLIFT_TASK, CLI_DIR) and must not be expanded at write time.
  cat > "$dest" <<'DISPATCHER_HEAD'
#!/usr/bin/env bash
# Generated by `clift init --from`
# Dispatcher for a namespace group — re-routes by CLIFT_TASK.
# The router's passthrough path resolves every `<top>:<sub>` task to this
# single script; we forward to the per-task wrapper (`<top>.<sub>.sh`).
set -euo pipefail
DISPATCHER_HEAD

  # The dispatcher's <top> is fixed at write time; bake it into the
  # `script_name` derivation. Anything else stays in env vars.
  printf '_top=%q\n' "$top" >> "$dest"
  cat >> "$dest" <<'DISPATCHER_BODY'
_task="${CLIFT_TASK:-$_top}"
if [[ "$_task" == *:* ]]; then
  _script="${_task//:/.}.sh"
else
  _script="${_top}.${_task}.sh"
fi
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_target="${_dir}/${_script}"
if [[ ! -f "$_target" ]]; then
  # Fall back to the bare-top wrapper when the sub-script is missing —
  # covers tasks named `<top>:default` whose wrapper landed at
  # `<top>.default.sh` only if the orchestrator emitted it that way.
  _target="${_dir}/${_top}.default.sh"
fi
if [[ ! -f "$_target" ]]; then
  echo "error: dispatcher could not resolve task '${_task}' under '${_top}'" >&2
  exit 1
fi
exec bash "$_target" "$@"
DISPATCHER_BODY

  chmod +x "$dest"
}

# write_cmd_taskfile <entry-or-array> <dest-dir>
# Writes <dest-dir>/Taskfile.yaml. Two input shapes:
#   1. Single task object — emits one `default` block (legacy shape).
#   2. JSON array of task objects sharing one top-level segment — emits
#      one block per task, keyed by sub-segment (`<top>:default` →
#      `default`, `<top>:<sub>` → `<sub>`).
# Parsed-flag tasks get a `vars.FLAGS:` block; passthrough + wildcard
# tasks omit `vars.FLAGS` so the router uses true-passthrough dispatch
# (spec issue #4).
write_cmd_taskfile() {
  if [[ $# -lt 2 ]]; then
    echo "error: wrapper_writer: write_cmd_taskfile requires <entry-or-array> <dest-dir>" >&2
    return 1
  fi
  local input="$1"
  local dest_dir="$2"

  if [[ ! -d "$dest_dir" ]]; then
    echo "error: wrapper_writer: dest dir not found: ${dest_dir}" >&2
    return 1
  fi

  local input_type
  input_type="$(jq -r 'type' <<< "$input")"

  local dest="${dest_dir}/Taskfile.yaml"

  if [[ "$input_type" == "array" ]]; then
    # Multi-task mode. Compute the shared top from the first task's name
    # so the keying logic works for both bare and namespaced groups.
    local top first_name
    first_name="$(jq -r '.[0].name' <<< "$input")"
    top="${first_name%%:*}"

    local count i entry key
    count="$(jq -r 'length' <<< "$input")"

    {
      printf "version: '3'\n"
      printf '\n'
      printf 'tasks:\n'
      for (( i=0; i<count; i++ )); do
        entry="$(jq -c ".[$i]" <<< "$input")"
        key="$(_ww_task_block_key "$entry" "$top")"
        _ww_emit_task_block "$entry" "$key" || return 1
      done
    } > "$dest"
    return 0
  fi

  # Single-task mode (legacy / direct callers). Always emits as `default`.
  {
    printf "version: '3'\n"
    printf '\n'
    printf 'tasks:\n'
    _ww_emit_task_block "$input" "default" || return 1
  } > "$dest"
}

# Direct-invocation CLI for dogfooding / debugging. Sourced usage skips
# this branch via the load guard at the top of the file.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    wrapper)  shift; write_wrapper_script "$@" ;;
    taskfile) shift; write_cmd_taskfile   "$@" ;;
    *)
      echo "usage: wrapper_writer.sh {wrapper|taskfile} <task-json> <dest-dir>" >&2
      exit 1
      ;;
  esac
fi
