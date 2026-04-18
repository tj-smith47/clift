#!/usr/bin/env bash
# Import go-task tasks from an existing Taskfile as clift commands.
# Generates thin wrapper scripts that `exec task --taskfile <src>` — the
# wrapped task keeps its full go-task semantics (deps, sources, status).
#
# Usage: import.sh <CLI_DIR> <FRAMEWORK_DIR> [--from PATH] [--dry-run]

set -euo pipefail

CLI_DIR="${1:-}"
FRAMEWORK_DIR="${2:-}"
if [[ -z "$CLI_DIR" || -z "$FRAMEWORK_DIR" ]]; then
  echo "error: import.sh requires CLI_DIR and FRAMEWORK_DIR" >&2
  exit 1
fi
shift 2

# In standard mode the Taskfile's `{{.CLI_ARGS}}` is empty — the wrapper
# sets CLIFT_ARG_COUNT and CLIFT_ARG_1..N instead. Pull any user flags from
# there if present; task mode already has them in $@.
if [[ -n "${CLIFT_ARG_COUNT:-}" ]]; then
  _import_args=()
  for (( _i=1; _i<=CLIFT_ARG_COUNT; _i++ )); do
    _v="CLIFT_ARG_$_i"
    _import_args+=("${!_v}")
  done
  set -- "${_import_args[@]+"${_import_args[@]}"}"
fi

