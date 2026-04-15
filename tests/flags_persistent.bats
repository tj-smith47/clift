#!/usr/bin/env bats
# Persistent (CLI-wide) flags: vars.PERSISTENT_FLAGS at the root Taskfile
# merge into every command's flag table and may appear before OR after the
# command token. The wrapper early-binds pre-command occurrences so they
# reach every execution path (including the router's parser for the
# resolved command, where they're also present in the merged flag table
# and can be overridden by a post-command occurrence — last-write-wins).
bats_require_minimum_version 1.5.0

load test_helper

# Build a two-command CLI with a persistent-flag block declared at the root.
# Uses create_test_cli for the root scaffold (injecting PERSISTENT_FLAGS via
# CLIFT_TEST_PERSISTENT_BLOCK) and adds a sibling `build` cmd identical to
# the one create_test_cli produces for `deploy`. Both commands echo
# CLIFT_FLAG_PROFILE (plus any CLIFT_FLAG_TAG_* list values) so tests can
# verify the value flowed all the way down.
_setup_persistent_cli() {
  CLIFT_TEST_PERSISTENT_BLOCK="$1" create_test_cli deploy

  # Splice a second include (build) ahead of the tasks: section so it lives
  # under includes:, not tasks:. The rewrite is a straight awk substitution
  # (no sed -i, no in-place edits) to keep this portable across GNU/BSD.
  awk '
    /^tasks:/ && !done { print "  build:\n    taskfile: ./cmds/build"; done=1 }
    { print }
  ' "$CLI_DIR/Taskfile.yaml" > "$CLI_DIR/Taskfile.yaml.tmp"
  mv "$CLI_DIR/Taskfile.yaml.tmp" "$CLI_DIR/Taskfile.yaml"

  mkdir -p "$CLI_DIR/cmds/build"
  cp "$CLI_DIR/cmds/deploy/Taskfile.yaml" "$CLI_DIR/cmds/build/Taskfile.yaml"

  for cmd in deploy build; do
    cat > "$CLI_DIR/cmds/${cmd}/${cmd}.sh" <<SH
#!/usr/bin/env bash
set -euo pipefail
echo "cmd=${cmd} profile=\${CLIFT_FLAG_PROFILE:-<unset>}"
if [[ -n "\${CLIFT_FLAG_TAG_COUNT:-}" ]]; then
  n="\${CLIFT_FLAG_TAG_COUNT}"
  for ((i=1;i<=n;i++)); do
    v="CLIFT_FLAG_TAG_\$i"
    echo "tag=\${!v}"
  done
fi
SH
    chmod +x "$CLI_DIR/cmds/${cmd}/${cmd}.sh"
  done

  build_test_wrapper
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
}

