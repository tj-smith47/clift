#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load test_helper

setup() { common_setup; }
teardown() { common_teardown; }

# Task 5.5: dynamic completers, convention-only.
# Discovery rule: a function named `clift_complete_<task>_<flag>` in either
#   $CLI_DIR/.clift/overrides/completion.sh (CLI-global)
# or
#   $CLI_DIR/cmds/<cmd-seg>/overrides/completion.sh (per-command, cmd-seg =
#   first colon-separated segment of <task>)
# is the *declaration*. No FLAGS schema field, no registration call.
# Colons in task name → underscores, dashes in flag name → underscores.
#
# The wrapper exposes a hidden `_complete` subcommand:
#   <cli> _complete <task> <flag> [partial-word]
# which sources the override file(s), builds the function name, and invokes
# the matching `clift_complete_*` with [partial-word] as $1. Always exits 0
# so tab-completion is never visibly broken by a missing / failing completer.

@test "_complete invokes CLI-global completer from .clift/overrides/completion.sh" {
  create_test_cli "deploy"
  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/completion.sh" <<'SH'
clift_complete_deploy_region() {
  echo us-east-1
  echo us-west-2
  echo eu-west-1
}
SH
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" _complete deploy region
  [ "$status" -eq 0 ]
  [[ "$output" == *"us-east-1"* ]]
  [[ "$output" == *"us-west-2"* ]]
  [[ "$output" == *"eu-west-1"* ]]
}

@test "_complete invokes per-command completer from cmds/<cmd>/overrides/completion.sh" {
  create_test_cli "deploy"
  mkdir -p "$CLI_DIR/cmds/deploy/overrides"
  cat > "$CLI_DIR/cmds/deploy/overrides/completion.sh" <<'SH'
clift_complete_deploy_region() {
  echo local-region
}
SH
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" _complete deploy region
  [ "$status" -eq 0 ]
  [[ "$output" == *"local-region"* ]]
}

@test "_complete CLI-global wins when both global and per-command define the same completer" {
  create_test_cli "deploy"
  mkdir -p "$CLI_DIR/.clift/overrides" "$CLI_DIR/cmds/deploy/overrides"
  cat > "$CLI_DIR/.clift/overrides/completion.sh" <<'SH'
clift_complete_deploy_region() { echo GLOBAL; }
SH
  cat > "$CLI_DIR/cmds/deploy/overrides/completion.sh" <<'SH'
clift_complete_deploy_region() { echo LOCAL; }
SH
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" _complete deploy region
  [ "$status" -eq 0 ]
  [[ "$output" == *"GLOBAL"* ]]
  [[ "$output" != *"LOCAL"* ]]
}

@test "_complete passes the partial word as \$1 to the completer" {
  create_test_cli "deploy"
  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/completion.sh" <<'SH'
clift_complete_deploy_region() {
  for r in us-east-1 us-west-2 eu-west-1; do
    [[ "$r" == "${1:-}"* ]] && echo "$r"
  done
}
SH
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" _complete deploy region eu-
  [ "$status" -eq 0 ]
  [[ "$output" == *"eu-west-1"* ]]
  [[ "$output" != *"us-east-1"* ]]
}

@test "_complete exits 0 silently when no completer is defined" {
  create_test_cli "deploy"
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" _complete deploy region
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_complete exits 0 silently when override file exists but completer fn missing" {
  create_test_cli "deploy"
  mkdir -p "$CLI_DIR/.clift/overrides"
  echo "# no completer defined" > "$CLI_DIR/.clift/overrides/completion.sh"
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" _complete deploy region
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_complete flag name maps dashes to underscores" {
  create_test_cli "deploy"
  mkdir -p "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/.clift/overrides/completion.sh" <<'SH'
clift_complete_deploy_dry_run() { echo true; echo false; }
SH
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" _complete deploy dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"true"* ]]
  [[ "$output" == *"false"* ]]
}

@test "_complete task name maps colons to underscores" {
  create_test_cli "deploy"
  mkdir -p "$CLI_DIR/cmds/deploy/prod" "$CLI_DIR/.clift/overrides"
  cat > "$CLI_DIR/cmds/deploy/prod/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS: []
tasks:
  default:
    vars: {FLAGS: []}
    cmd: echo prod
YAML
  cat > "$CLI_DIR/.clift/overrides/completion.sh" <<'SH'
clift_complete_deploy_prod_region() { echo prod-east; }
SH
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" _complete deploy:prod region
  [ "$status" -eq 0 ]
  [[ "$output" == *"prod-east"* ]]
}

@test "_complete rejects unsafe task name (path traversal defense)" {
  create_test_cli "deploy"
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" _complete "../etc" region
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_complete rejects unsafe flag name (path traversal defense)" {
  create_test_cli "deploy"
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" _complete deploy "../etc"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_complete requires both task and flag arguments" {
  create_test_cli "deploy"
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" _complete
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  run "$CLI_DIR/bin/$CLI_NAME" _complete deploy
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_complete does not dispatch through the longest-prefix walk" {
  # _complete must short-circuit before task dispatch so invoking it on a
  # CLI with no matching user command is still a no-op, not a "did-you-mean"
  # error. Also proves the handler runs without a warmed cache.
  create_test_cli
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" _complete nosuch flag
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "generated bash completion script wires flag-value completion to _complete" {
  create_test_cli "deploy"
  build_test_wrapper
  CLIFT_MODE=standard run bash "$FRAMEWORK_DIR/lib/completion/completion.sh" bash
  [ "$status" -eq 0 ]
  # Generated script must invoke the hidden _complete subcommand.
  [[ "$output" == *"_complete"* ]]
}

@test "generated zsh completion script wires flag-value completion to _complete" {
  create_test_cli "deploy"
  build_test_wrapper
  CLIFT_MODE=standard run bash "$FRAMEWORK_DIR/lib/completion/completion.sh" zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"_complete"* ]]
}
