#!/usr/bin/env bash
# clift `init --from` orchestrator
#
# Tier 4I + 4J of the import redesign. Wires together the tier 1/2/3
# primitives into the user-facing one-shot bootstrap:
#
#     init_from.sh <dir> --from PATH [--prefix STR] [--rename SRC=DST]...
#                        [--framework-namespace NS] [--yes]
#
# Runs end-to-end:
#   1. Parse flags.
#   2. Resolve --from (file | directory containing Taskfile.yaml | `-` stdin).
#   3. Read source via lib/setup/from_taskfile.sh::read_source.
#   4. Apply --prefix / --rename overlays to each task's clift-side `name`.
#      The original go-task `task` field is preserved verbatim so dispatch
#      keeps working — only the user-visible identifier changes.
#   5. Detect collisions BEFORE any files are written:
#        * self-collisions (two final names equal)
#        * reserved-name collisions (final name matches a framework command,
#          unless --framework-namespace moves built-ins out of the way)
#      The reserved list is derived at runtime from
#      lib/_framework_aggregate.yaml's top-level includes — never hardcoded
#      in this file, so adding a new framework command (a new include row)
#      automatically extends the reserved list without touching this script.
#      On collision: print a three-resolution-paths error and exit 1
#      atomically (no partial dest dir).
#   6. Source root_writer.sh — emit .clift.yaml, .env, root Taskfile.yaml
#      (with the user-includes sentinel), Taskfile.user.yaml, bin/<name>.
#   7. Source wrapper_writer.sh — emit cmds/<top>/Taskfile.yaml +
#      cmds/<top>/<task>.sh per task (with mkdir -p <top> as needed).
#   8. Splice user-includes into the root Taskfile by replacing the sentinel
#      line with one `<top>: { taskfile: ./cmds/<top> }` row per top-level
#      command (deduped). Temp-file-and-move — never sed -i.
#   9. Print the success summary (created files, command count, next steps).
#
# Decision (recorded here per the prompt): `--framework-namespace` on a BLANK
# `task setup:cli -- <dir>` is OUT OF SCOPE for this tier. Users wanting
# framework-namespace mode without `--from` edit `.clift.yaml` post-init
# (the schema field is already supported by root_writer.sh and the help
# layer). Avoiding the dual code path keeps the blank-init flow on the
# stable existing surface (lib/setup/setup.sh) untouched.
#
# Invocation:
#   bash lib/setup/init_from.sh <dir> --from PATH [--prefix STR] ...
# Sourced via shebang, never as a module — no source guard needed.

set -euo pipefail

_INIT_FROM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_INIT_FROM_FRAMEWORK_DIR="$(cd "$_INIT_FROM_DIR/../.." && pwd)"

# shellcheck source=../log/log.sh
. "$_INIT_FROM_FRAMEWORK_DIR/lib/log/log.sh"
# shellcheck source=./from_taskfile.sh
. "$_INIT_FROM_DIR/from_taskfile.sh"
# shellcheck source=./root_writer.sh
. "$_INIT_FROM_DIR/root_writer.sh"
# shellcheck source=./wrapper_writer.sh
. "$_INIT_FROM_DIR/wrapper_writer.sh"

_usage() {
  cat <<'USAGE' >&2
Usage:
  init_from.sh <dir> --from PATH [--prefix STR] [--rename SRC=DST]...
                     [--framework-namespace NS] [--yes]

Bootstrap a brand-new clift CLI under <dir> from an existing go-task
Taskfile. <dir> is created if absent; existing files are overwritten.

Flags:
  --from PATH               Required. Source Taskfile path. PATH may be:
                              <file>  → use directly
                              <dir>   → look for Taskfile.yaml inside
                              -       → read stdin into a temp file
  --prefix STR              Prepend STR to every imported task's clift
                            name. The go-task task identifier (used for
                            dispatch) is preserved verbatim.
  --rename SRC=DST          Repeatable. Rewrite the final clift name from
                            SRC to DST. Applied AFTER --prefix.
  --framework-namespace NS  Mount framework built-ins under <CLI> NS:* so
                            user tasks named `config`, `version`, etc.
                            don't collide. Also resolves reserved-name
                            collisions surfaced by the orchestrator.
  --yes                     Suppress interactive confirmation. (Reserved —
                            the current orchestrator never prompts; flag
                            accepted for forward-compat.)
USAGE
}