@test "persistent flag: value set via pre-command position reaches the command" {
  _setup_persistent_cli "  PERSISTENT_FLAGS:
    - {name: profile, short: p, type: string, default: \"default\", desc: \"Profile\"}"

  run "$CLI_DIR/bin/$CLI_NAME" --profile=staging deploy
  [ "$status" -eq 0 ]
  [[ "$output" == *"cmd=deploy profile=staging"* ]]
}

@test "persistent flag: value set via post-command position reaches the command" {
  _setup_persistent_cli "  PERSISTENT_FLAGS:
    - {name: profile, short: p, type: string, default: \"default\", desc: \"Profile\"}"

  run "$CLI_DIR/bin/$CLI_NAME" deploy --profile=staging
  [ "$status" -eq 0 ]
  [[ "$output" == *"cmd=deploy profile=staging"* ]]
}

@test "persistent flag: default applies when not provided" {
  _setup_persistent_cli "  PERSISTENT_FLAGS:
    - {name: profile, short: p, type: string, default: \"default\", desc: \"Profile\"}"

  run "$CLI_DIR/bin/$CLI_NAME" deploy
  [ "$status" -eq 0 ]
  [[ "$output" == *"cmd=deploy profile=default"* ]]
}

@test "persistent flag: available on every command (deploy and build)" {
  _setup_persistent_cli "  PERSISTENT_FLAGS:
    - {name: profile, short: p, type: string, default: \"default\", desc: \"Profile\"}"

  run "$CLI_DIR/bin/$CLI_NAME" --profile=prod deploy
  [ "$status" -eq 0 ]
  [[ "$output" == *"cmd=deploy profile=prod"* ]]

  run "$CLI_DIR/bin/$CLI_NAME" --profile=prod build
  [ "$status" -eq 0 ]
  [[ "$output" == *"cmd=build profile=prod"* ]]
}

@test "persistent flag: short form pre-command (-p value)" {
  _setup_persistent_cli "  PERSISTENT_FLAGS:
    - {name: profile, short: p, type: string, default: \"default\", desc: \"Profile\"}"

  run "$CLI_DIR/bin/$CLI_NAME" -p staging deploy
  [ "$status" -eq 0 ]
  [[ "$output" == *"cmd=deploy profile=staging"* ]]
}

@test "persistent flag: short form pre-command (-p=value)" {
  _setup_persistent_cli "  PERSISTENT_FLAGS:
    - {name: profile, short: p, type: string, default: \"default\", desc: \"Profile\"}"

  run "$CLI_DIR/bin/$CLI_NAME" -p=staging deploy
  [ "$status" -eq 0 ]
  [[ "$output" == *"cmd=deploy profile=staging"* ]]
}

@test "persistent flag: post-command value overrides pre-command (last-write-wins)" {
  _setup_persistent_cli "  PERSISTENT_FLAGS:
    - {name: profile, short: p, type: string, default: \"default\", desc: \"Profile\"}"

  run "$CLI_DIR/bin/$CLI_NAME" --profile=staging deploy --profile=prod
  [ "$status" -eq 0 ]
  [[ "$output" == *"cmd=deploy profile=prod"* ]]
}

@test "compile error: persistent flag clashes with per-command flag" {
  cat > "$CLI_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: help, short: h, type: bool, desc: "Show help"}
  PERSISTENT_FLAGS:
    - {name: profile, short: p, type: string, default: "default", desc: "Profile"}
includes:
  deploy:
    taskfile: ./cmds/deploy
tasks:
  default:
    cmd: echo root
YAML
  mkdir -p "$CLI_DIR/cmds/deploy"
  cat > "$CLI_DIR/cmds/deploy/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: profile, type: string, desc: "Per-command profile"}
tasks:
  default:
    cmd: echo deploy
YAML

  run bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"persistent flag"* ]]
  [[ "$output" == *"profile"* ]]
  [[ "$output" == *"per-command"* ]]
}

@test "compile error: persistent flag clashes with per-command short" {
  cat > "$CLI_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: help, short: h, type: bool, desc: "Show help"}
  PERSISTENT_FLAGS:
    - {name: profile, short: p, type: string, default: "default", desc: "Profile"}
includes:
  deploy:
    taskfile: ./cmds/deploy
tasks:
  default:
    cmd: echo root
YAML
  mkdir -p "$CLI_DIR/cmds/deploy"
  cat > "$CLI_DIR/cmds/deploy/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: port, short: p, type: int, default: 80, desc: "Port"}
tasks:
  default:
    cmd: echo deploy
YAML

  run bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"short"* ]]
  [[ "$output" == *"persistent"* ]]
}

@test "compile error: persistent flag clashes with reserved global (help)" {
  cat > "$CLI_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: help, short: h, type: bool, desc: "Show help"}
  PERSISTENT_FLAGS:
    - {name: help, type: bool, desc: "Bad"}
tasks:
  default:
    cmd: echo root
YAML

  run bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"reserved"* ]]
  [[ "$output" == *"help"* ]]
}

@test "compile error: persistent flag clashes with reserved global (verbose)" {
  cat > "$CLI_DIR/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS:
    - {name: help, short: h, type: bool, desc: "Show help"}
  PERSISTENT_FLAGS:
    - {name: verbose, type: bool, desc: "Bad"}
tasks:
  default:
    cmd: echo root
YAML

  run bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"reserved"* ]]
}

