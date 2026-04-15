#!/usr/bin/env bats
# Persistent (CLI-wide) flags: vars.PERSISTENT_FLAGS at the root Taskfile
# merge into every command's flag table and may appear before OR after the
# command token. The wrapper early-binds pre-command occurrences so they
# reach every execution path (including the router's parser for the
# resolved command, where they're also present in the merged flag table
# and can be overridden by a post-command occurrence — last-write-wins).
bats_require_minimum_version 1.5.0

load test_helper

# Build a two-command CLI with one persistent flag declared at the root.
# Both commands echo the CLIFT_FLAG_PROFILE env var so tests can verify the
# value flowed all the way down.
_setup_persistent_cli() {
  local persistent_block="$1"

  cat > "$CLI_DIR/Taskfile.yaml" <<YAML
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
    - {name: version, type: bool, desc: "Version"}
${persistent_block}
includes:
  deploy:
    taskfile: ./cmds/deploy
  build:
    taskfile: ./cmds/build
tasks:
  default:
    cmd: echo root
YAML

  cat > "$CLI_DIR/.env" <<ENV
CLI_NAME=$CLI_NAME
CLI_VERSION=$CLI_VERSION
CLI_DIR=$CLI_DIR
FRAMEWORK_DIR=$FRAMEWORK_DIR
CLIFT_MODE=standard
LOG_THEME=minimal
ENV

  mkdir -p "$CLI_DIR/cmds/deploy" "$CLI_DIR/cmds/build"

  # Each command is parsed (FLAGS: []) so the router merges in the persistent
  # layer and the post-command position of persistent flags works via parser.sh.
  for cmd in deploy build; do
    cat > "$CLI_DIR/cmds/${cmd}/Taskfile.yaml" <<YAML
version: '3'
vars:
  FLAGS: []
tasks:
  default:
    vars:
      FLAGS: []
    cmd: "CLI_ARGS='{{.CLI_ARGS}}' '{{.FRAMEWORK_DIR}}/lib/router/router.sh' '{{.TASK}}'"
YAML
    cat > "$CLI_DIR/cmds/${cmd}/${cmd}.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "cmd=__CMD__ profile=${CLIFT_FLAG_PROFILE:-<unset>}"
if [[ -n "${CLIFT_FLAG_TAG_COUNT:-}" ]]; then
  n="${CLIFT_FLAG_TAG_COUNT}"
  for ((i=1;i<=n;i++)); do
    v="CLIFT_FLAG_TAG_$i"
    echo "tag=${!v}"
  done
fi
SH
    # Bash doesn't interpolate placeholders in heredoc with quoted marker, so
    # substitute after the fact.
    sed -e "s|__CMD__|${cmd}|" "$CLI_DIR/cmds/${cmd}/${cmd}.sh" > "$CLI_DIR/cmds/${cmd}/${cmd}.sh.tmp"
    mv "$CLI_DIR/cmds/${cmd}/${cmd}.sh.tmp" "$CLI_DIR/cmds/${cmd}/${cmd}.sh"
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
