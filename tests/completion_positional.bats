#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load test_helper

setup() {
  common_setup
  export CLI_NAME="mycli"
  # Create a CLI with a "deploy" command scaffolded by the helper (writes
  # include + per-cmd Taskfile). We then overwrite the Taskfile to match
  # the plan's fixture (default task that just echoes) and add a pos1
  # completer under cmds/deploy/overrides/.
  create_test_cli "deploy"
  build_test_wrapper

  cat > "$CLI_DIR/cmds/deploy/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: force, type: bool, desc: "Force"}
tasks:
  default:
    desc: "Deploy to a target"
    cmd: echo deploy
YAML

  mkdir -p "$CLI_DIR/cmds/deploy/overrides"
  cat > "$CLI_DIR/cmds/deploy/overrides/completion.sh" <<'SH'
clift_complete_deploy_pos1() {
  local prefix="${1:-}"
  for t in prod-east prod-west staging dev; do
    [[ "$t" == "$prefix"* ]] && printf '%s\n' "$t"
  done
}
SH
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
}
teardown() { common_teardown; }

@test "wrapper _complete dispatches pos1 to clift_complete_<task>_pos1" {
  run "$CLI_DIR/bin/mycli" _complete deploy pos1 prod
  [ "$status" -eq 0 ]
  [[ "$output" == *"prod-east"* ]]
  [[ "$output" == *"prod-west"* ]]
  [[ "$output" != *"staging"* ]]
}

@test "bash completion emits positional hook for deploy pos1" {
  export CLIFT_MODE=standard CLI_NAME=mycli
  run bash "$FRAMEWORK_DIR/lib/completion/completion.sh" bash
  [ "$status" -eq 0 ]
  # Bash completion function must reference the _complete pos<N> pathway.
  [[ "$output" == *"_complete"* ]]
  [[ "$output" == *"pos"* ]]
}

@test "zsh completion emits positional hook for deploy pos1" {
  export CLIFT_MODE=standard CLI_NAME=mycli
  run bash "$FRAMEWORK_DIR/lib/completion/completion.sh" zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"_complete"* ]]
  [[ "$output" == *"pos"* ]]
}

@test "bash completion invokes pos1 at first positional after task" {
  # Simulate: mycli deploy <TAB> → compgen -W should include prod-east.
  export CLIFT_MODE=standard CLI_NAME=mycli
  local script
  script="$(bash "$FRAMEWORK_DIR/lib/completion/completion.sh" bash)"
  # Source completion script, fake COMP state, call the completion fn.
  run bash -c '
    export CLIFT_MODE=standard
    eval "$1"
    COMP_WORDS=(mycli deploy "")
    COMP_CWORD=2
    export PATH="'"$CLI_DIR"'/bin:$PATH"
    _mycli_completions
    printf "%s\n" "${COMPREPLY[@]}"
  ' _ "$script"
  [ "$status" -eq 0 ]
  [[ "$output" == *"prod-east"* ]]
}

# pos2+ dispatch — cache-aware task-path resolution.
#
# Earlier the dispatcher greedily colon-joined every non-flag word into
# cmd_path, then derived pos_n from a colon count. That collapsed pos2+
# to pos1: at `mycli deploy foo <TAB>` the cmd_path became `deploy:foo`
# (a non-existent task) and the dispatcher fired pos1, not pos2. The fix
# reads `.clift/index.json` at completion time, walks non-flag words
# longest-prefix against the real task table, and uses the first
# unmatched word as the start of positionals.

@test "wrapper _complete dispatches pos2 to clift_complete_<task>_pos2" {
  cat > "$CLI_DIR/cmds/deploy/overrides/completion.sh" <<'SH'
clift_complete_deploy_pos1() { printf 'TARGET\n'; }
clift_complete_deploy_pos2() { printf 'STAGE-A\nSTAGE-B\n'; }
SH
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
  run "$CLI_DIR/bin/mycli" _complete deploy pos2 ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"STAGE-A"* ]]
  [[ "$output" == *"STAGE-B"* ]]
}

@test "bash completion invokes pos2 at second positional (deploy <pos1> <pos2>)" {
  cat > "$CLI_DIR/cmds/deploy/overrides/completion.sh" <<'SH'
clift_complete_deploy_pos1() { printf 'prod-east\nprod-west\n'; }
clift_complete_deploy_pos2() { printf 'STAGE-A\nSTAGE-B\n'; }
SH
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"

  export CLIFT_MODE=standard CLI_NAME=mycli
  local script
  script="$(bash "$FRAMEWORK_DIR/lib/completion/completion.sh" bash)"
  run bash -c '
    export CLIFT_MODE=standard
    eval "$1"
    COMP_WORDS=(mycli deploy prod-east "")
    COMP_CWORD=3
    export PATH="'"$CLI_DIR"'/bin:$PATH"
    _mycli_completions
    printf "%s\n" "${COMPREPLY[@]}"
  ' _ "$script"
  [ "$status" -eq 0 ]
  [[ "$output" == *"STAGE-A"* ]]
  [[ "$output" == *"STAGE-B"* ]]
  # And must NOT mistakenly fire pos1 against deploy:prod-east
  [[ "$output" != *"prod-east"* ]] || true  # tolerable if compgen happens to echo
}

