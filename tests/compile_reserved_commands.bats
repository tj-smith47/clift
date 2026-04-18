#!/usr/bin/env bats
# Branch-review I4: compile.sh must reject reserved top-level tokens used as
# user command names or first-token aliases.
#
# Reserved set:
#   watch     — wrapper rewrites `mycli watch <cmd>` to `--task:watch <cmd>`
#               unconditionally before the cache loads, so a user `watch`
#               command is silently shadowed.
#   _complete — hidden tab-completion dispatch. Already filtered by the
#               framework's `^_` rule, but the explicit reservation makes
#               the behavior intentional and the error message informative.
#
# Scope: only the BARE top-level token. A nested namespace task like
# `watch:foo` (whose canonical retains the colon) is allowed — the wrapper's
# `[[ "$1" == "watch" ]]` rewrite only fires for a single-token first-arg
# literally equal to `watch`.

bats_require_minimum_version 1.5.0
load test_helper

setup() { common_setup; }
teardown() { common_teardown; }

@test "compile rejects a top-level command literally named 'watch'" {
  # Create a CLI whose include namespace is `watch` AND whose included
  # taskfile defines a `default` task — the resulting `watch:default`
  # canonicalises to the bare `watch` after `:default` strip, which the
  # wrapper would dispatch as `mycli watch` if the rewrite weren't
  # consuming it first.
  create_test_cli
  mkdir -p "$CLI_DIR/cmds/watch"
  cat > "$CLI_DIR/cmds/watch/Taskfile.yaml" <<'YAML'
version: '3'
tasks:
  default:
    cmd: "echo WATCH_RAN"
YAML
  awk 'BEGIN{done=0} {print} /^includes:$/ && !done {print "  watch:"; print "    taskfile: ./cmds/watch"; done=1}' \
    "$CLI_DIR/Taskfile.yaml" > "$CLI_DIR/Taskfile.yaml.new"
  mv "$CLI_DIR/Taskfile.yaml.new" "$CLI_DIR/Taskfile.yaml"

  run bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"reserved top-level token"* ]]
  [[ "$output" == *"watch"* ]]
}

@test "compile rejects a root-level task literally named 'watch'" {
  # No include namespace — declare `watch` directly under `tasks:` in the
  # root Taskfile. tasks.json reports `name: "watch"` (no colon), the
  # canonical-name violation branch fires.
  create_test_cli
  cat >> "$CLI_DIR/Taskfile.yaml" <<'YAML'
  watch:
    cmd: "echo WATCH_RAN"
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"reserved top-level token"* ]]
  [[ "$output" == *"watch"* ]]
}

@test "compile rejects an alias resolving to bare 'watch' on another task" {
  # User declares `aliases: [watch]` on a deploy task. The user_aliases
  # derivation strips the `deploy:` namespace prefix and yields the bare
  # token `watch`, which is reserved.
  create_test_cli "deploy"
  cat > "$CLI_DIR/cmds/deploy/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS: []
tasks:
  default:
    aliases: [watch]
    vars:
      FLAGS: []
    cmd: "echo DEPLOY"
YAML
  run bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"reserved top-level token"* ]]
  [[ "$output" == *"alias 'watch'"* ]]
}

@test "compile permits a nested 'watch:foo' command (only the bare top-level token is reserved)" {
  # The canonical `watch:foo` keeps the colon — the wrapper's literal-token
  # rewrite never fires, no shadowing risk, no rejection.
  create_test_cli
  mkdir -p "$CLI_DIR/cmds/watch"
  cat > "$CLI_DIR/cmds/watch/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS: []
tasks:
  foo:
    vars:
      FLAGS: []
    cmd: "echo WATCH_FOO_RAN"
YAML
  awk 'BEGIN{done=0} {print} /^includes:$/ && !done {print "  watch:"; print "    taskfile: ./cmds/watch"; done=1}' \
    "$CLI_DIR/Taskfile.yaml" > "$CLI_DIR/Taskfile.yaml.new"
  mv "$CLI_DIR/Taskfile.yaml.new" "$CLI_DIR/Taskfile.yaml"

  run bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
  [ "$status" -eq 0 ]
}

@test "compile permits an unrelated user command name 'watcher'" {
  # Sanity: substring matches don't trip the rejection. Only the exact
  # bare token is reserved.
  create_test_cli "watcher"
  run bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
  [ "$status" -eq 0 ]
}

@test "compile permits 'help' as a user command (asymmetric reservation)" {
  # `help` is intentionally NOT reserved — the wrapper's `help <cmd>`
  # rewrite guards with `! _is_task_prefix "help"` so a user-defined
  # `help` task wins. This test locks that asymmetry into the test suite
  # so a future "reserve help too" change won't slip in unnoticed.
  create_test_cli "help"
  run bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
  [ "$status" -eq 0 ]
}