# _resolve_source <path-arg>
#   - `-`        → drain stdin into a temp file (cleaned up via trap below)
#   - <dir>      → <dir>/Taskfile.yaml, error if missing
#   - <file>     → use as-is (resolved to absolute)
# Echoes the absolute path on stdout. Exits 3 if the file cannot be located.
_INIT_FROM_TMP_SOURCE=""
_resolve_source() {
  local arg="$1"

  if [[ -z "$arg" ]]; then
    log_error "missing --from PATH"
    exit 1
  fi

  if [[ "$arg" == "-" ]]; then
    local tmp
    tmp="$(mktemp -t clift-init-from.XXXXXX.yaml)"
    _INIT_FROM_TMP_SOURCE="$tmp"
    if ! cat > "$tmp"; then
      log_error "failed to read stdin into ${tmp}"
      exit 3
    fi
    if [[ ! -s "$tmp" ]]; then
      log_error "stdin produced no content for --from -"
      exit 3
    fi
    printf '%s\n' "$tmp"
    return 0
  fi

  if [[ -d "$arg" ]]; then
    local candidate="${arg%/}/Taskfile.yaml"
    if [[ ! -f "$candidate" ]]; then
      log_error "no Taskfile.yaml found in directory ${arg}"
      exit 3
    fi
    arg="$candidate"
  fi

  if [[ ! -f "$arg" ]]; then
    log_error "source not found: ${arg}"
    exit 3
  fi

  printf '%s\n' "$(cd "$(dirname "$arg")" && pwd)/$(basename "$arg")"
}

# Cleanup hook for the stdin temp file. mktemp puts it in $TMPDIR — we
# leave the file behind otherwise so users can re-run with --from <tmp>
# for debugging if anything went sideways before this trap fires.
_init_from_cleanup() {
  if [[ -n "${_INIT_FROM_TMP_SOURCE}" && -f "${_INIT_FROM_TMP_SOURCE}" ]]; then
    rm -f "$_INIT_FROM_TMP_SOURCE"
  fi
}
trap _init_from_cleanup EXIT

# _framework_reserved_names
# Reads the top-level `includes:` keys from lib/_framework_aggregate.yaml
# at runtime — that file is the single source of truth for framework
# commands. Hardcoding the list here would silently drift the moment a
# new framework command lands. Returns one name per line on stdout.
#
# `_help` and `_log` are intentionally excluded: the aggregator only
# mounts user-facing commands, and that's the surface the framework
# claims. Underscored infrastructure includes never reach the user-facing
# top level so they cannot collide.
_framework_reserved_names() {
  local agg="$_INIT_FROM_FRAMEWORK_DIR/lib/_framework_aggregate.yaml"
  if [[ ! -f "$agg" ]]; then
    # Aggregator missing → fall back to the historic stable list documented
    # in the import redesign plan. Keep this list in sync with the agg.
    printf '%s\n' config version update completion new
    return 0
  fi
  yq -r '.includes | keys | .[]' "$agg" 2>/dev/null
}

