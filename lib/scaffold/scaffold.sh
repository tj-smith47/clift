#!/usr/bin/env bash
# Scaffolds a new command into a bootstrapped CLI.
# Usage: scaffold.sh <NAME> <DESC> <CLI_DIR> <FRAMEWORK_DIR>

set -euo pipefail

CMD_NAME="${1:-}"
CMD_DESC="${2:-}"
CLI_DIR="${3:-}"
FRAMEWORK_DIR="${4:-}"

if [[ -z "$CMD_NAME" || -z "$CMD_DESC" || -z "$CLI_DIR" || -z "$FRAMEWORK_DIR" ]]; then
  echo "error: scaffold.sh requires NAME, DESC, CLI_DIR, FRAMEWORK_DIR" >&2
  exit 1
fi

source "${FRAMEWORK_DIR}/lib/log/log.sh"

# Validate command name: lowercase, starts with letter, colons for subcommands
NAME_RE='^[a-z][a-z0-9-]*(:[a-z][a-z0-9-]*)*$'
if [[ ! "$CMD_NAME" =~ $NAME_RE ]]; then
  log_error "Invalid: command names must match ${NAME_RE} (lowercase, start with letter, colons for sub)"
  exit 1
fi

# Determine if this is a top-level command or subcommand
# "greet" -> top-level, "greet:loud" -> subcommand of greet
TOP_CMD="${CMD_NAME%%:*}"
SUB_CMD="${CMD_NAME#*:}"
IS_SUBCOMMAND=false
if [[ "$TOP_CMD" != "$CMD_NAME" ]]; then
  IS_SUBCOMMAND=true
fi

CMD_DIR="${CLI_DIR}/cmds/${TOP_CMD}"
TASKFILE_PATH="${CMD_DIR}/Taskfile.yaml"

if [[ "$IS_SUBCOMMAND" == "true" ]]; then
  # Subcommand: append task to existing Taskfile, create separate script
  if [[ ! -f "$TASKFILE_PATH" ]]; then
    log_error "Top-level command '${TOP_CMD}' doesn't exist. Create it first: new:cmd NAME=${TOP_CMD}"
    exit 1
  fi

  # One-script-per-task: cmds/<cmd>/<cmd>.<sub>.sh
  SCRIPT_PATH="${CMD_DIR}/${TOP_CMD}.${SUB_CMD}.sh"

  # Render the subcommand script from template
  sed \
    -e "s|%%CMD_NAME%%|${CMD_NAME}|g" \
    "${FRAMEWORK_DIR}/templates/command/command.sh.tmpl" > "$SCRIPT_PATH"
  chmod +x "$SCRIPT_PATH"

  # Append the subcommand task to the existing Taskfile
  cat >> "$TASKFILE_PATH" <<YAML

  ${SUB_CMD}:
    desc: "${CMD_DESC}"
    summary: |
      ${CMD_DESC}

      Examples:
        {{.CLI_NAME}} ${CMD_NAME} [flags]
    vars:
      FLAGS: []
    cmd: "CLI_ARGS='{{.CLI_ARGS}}' '{{.FRAMEWORK_DIR}}/lib/router/router.sh' '{{.TASK}}'"
YAML

  log_success "Added subcommand '${SUB_CMD}' to ${TOP_CMD}"

else
  # Top-level command: create directory, Taskfile, and script

  if [[ -d "$CMD_DIR" ]]; then
    log_error "Command '${CMD_NAME}' already exists at ${CMD_DIR}"
    exit 1
  fi

  mkdir -p "$CMD_DIR"

  SCRIPT_PATH="${CMD_DIR}/${TOP_CMD}.sh"

  # Render Taskfile from template
  sed \
    -e "s|%%CMD_NAME%%|${CMD_NAME}|g" \
    -e "s|%%CMD_DESC%%|${CMD_DESC}|g" \
    -e "s|%%CLI_NAME%%|${CLI_NAME:-mycli}|g" \
    "${FRAMEWORK_DIR}/templates/command/Taskfile.yaml.tmpl" > "$TASKFILE_PATH"

  # Render script from template
  sed \
    -e "s|%%CMD_NAME%%|${CMD_NAME}|g" \
    "${FRAMEWORK_DIR}/templates/command/command.sh.tmpl" > "$SCRIPT_PATH"
  chmod +x "$SCRIPT_PATH"

  # Append include to root Taskfile
  ROOT_TASKFILE="${CLI_DIR}/Taskfile.yaml"
  if ! grep -q "^  ${CMD_NAME}:" "$ROOT_TASKFILE" 2>/dev/null; then
    # Find the "# User commands" comment and append after it
    if grep -q "# User commands" "$ROOT_TASKFILE"; then
      sed -i "/# User commands.*/a\\
  ${CMD_NAME}:\\
    taskfile: ./cmds/${CMD_NAME}" "$ROOT_TASKFILE"
    else
      # Fallback: append to includes section before tasks section
      sed -i "/^tasks:/i\\
  ${CMD_NAME}:\\
    taskfile: ./cmds/${CMD_NAME}" "$ROOT_TASKFILE"
    fi
  fi

  log_success "Created command '${CMD_NAME}' at ${CMD_DIR}"
  log_info "Edit ${SCRIPT_PATH} to add your logic"
fi

# Validate the command Taskfile
bash "${FRAMEWORK_DIR}/lib/flags/validate.sh" "$TASKFILE_PATH" || {
  log_error "Generated Taskfile failed validation"
  exit 1
}

# Refresh the precompilation cache
FRAMEWORK_DIR="${FRAMEWORK_DIR}" bash "${FRAMEWORK_DIR}/lib/flags/compile.sh" "$CLI_DIR" || {
  log_error "Cache rebuild failed"
  exit 1
}