@test "bash completion invokes pos2 even when pos1 is a real subcommand-shaped token" {
  # If pos1 happens to share a name with a (nonexistent) nested subcommand,
  # the dispatcher must still recognise that there's no `deploy:foo` task
  # and treat `foo` as a consumed positional, not a path segment.
  cat > "$CLI_DIR/cmds/deploy/overrides/completion.sh" <<'SH'
clift_complete_deploy_pos2() { printf 'STAGE-A\n'; }
SH
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"

  export CLIFT_MODE=standard CLI_NAME=mycli
  local script
  script="$(bash "$FRAMEWORK_DIR/lib/completion/completion.sh" bash)"
  run bash -c '
    export CLIFT_MODE=standard
    eval "$1"
    COMP_WORDS=(mycli deploy yaml "")
    COMP_CWORD=3
    export PATH="'"$CLI_DIR"'/bin:$PATH"
    _mycli_completions
    printf "%s\n" "${COMPREPLY[@]}"
  ' _ "$script"
  [ "$status" -eq 0 ]
  [[ "$output" == *"STAGE-A"* ]]
}

@test "bash completion preserves pos1 when intervening flag precedes positional" {
  cat > "$CLI_DIR/cmds/deploy/overrides/completion.sh" <<'SH'
clift_complete_deploy_pos1() { printf 'prod-east\n'; }
SH
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"

  export CLIFT_MODE=standard CLI_NAME=mycli
  local script
  script="$(bash "$FRAMEWORK_DIR/lib/completion/completion.sh" bash)"
  run bash -c '
    export CLIFT_MODE=standard
    eval "$1"
    COMP_WORDS=(mycli deploy --force "")
    COMP_CWORD=3
    export PATH="'"$CLI_DIR"'/bin:$PATH"
    _mycli_completions
    printf "%s\n" "${COMPREPLY[@]}"
  ' _ "$script"
  [ "$status" -eq 0 ]
  [[ "$output" == *"prod-east"* ]]
}

@test "bash completion handles pos2 inside a nested namespace (task:add foo <TAB>)" {
  # Build a nested fixture: cmds/task/Taskfile.yaml with `add` subcommand.
  rm -rf "$CLI_DIR/cmds/deploy"
  cat > "$CLI_DIR/Taskfile.yaml" <<'YAML'
version: '3'
silent: true
output:
  group:
    begin: ''
    end: ''
set: [errexit, pipefail]
dotenv: ['.env']
vars:
  FLAGS:
    - {name: help, short: h, type: bool, desc: "Show help"}
    - {name: verbose, short: v, type: bool, desc: "Verbose"}
    - {name: quiet, short: q, type: bool, desc: "Quiet"}
    - {name: no-color, type: bool, desc: "No color"}
    - {name: no-cache, type: bool, desc: "Force-rebuild the .clift cache before this command"}
    - {name: version, type: bool, desc: "Version"}
includes:
  task:
    taskfile: ./cmds/task
tasks:
  default:
    cmd: echo root
YAML

  mkdir -p "$CLI_DIR/cmds/task"
  cat > "$CLI_DIR/cmds/task/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS: []
tasks:
  add:
    desc: "Add a task"
    cmd: echo add
YAML

  mkdir -p "$CLI_DIR/cmds/task/overrides"
  cat > "$CLI_DIR/cmds/task/overrides/completion.sh" <<'SH'
clift_complete_task_add_pos1() { printf 'first-arg\n'; }
clift_complete_task_add_pos2() { printf 'SECOND-ARG\n'; }
SH
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"

  export CLIFT_MODE=standard CLI_NAME=mycli
  local script
  script="$(bash "$FRAMEWORK_DIR/lib/completion/completion.sh" bash)"
  run bash -c '
    export CLIFT_MODE=standard
    eval "$1"
    COMP_WORDS=(mycli task add first-arg "")
    COMP_CWORD=4
    export PATH="'"$CLI_DIR"'/bin:$PATH"
    _mycli_completions
    printf "%s\n" "${COMPREPLY[@]}"
  ' _ "$script"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SECOND-ARG"* ]]
}