# _drop_wildcards_shadowed_by_plain <document-json>
# When a source declares BOTH a plain `<top>` task AND a wildcard task
# whose normalized clift-name collapses to the same top (`<top>:*`,
# `<top>:*:release`, etc.), the plain task wins and the wildcard is
# dropped. clift's command tree has only one slot per name, so the
# wildcard would be unreachable as `mycli <top> <X>` regardless — go-task
# itself resolves `task <top>` to the literal task and never to the
# wildcard, so the user's wildcard intent has no working dispatch path
# in this CLI.
#
# Behaviour mirrors go-task's own literal-takes-precedence rule. We
# emit a `note:` line to stderr per dropped wildcard so the user is
# aware their wildcard task didn't make it into the CLI; an explicit
# --rename can recover it under a different name.
#
# Pure jq filter — emits the filtered JSON document on stdout. Notes
# are emitted as a side effect (stderr) before the filtered document.
_drop_wildcards_shadowed_by_plain() {
  local doc="$1"

  # Names that occur 2+ times in the post-rename task set. A wildcard
  # whose name lands in this set is shadowed by a plain (or another
  # wildcard) sharing the slot.
  local colliding_json
  colliding_json="$(jq -c '
    [ .tasks[].name ]
    | group_by(.)
    | map(select(length > 1) | .[0])
  ' <<< "$doc")"

  # Wildcard tasks whose name appears in $colliding_json — the set we
  # drop. Each gets a stderr note before the doc is filtered.
  local dropped_json
  dropped_json="$(jq -c --argjson colliding "$colliding_json" '
    [ .tasks[]
      | select(.wildcard == true)
      | select(.name as $n | $colliding | index($n))
      | { task: .task, name: .name }
    ]
  ' <<< "$doc")"

  local dropped_count
  dropped_count="$(jq -r 'length' <<< "$dropped_json")"

  if [[ "$dropped_count" -gt 0 ]]; then
    jq -r '
      .[] |
      "note: dropping wildcard task `" + .task + "` — shadowed by plain `" + .name + "` (clift command tree has one slot per name; use --rename to keep both)"
    ' <<< "$dropped_json" >&2
  fi

  # Filter the doc: keep every task that ISN'T a shadowed wildcard.
  jq -c --argjson colliding "$colliding_json" '
    .tasks |= map(
      select(
        (.wildcard != true)
        or (.name as $n | $colliding | index($n) | not)
      )
    )
  ' <<< "$doc"
}

# _apply_renames <tasks-json> <prefix> <rename-pairs-json>
# Rewrites each task entry's `.name`:
#   1. prepend prefix (if non-empty)
#   2. apply each `SRC=DST` rename (later renames override earlier ones)
# Pure jq pass — emits the rewritten JSON document on stdout.
_apply_renames() {
  local tasks_json="$1" prefix="$2" renames_json="$3"
  jq --arg prefix "$prefix" --argjson renames "$renames_json" '
    . as $root |
    .tasks |= map(
      . as $t |
      ($t.name) as $orig |
      ( if $prefix == "" then $orig else $prefix + $orig end ) as $prefixed |
      ( $renames
        | reduce .[] as $r (
            $prefixed;
            if $r.src == . then $r.dst else . end
          )
      ) as $final |
      .name = $final
    )
  ' <<< "$tasks_json"
}