@test "persistent list flag: pre-command repeats accumulate" {
  _setup_persistent_cli "  PERSISTENT_FLAGS:
    - {name: tag, type: list, desc: \"Tags\"}"

  run "$CLI_DIR/bin/$CLI_NAME" --tag=one --tag=two deploy
  [ "$status" -eq 0 ]
  [[ "$output" == *"tag=one"* ]]
  [[ "$output" == *"tag=two"* ]]
}

@test "persistent list flag: mixed pre+post accumulate" {
  _setup_persistent_cli "  PERSISTENT_FLAGS:
    - {name: tag, type: list, desc: \"Tags\"}"

  run "$CLI_DIR/bin/$CLI_NAME" --tag=one deploy --tag=two
  [ "$status" -eq 0 ]
  [[ "$output" == *"tag=one"* ]]
  [[ "$output" == *"tag=two"* ]]
}

@test "cache invalidates when PERSISTENT_FLAGS changes" {
  _setup_persistent_cli "  PERSISTENT_FLAGS:
    - {name: profile, short: p, type: string, default: \"default\", desc: \"Profile\"}"

  # Sanity
  run "$CLI_DIR/bin/$CLI_NAME" deploy
  [ "$status" -eq 0 ]
  [[ "$output" == *"profile=default"* ]]

  # Rewrite root Taskfile with a different default; cache must rebuild.
  sleep 1
  _setup_persistent_cli "  PERSISTENT_FLAGS:
    - {name: profile, short: p, type: string, default: \"newdefault\", desc: \"Profile\"}"

  run "$CLI_DIR/bin/$CLI_NAME" deploy
  [ "$status" -eq 0 ]
  [[ "$output" == *"profile=newdefault"* ]]
}

# [C1] Bare `--` post-command must not crash the wrapper under set -u. Prior
# to the fix the persistence dispatch tried to index _persist_type[""] on a
# bare "--" token and tripped a bad-array-subscript abort.
@test "persistent: post-command bare -- terminates wrapper flag scan (no crash)" {
  _setup_persistent_cli "  PERSISTENT_FLAGS:
    - {name: profile, short: p, type: string, default: \"default\", desc: \"Profile\"}"

  run "$CLI_DIR/bin/$CLI_NAME" deploy --
  [ "$status" -eq 0 ]
  [[ "$output" == *"cmd=deploy profile=default"* ]]
}

# [C1] Tokens after `--` pass through verbatim, even ones that would
# otherwise be persistent flags. `--profile=x` after the terminator must be
# treated as a literal positional and must NOT bind CLIFT_FLAG_PROFILE.
@test "persistent: post-command -- passes subsequent flag-looking tokens as literals" {
  _setup_persistent_cli "  PERSISTENT_FLAGS:
    - {name: profile, short: p, type: string, default: \"default\", desc: \"Profile\"}"

  run "$CLI_DIR/bin/$CLI_NAME" deploy -- --profile=x
  [ "$status" -eq 0 ]
  # The persistent --profile should stay at its default; the post-`--` token
  # is a literal positional, not a flag. (The deploy script echoes profile
  # from CLIFT_FLAG_PROFILE which the parser leaves at the declared default.)
  [[ "$output" == *"cmd=deploy profile=default"* ]]
}

# [C2] Pre-command `--` terminates wrapper scanning at the first token. A
# `--profile=x` that follows must NOT bind; it is a literal positional.
@test "persistent: pre-command -- terminates wrapper flag scan (profile not bound)" {
  _setup_persistent_cli "  PERSISTENT_FLAGS:
    - {name: profile, short: p, type: string, default: \"default\", desc: \"Profile\"}"

  run "$CLI_DIR/bin/$CLI_NAME" -- --profile=x deploy
  [ "$status" -eq 0 ]
  # Nothing beyond `--` was interpreted as a flag — profile stayed unset
  # (no default applied either, because no command was dispatched through
  # the router's parser; the root task runs).
  [[ "$output" != *"profile=x"* ]]
  # `deploy` appears in the literal argv forwarded to the root task; see
  # the root Taskfile's default command output.
}

# [I3] Persistent list flag default MUST be washed by wrapper binding. With
# default "a,b", invoking `mycli --tag=c cmd --tag=d` should yield exactly
# c,d — the wrapper's pre-command bind counts as a user value and must
# override (not extend) the declared default, then the post-command token
# appends to that wrapper-bound set. Expected final: c,d (not a,b,c,d).
@test "persistent list flag: user values replace default, do not concatenate (pre+post)" {
  _setup_persistent_cli "  PERSISTENT_FLAGS:
    - {name: tag, type: list, default: \"a,b\", desc: \"Tags\"}"

  run "$CLI_DIR/bin/$CLI_NAME" --tag=c deploy --tag=d
  [ "$status" -eq 0 ]
  [[ "$output" == *"tag=c"* ]]
  [[ "$output" == *"tag=d"* ]]
  # Default tokens MUST NOT appear once the user has supplied values.
  [[ "$output" != *"tag=a"* ]]
  [[ "$output" != *"tag=b"* ]]
}