FROM=""
DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --from)
      [[ $# -lt 2 ]] && { echo "error: --from requires a path" >&2; exit 1; }
      FROM="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "error: unknown flag: $1" >&2; exit 1 ;;
  esac
done

source "${FRAMEWORK_DIR}/lib/log/log.sh"
# shellcheck source=/dev/null
source "${FRAMEWORK_DIR}/lib/flags/name_rules.sh"

# Preconditions
if [[ ! -f "${CLI_DIR}/.clift.yaml" ]]; then
  die "Not a clift CLI: ${CLI_DIR}/.clift.yaml not found. Run 'clift init' first."
fi

# Source Taskfile resolution: --from wins; else Taskfile.user.yaml; else root.
if [[ -z "$FROM" ]]; then
  if [[ -f "${CLI_DIR}/Taskfile.user.yaml" ]]; then
    FROM="${CLI_DIR}/Taskfile.user.yaml"
  else
    FROM="${CLI_DIR}/Taskfile.yaml"
  fi
fi

if [[ ! -f "$FROM" ]]; then
  die "Source Taskfile not found: ${FROM}"
fi

# Resolve to absolute path so generated wrappers survive cwd changes.
FROM_ABS="$(cd "$(dirname "$FROM")" && pwd)/$(basename "$FROM")"

# Refuse to import from the clift-managed root Taskfile when it contains
# framework includes — wrapping those tasks would recurse through the router.
if [[ "$FROM_ABS" == "${CLI_DIR}/Taskfile.yaml" ]] && grep -q "FRAMEWORK_DIR.*lib/" "$FROM_ABS" 2>/dev/null; then
  die "Source is the clift-managed root Taskfile. Move your tasks to Taskfile.user.yaml first, or pass --from PATH."
fi

# Get tasks from source. --nested gives us root + namespace structure.
tasks_json="$(task --list-all --json --nested --taskfile "$FROM_ABS" 2>/dev/null || true)"
if [[ -z "$tasks_json" ]]; then
  die "Failed to parse source Taskfile: ${FROM}"
fi

FRAMEWORK_RESERVED=(config update completion new version help import)

# Collect all task names from root and namespaces (excluding :default synthetic)
mapfile -t all_names < <(echo "$tasks_json" | jq -r '
  [
    (.tasks // [])[].name,
    ((.namespaces // {}) | to_entries[] | .value.tasks[]?.name)
  ]
  | map(select(. != null and . != ""))
  | unique
  | .[]
')

importable=()
importable_descs=()
skipped_reserved=()
skipped_invalid=()
skipped_existing=()
skipped_wildcard=()

_desc_for() {
  local n="$1"
  echo "$tasks_json" | jq -r --arg n "$n" '
    [.. | .tasks? // empty | .[] | select(.name == $n) | .desc // ""] | first // ""
  '
}

for name in "${all_names[@]}"; do
  [[ -z "$name" ]] && continue
  [[ "$name" == "default" ]] && continue
  [[ "$name" == _* ]] && { skipped_invalid+=("$name"); continue; }
  # Strip trailing :default (namespace synthetic) so we import the top name.
  display="${name%:default}"
  [[ "$display" == _* ]] && { skipped_invalid+=("$name"); continue; }

  if [[ "$display" == *"*"* ]]; then
    skipped_wildcard+=("$display")
    continue
  fi

  if [[ ! "$display" =~ $CLIFT_CMD_NAME_RE ]]; then
    skipped_invalid+=("$display")
    continue
  fi

  top="${display%%:*}"
  is_reserved=false
  for r in "${FRAMEWORK_RESERVED[@]}"; do
    [[ "$top" == "$r" ]] && is_reserved=true && break
  done
  if $is_reserved; then
    skipped_reserved+=("$display")
    continue
  fi

  if [[ -d "${CLI_DIR}/cmds/${top}" ]]; then
    skipped_existing+=("$display")
    continue
  fi

  # Deduplicate (namespaces and plain tasks can overlap)
  already=false
  for existing in "${importable[@]:-}"; do
    [[ "$existing" == "$display" ]] && already=true && break
  done
  $already && continue

  importable+=("$display")
  importable_descs+=("$(_desc_for "$name")")
done

# --- Print plan ---
src_basename="$(basename "$FROM")"
if [[ ${#importable[@]} -eq 0 ]]; then
  log_info "No importable tasks found in ${src_basename}"
else
  log_info "Found ${#importable[@]} importable task(s) in ${src_basename}:"
  for i in "${!importable[@]}"; do
    printf '  %-20s %s\n' "${importable[$i]}" "${importable_descs[$i]}"
  done
fi

_print_skipped() {
  local label="$1"; shift
  local -a arr=("$@")
  [[ ${#arr[@]} -eq 0 ]] && return 0
  for n in "${arr[@]}"; do
    printf '  %-20s %s\n' "$n" "$label"
  done
}

if [[ ${#skipped_reserved[@]} -gt 0 ]] || [[ ${#skipped_invalid[@]} -gt 0 ]] \
   || [[ ${#skipped_wildcard[@]} -gt 0 ]] || [[ ${#skipped_existing[@]} -gt 0 ]]; then
  echo ""
  echo "Skipped:"
  _print_skipped "(collides with clift framework command)" "${skipped_reserved[@]:-}"
  _print_skipped "(invalid name for clift)"                "${skipped_invalid[@]:-}"
  _print_skipped "(wildcard not supported)"                "${skipped_wildcard[@]:-}"
  _print_skipped "(already exists in cmds/)"               "${skipped_existing[@]:-}"
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo ""
  log_info "Dry run — no changes made."
  exit 0
fi

if [[ ${#importable[@]} -eq 0 ]]; then
  exit 0
fi

# --- Generate files ---
ROOT_TASKFILE="${CLI_DIR}/Taskfile.yaml"
tops_added=()

_already_added() {
  local t="$1"
  for x in "${tops_added[@]:-}"; do
    [[ "$x" == "$t" ]] && return 0
  done
  return 1
}

for i in "${!importable[@]}"; do
  name="${importable[$i]}"
  desc="${importable_descs[$i]}"
  [[ -z "$desc" ]] && desc="Imported from ${src_basename}"

  top="${name%%:*}"
  cmd_dir="${CLI_DIR}/cmds/${top}"
  mkdir -p "$cmd_dir"

  script_name="${name//:/.}"
  script_path="${cmd_dir}/${script_name}.sh"

  # Wrapper: exec task against the original source Taskfile (absolute path
  # recorded at import time — survives cwd changes, insulated from the
  # clift-managed root). The router invokes us with empty $@ but parks any
  # positional args in CLIFT_POS_*, so rebuild argv before forwarding.
  cat > "$script_path" <<SCRIPT
#!/usr/bin/env bash
# Auto-generated by clift import — wraps go-task: ${name}
# Regenerate via: clift import --from ${src_basename}
set -euo pipefail
_fwd=()
for (( _i=1; _i<=\${CLIFT_POS_COUNT:-0}; _i++ )); do
  _v="CLIFT_POS_\$_i"
  _fwd+=("\${!_v}")
done
exec task --taskfile '${FROM_ABS}' '${name}' -- "\${_fwd[@]+\"\${_fwd[@]}\"}"
SCRIPT
  chmod +x "$script_path"

  # Generate the cmds/<top>/Taskfile.yaml (once per top-level name). For
  # subcommands, append a task block to the existing Taskfile.
  cmd_taskfile="${cmd_dir}/Taskfile.yaml"
  if [[ "$top" == "$name" ]]; then
    cat > "$cmd_taskfile" <<YAML
version: '3'

vars:
  FLAGS: []

tasks:
  default:
    desc: "${desc}"
    vars:
      FLAGS: []
    cmd: "CLI_ARGS='{{.CLI_ARGS}}' '{{.FRAMEWORK_DIR}}/lib/router/router.sh' '{{.TASK}}'"
YAML
  else
    sub="${name#*:}"
    # If no top-level Taskfile yet (importing subcommand without parent),
    # synthesize a group-header Taskfile first.
    if [[ ! -f "$cmd_taskfile" ]]; then
      cat > "$cmd_taskfile" <<YAML
version: '3'

vars:
  FLAGS: []

tasks:
YAML
    fi
    cat >> "$cmd_taskfile" <<YAML

  ${sub}:
    desc: "${desc}"
    vars:
      FLAGS: []
    cmd: "CLI_ARGS='{{.CLI_ARGS}}' '{{.FRAMEWORK_DIR}}/lib/router/router.sh' '{{.TASK}}'"
YAML
  fi

  # Inject root include (once per top, idempotent).
  if ! _already_added "$top" \
     && ! grep -qE "^[[:space:]]+${top}:[[:space:]]*$" "$ROOT_TASKFILE"; then
    _tmp="$(mktemp)"
    if grep -q "# User commands" "$ROOT_TASKFILE"; then
      awk -v name="$top" '
        /# User commands/ { print; print "  " name ":"; print "    taskfile: ./cmds/" name; next }
        { print }
      ' "$ROOT_TASKFILE" > "$_tmp"
    else
      awk -v name="$top" '
        /^tasks:/ { print "  " name ":"; print "    taskfile: ./cmds/" name }
        { print }
      ' "$ROOT_TASKFILE" > "$_tmp"
    fi
    mv "$_tmp" "$ROOT_TASKFILE"
    tops_added+=("$top")
  fi
done

# Rebuild the cache so the new commands are routable immediately.
bash "${FRAMEWORK_DIR}/lib/flags/compile.sh" "$CLI_DIR" >/dev/null 2>&1 || true

log_success "Imported ${#importable[@]} command(s)"
if [[ ${#tops_added[@]} -gt 0 ]]; then
  log_info "Added to root Taskfile: ${tops_added[*]}"
fi