# _detect_collisions <document-json> <fwns> <basename>
# Emits any collision report to stderr and returns nonzero on collision.
# Two cases reported:
#   1. self-collision — two or more imported tasks ended up with the same
#      final name (usually a --rename mistake). Lists each duplicate
#      alongside the source go-task names that produced it.
#   2. reserved-name collision — a final name matches a framework command,
#      and --framework-namespace was NOT set. Skipped entirely when fwns
#      is non-empty (framework built-ins move to <basename> NS:*).
#
# Both reports include the user's <basename> in the error so the message
# reads as `mycli config` not abstractly `config`.
_detect_collisions() {
  local doc="$1" fwns="$2" basename="$3"

  # Self-collisions first — these can land before reserved-name pressure
  # ever applies (e.g., `--rename a=foo --rename b=foo`).
  local dup_names_json
  dup_names_json="$(jq -c '
    [ .tasks | group_by(.name)[]
      | select(length > 1)
      | { final: .[0].name, sources: [ .[].task ] }
    ]
  ' <<< "$doc")"

  local dup_count
  dup_count="$(jq -r 'length' <<< "$dup_names_json")"
  if [[ "$dup_count" -gt 0 ]]; then
    {
      printf 'error: %s task(s) collide after rename:\n' "$dup_count"
      jq -r '
        .[]
        | "  " + .final
          + "  ← from: " + (.sources | join(", "))
      ' <<< "$dup_names_json"
      printf '\n'
      printf 'Each final name must be unique. Adjust --rename arguments\n'
      printf 'so the duplicates land on distinct names.\n'
    } >&2
    return 1
  fi

  # Reserved-name collisions — only when fwns is unset.
  if [[ -z "$fwns" ]]; then
    local reserved_lines reserved_json
    reserved_lines="$(_framework_reserved_names)"
    reserved_json="$(printf '%s\n' "$reserved_lines" | jq -R . | jq -cs 'map(select(. != ""))')"

    local conflicts_json
    conflicts_json="$(jq -c --argjson reserved "$reserved_json" '
      [ .tasks[] | select(.name as $n | $reserved | index($n)) | .name ]
      | unique
    ' <<< "$doc")"

    local conflict_count
    conflict_count="$(jq -r 'length' <<< "$conflicts_json")"
    if [[ "$conflict_count" -gt 0 ]]; then
      {
        printf 'error: %s task(s) collide with framework commands:\n' "$conflict_count"
        jq -r --arg base "$basename" '
          .[]
          | "  " + . + "   → collides with `" + $base + " " + . + "`"
        ' <<< "$conflicts_json"
        printf '\n'
        printf 'Resolutions:\n'
        local rename_args=""
        local n
        while IFS= read -r n; do
          [[ -z "$n" ]] && continue
          rename_args+=" --rename ${n}=${n}-cmd"
        done < <(jq -r '.[]' <<< "$conflicts_json")
        printf '  %s        surgical renames\n' "$rename_args"
        printf '  --prefix <STR>                                  bulk prefix (you choose the string)\n'
        # shellcheck disable=SC2016  # backticks here are literal output, not command substitution
        printf '  --framework-namespace=clift                     move built-ins to `%s clift:*`\n' "$basename"
        printf '\n'
        printf 'Or rename the tasks in your Taskfile and re-run.\n'
      } >&2
      return 1
    fi
  fi

  return 0
}

# _splice_user_includes <root-taskfile> <tops-list...>
# Replaces the user-includes sentinel line with one include row per top-
# level command (deduped, in input order). Temp-file-and-move per project
# convention — never sed -i.
_splice_user_includes() {
  local root_taskfile="$1"
  shift
  local tmp
  tmp="$(mktemp "${root_taskfile}.XXXXXX")"

  # Build the replacement block once — empty when no user commands (rare,
  # but `init --from` on a Taskfile with only internals would land here).
  local block=""
  local top
  for top in "$@"; do
    [[ -z "$top" ]] && continue
    block+="  ${top}: { taskfile: ./cmds/${top} }"$'\n'
  done

  local sentinel="${_CLIFT_ROOT_USER_INCLUDES_SENTINEL}"
  local line found=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "$sentinel" ]]; then
      found=1
      if [[ -n "$block" ]]; then
        printf '%s' "$block"
      fi
      continue
    fi
    printf '%s\n' "$line"
  done < "$root_taskfile" > "$tmp"

  if [[ "$found" -eq 0 ]]; then
    rm -f "$tmp"
    log_error "user-includes sentinel not found in ${root_taskfile}"
    return 1
  fi

  mv "$tmp" "$root_taskfile"
}

# ----------------------------- main ------------------------------------

