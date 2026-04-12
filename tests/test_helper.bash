# Common test helper
#
# FILESYSTEM ISOLATION: every test must run with HOME redirected into
# TEST_DIR so nothing can write to the developer's real shell rc files,
# config dirs, or caches. Past test runs without this guard polluted the
# developer's real ~/.bashrc with stray alias entries pointing at /tmp dirs
# that no longer exist. Never remove the HOME redirect below.

common_setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR"
  export FRAMEWORK_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export CLI_DIR="$TEST_DIR"
  export CLI_NAME="testcli"
  export CLI_VERSION="1.0.0"
  export LOG_THEME="minimal"
  export PROMPT="false"
  export SHELL=/bin/bash
  # Second line of defense for setup.sh rc-file writes (see setup.sh line 130)
  export CLIFT_RC_FILE="$HOME/.bashrc"
  touch "$HOME/.bashrc"
  touch "$HOME/.zshrc"
}

common_teardown() {
  rm -rf "$TEST_DIR"
}

setup() {
  common_setup
}

teardown() {
  common_teardown
}

# Create a minimal CLI fixture at $CLI_DIR with:
#   - Root Taskfile with dotenv, FLAGS, includes
#   - .env with standard vars
#   - Optional: command dirs under cmds/
#
# Usage: create_test_cli [cmd_name] [cmd_flags_yaml]
# Examples:
#   create_test_cli                          # bare CLI, no commands
#   create_test_cli "greet"                  # command with empty FLAGS
#   create_test_cli "greet" "- {name: name, short: n, type: string, default: world}"
create_test_cli() {
  local cmd_name="${1:-}"
  local cmd_flags="${2:-}"

  cat > "$CLI_DIR/Taskfile.yaml" <<'YAML'
version: '3'
dotenv: ['.env']
vars:
  FLAGS:
    - {name: help, short: h, type: bool, desc: "Show help"}
    - {name: verbose, short: v, type: bool, desc: "Verbose"}
    - {name: quiet, short: q, type: bool, desc: "Quiet"}
    - {name: no-color, type: bool, desc: "No color"}
    - {name: version, type: bool, desc: "Version"}
includes:
YAML

  cat > "$CLI_DIR/.env" <<ENV
CLI_NAME=$CLI_NAME
CLI_VERSION=$CLI_VERSION
CLI_DIR=$CLI_DIR
FRAMEWORK_DIR=$FRAMEWORK_DIR
CLIFT_MODE=standard
LOG_THEME=minimal
ENV

  if [[ -n "$cmd_name" ]]; then
    # Add include to root Taskfile
    echo "  ${cmd_name}:" >> "$CLI_DIR/Taskfile.yaml"
    echo "    taskfile: ./cmds/${cmd_name}" >> "$CLI_DIR/Taskfile.yaml"

    # Add default task
    cat >> "$CLI_DIR/Taskfile.yaml" <<'YAML'
tasks:
  default:
    cmd: echo root
YAML

    mkdir -p "$CLI_DIR/cmds/${cmd_name}"

    local flags_line="FLAGS: []"
    local task_flags_line="FLAGS: []"
    if [[ -n "$cmd_flags" ]]; then
      flags_line="FLAGS:"
      task_flags_line="FLAGS:"
    fi

    cat > "$CLI_DIR/cmds/${cmd_name}/Taskfile.yaml" <<YAML
version: '3'
vars:
  ${flags_line}
YAML

    if [[ -n "$cmd_flags" ]]; then
      echo "    ${cmd_flags}" >> "$CLI_DIR/cmds/${cmd_name}/Taskfile.yaml"
    fi

    cat >> "$CLI_DIR/cmds/${cmd_name}/Taskfile.yaml" <<YAML
tasks:
  default:
    vars:
      ${task_flags_line}
    cmd: "CLI_ARGS='{{.CLI_ARGS}}' '{{.FRAMEWORK_DIR}}/lib/router/router.sh' '{{.TASK}}'"
YAML

    if [[ -n "$cmd_flags" ]]; then
      echo "      ${cmd_flags}" >> "$CLI_DIR/cmds/${cmd_name}/Taskfile.yaml"
    fi
  else
    cat >> "$CLI_DIR/Taskfile.yaml" <<'YAML'
tasks:
  default:
    cmd: echo root
YAML
  fi
}

# Render wrapper.sh.tmpl into $CLI_DIR/bin/$CLI_NAME.
# Requires CLI_DIR, CLI_NAME, CLI_VERSION, FRAMEWORK_DIR to be set.
build_test_wrapper() {
  mkdir -p "$CLI_DIR/bin"
  sed \
    -e "s|%%FRAMEWORK_DIR%%|$FRAMEWORK_DIR|g" \
    -e "s|%%CLI_DIR%%|$CLI_DIR|g" \
    -e "s|%%CLI_NAME%%|$CLI_NAME|g" \
    -e "s|%%CLI_VERSION%%|$CLI_VERSION|g" \
    "$FRAMEWORK_DIR/lib/wrapper/wrapper.sh.tmpl" > "$CLI_DIR/bin/$CLI_NAME"
  chmod +x "$CLI_DIR/bin/$CLI_NAME"
}
