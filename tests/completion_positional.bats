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