main() {
  local dest=""
  local source_path=""
  local prefix=""
  local fwns=""
  local -a renames=()

  # Argument parsing — the destination is the first non-flag positional.
  # We accept `--rename` repeatedly and verify each value contains `=`.
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --from)
        if [[ $# -lt 2 ]]; then
          log_error "--from requires a value"
          _usage
          exit 1
        fi
        source_path="$2"
        shift 2
        ;;
      --from=*)
        source_path="${1#--from=}"
        shift
        ;;
      --prefix)
        if [[ $# -lt 2 ]]; then
          log_error "--prefix requires a value"
          _usage
          exit 1
        fi
        prefix="$2"
        shift 2
        ;;
      --prefix=*)
        prefix="${1#--prefix=}"
        shift
        ;;
      --rename)
        if [[ $# -lt 2 ]]; then
          log_error "--rename requires a value"
          _usage
          exit 1
        fi
        renames+=("$2")
        shift 2
        ;;
      --rename=*)
        renames+=("${1#--rename=}")
        shift
        ;;
      --framework-namespace)
        if [[ $# -lt 2 ]]; then
          log_error "--framework-namespace requires a value"
          _usage
          exit 1
        fi
        fwns="$2"
        shift 2
        ;;
      --framework-namespace=*)
        fwns="${1#--framework-namespace=}"
        shift
        ;;
      --yes|-y)
        # Reserved for parity with future interactive flows. The current
        # orchestrator never prompts, so the flag is silently accepted.
        shift
        ;;
      -h|--help)
        _usage
        exit 0
        ;;
      --)
        shift
        if [[ -z "$dest" && $# -gt 0 ]]; then
          dest="$1"
          shift
        fi
        ;;
      -*)
        log_error "unknown flag: $1"
        _usage
        exit 1
        ;;
      *)
        if [[ -z "$dest" ]]; then
          dest="$1"
          shift
        else
          log_error "unexpected positional: $1"
          _usage
          exit 1
        fi
        ;;
    esac
  done

  if [[ -z "$dest" ]]; then
    log_error "missing <dir> argument"
    _usage
    exit 1
  fi
  if [[ -z "$source_path" ]]; then
    log_error "missing --from PATH"
    _usage
    exit 1
  fi

  # Validate rename pairs early — bad input shouldn't reach the writers.
  local renames_json='[]'
  if [[ ${#renames[@]} -gt 0 ]]; then
    local r
    for r in "${renames[@]}"; do
      if [[ "$r" != *=* ]]; then
        log_error "--rename expects SRC=DST, got: ${r}"
        exit 1
      fi
      local src="${r%%=*}"
      local dst="${r#*=}"
      if [[ -z "$src" || -z "$dst" ]]; then
        log_error "--rename SRC and DST must be non-empty: ${r}"
        exit 1
      fi
    done
    # Build a JSON array of {src,dst} so the jq overlay can iterate
    # without re-tokenizing in the shell.
    renames_json="$(printf '%s\n' "${renames[@]}" | jq -R 'split("=") | {src: .[0], dst: .[1]}' | jq -cs '.')"
  fi

  # 2. Resolve source path. `-` → stdin → tmp file (cleaned up by trap).
  local source_abs
  source_abs="$(_resolve_source "$source_path")"

  # 3. Read the source Taskfile via tier 1A.
  local source_doc
  if ! source_doc="$(read_source "$source_abs")"; then
    exit 1
  fi

  # 4. Apply prefix + rename overlays to the imported `name` field.
  local rewritten_doc
  rewritten_doc="$(_apply_renames "$source_doc" "$prefix" "$renames_json")"

  # 4b. Drop wildcard tasks shadowed by a plain task of the same name.
  # Mirrors go-task's literal-takes-precedence rule: when the source
  # declares both `deploy` and `deploy:*`, only the plain `deploy` is
  # importable (clift's command tree has one slot per name). A `note:`
  # line on stderr tells the user; --rename can recover the wildcard.
  rewritten_doc="$(_drop_wildcards_shadowed_by_plain "$rewritten_doc")"

  # Resolve destination to absolute (basename used in error messages and
  # by root_writer for .env / wrapper rendering). We do not mkdir until
  # collision detection has cleared so an aborted run leaves no trace.
  local dest_basename
  dest_basename="$(basename "$dest")"

  # 5. Collision detection — atomic abort point. No files written above
  # this line, so a nonzero return leaves the filesystem untouched.
  if ! _detect_collisions "$rewritten_doc" "$fwns" "$dest_basename"; then
    exit 1
  fi

  # Past this point, side effects begin. mkdir the dest now and resolve
  # to an absolute path the writers can stuff into generated artefacts.
  mkdir -p "$dest"
  local dest_abs
  dest_abs="$(cd "$dest" && pwd)"

  # 6. Root skeleton: .clift.yaml, .env, root Taskfile.yaml, Taskfile.user.yaml,
  # bin/<name>. The root Taskfile contains the user-includes sentinel.
  if [[ -n "$fwns" ]]; then
    write_cli_skeleton "$dest_basename" "$dest_abs" "$source_abs" "$fwns"
  else
    write_cli_skeleton "$dest_basename" "$dest_abs" "$source_abs"
  fi

  # 7. Per-task wrappers + Taskfiles. Group by top-level segment so each
  # `db:migrate`-style namespace shares one cmds/db/Taskfile.yaml with
  # ONE block per task (default for the bare/`:default`, named blocks
  # for sub-segments). Each task still gets its own .sh script.
  #
  # The router resolves `<top>:<sub>` to `cmds/<top>/<top>.<sub>.sh`
  # directly (with a fallback to `<top>.sh`), so each task lands at its
  # natural filename — no dispatcher shim, no bare-top relocation.
  #
  # We track unique tops in input order so step 9's include-splice keeps
  # the user's task ordering.
  local task_count
  task_count="$(jq -r '.tasks | length' <<< "$rewritten_doc")"

  local -a tops_seen=()
  declare -A tops_set=()

  # First pass: emit per-task wrappers and record unique-top order.
  local i
  for (( i=0; i<task_count; i++ )); do
    local entry name top
    entry="$(jq -c ".tasks[$i]" <<< "$rewritten_doc")"
    name="$(jq -r '.name' <<< "$entry")"
    top="${name%%:*}"

    if [[ -z "${tops_set[$top]:-}" ]]; then
      tops_set[$top]=1
      tops_seen+=("$top")
    fi

    local cmd_dir="$dest_abs/cmds/$top"
    mkdir -p "$cmd_dir"
    write_wrapper_script "$entry" "$cmd_dir"
  done

  # Second pass: one cmds/<top>/Taskfile.yaml per top, populated with
  # every task under that top. The writer keys each block as `default`
  # (bare top / `<top>:default`) or as the trailing sub-segment.
  local top
  for top in "${tops_seen[@]}"; do
    local cmd_dir="$dest_abs/cmds/$top"
    local group_json
    group_json="$(jq -c --arg top "$top" '
      [ .tasks[]
        | select((.name == $top) or (.name | startswith($top + ":")))
      ]
    ' <<< "$rewritten_doc")"
    write_cmd_taskfile "$group_json" "$cmd_dir"
  done

  # 9. Splice user-includes into the root Taskfile's sentinel slot.
  _splice_user_includes "$dest_abs/Taskfile.yaml" "${tops_seen[@]}"

  # 10. Success summary — list each imported command with its desc, then
  # the canonical "try it" block. Output goes to stdout because callers
  # may want to capture / pipe it; log_success only echoes status.
  echo
  log_success "Created ${dest_abs}/ with ${task_count} command(s):"
  echo
  jq -r '
    .tasks
    | map(
        "  " + (.name | (. + (" " * (12 - length))) )
        + (if (.desc // "") == "" then "(passthrough)" else .desc end)
      )
    | .[]
  ' <<< "$rewritten_doc"
  echo
  echo "Try it:"
  echo "  cd ${dest_abs}"
  echo "  ./bin/${dest_basename} --help"
}

# Direct invocation only — sourcing this file is unsupported.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
