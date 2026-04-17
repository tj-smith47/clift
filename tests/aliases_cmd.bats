#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

# Task 5.1 — Command aliases
#
# A command declared with `aliases: [d, dep]` must be reachable via any of
# its names from dispatch, advertised in help (list + detail), present in
# the completion script, and considered as a candidate for did-you-mean.

load test_helper

# Build a CLI with one command `deploy` that has aliases `d` and `dep`,
# plus a sibling command `hello` (no aliases) — used for did-you-mean
# proximity tests so that the alias set is meaningfully populated.
_setup_aliased_cli() {
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
    - {name: no-cache, type: bool, desc: "Force-rebuild the .clift cache"}
    - {name: version, type: bool, desc: "Version"}
includes:
  deploy:
    taskfile: ./cmds/deploy
  hello:
    taskfile: ./cmds/hello
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

  mkdir -p "$CLI_DIR/cmds/deploy"
  cat > "$CLI_DIR/cmds/deploy/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS: []
tasks:
  default:
    desc: "Deploy the app"
    aliases: [d, dep]
    vars:
      FLAGS: []
    cmd: echo deploy-ran
YAML

  mkdir -p "$CLI_DIR/cmds/hello"
  cat > "$CLI_DIR/cmds/hello/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS: []
tasks:
  default:
    desc: "Greet the user"
    vars:
      FLAGS: []
    cmd: echo hello-ran
YAML

  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
  build_test_wrapper
}

# --- Dispatch ----------------------------------------------------------------

@test "alias dispatch: canonical name still works" {
  _setup_aliased_cli
  run "$CLI_DIR/bin/$CLI_NAME" deploy
  [ "$status" -eq 0 ]
  [[ "$output" == *"deploy-ran"* ]]
}

@test "alias dispatch: short alias 'd' runs canonical task" {
  _setup_aliased_cli
  run "$CLI_DIR/bin/$CLI_NAME" d
  [ "$status" -eq 0 ]
  [[ "$output" == *"deploy-ran"* ]]
}

@test "alias dispatch: medium alias 'dep' runs canonical task" {
  _setup_aliased_cli
  run "$CLI_DIR/bin/$CLI_NAME" dep
  [ "$status" -eq 0 ]
  [[ "$output" == *"deploy-ran"* ]]
}

# --- Help listing ------------------------------------------------------------

@test "help list: aliases appear next to canonical name" {
  _setup_aliased_cli
  run bash "$FRAMEWORK_DIR/lib/help/list.sh" "$CLI_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  # Both alias names render on the same display line as the canonical
  [[ "$output" == *"deploy, d, dep"* ]]
  # Aliases must NOT appear as separate top-level rows
  local d_rows
  d_rows=$(echo "$output" | grep -cE '^\s+d\s' || true)
  [ "$d_rows" -eq 0 ]
}

# --- Help detail -------------------------------------------------------------

@test "help detail: 'Aliases:' line shows comma-separated alias list" {
  _setup_aliased_cli
  run bash "$FRAMEWORK_DIR/lib/help/detail.sh" deploy "$CLI_DIR/Taskfile.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Aliases: d, dep"* ]]
}

# --- Completion --------------------------------------------------------------

@test "completion (bash, standard mode): aliases reachable as candidates" {
  _setup_aliased_cli
  CLIFT_MODE=standard run bash "$FRAMEWORK_DIR/lib/completion/completion.sh" bash
  [ "$status" -eq 0 ]
  # Source the script in a subshell, fake completion state, then assert
  # COMPREPLY contains both the canonical and the aliases. The completion
  # function locates the CLI dir via `command -v $CLI_NAME`, so PATH must
  # include the test wrapper's bin/ directory.
  local script_file="$BATS_TEST_TMPDIR/comp.sh"
  printf '%s\n' "$output" > "$script_file"

  run bash -c "
    export PATH='$CLI_DIR/bin:'\$PATH
    source '$script_file'
    COMP_WORDS=('$CLI_NAME' '')
    COMP_CWORD=1
    _${CLI_NAME}_completions
    printf '%s\n' \"\${COMPREPLY[@]}\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"deploy"* ]]
  [[ "$output" == *"d"* ]]
  [[ "$output" == *"dep"* ]]
}

# --- Hidden-command aliases --------------------------------------------------

# A command marked vars.HIDDEN: true must keep ALL of its names (canonical +
# every alias) out of the completion candidate set. Earlier the canonical
# was filtered correctly via $hidden, but the alias_names collector did
# not consult $hidden so aliases of a hidden command leaked through.
@test "completion: hidden command's aliases are filtered" {
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
    - {name: no-cache, type: bool, desc: "Force-rebuild the .clift cache"}
    - {name: version, type: bool, desc: "Version"}
includes:
  secret:
    taskfile: ./cmds/secret
  visible:
    taskfile: ./cmds/visible
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

  mkdir -p "$CLI_DIR/cmds/secret"
  cat > "$CLI_DIR/cmds/secret/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS: []
  HIDDEN: true
tasks:
  default:
    aliases: [s, sec]
    vars:
      FLAGS: []
    cmd: echo secret
YAML
  mkdir -p "$CLI_DIR/cmds/visible"
  cat > "$CLI_DIR/cmds/visible/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS: []
tasks:
  default:
    vars:
      FLAGS: []
    cmd: echo visible
YAML

  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
  build_test_wrapper

  CLIFT_MODE=standard run bash "$FRAMEWORK_DIR/lib/completion/completion.sh" bash
  [ "$status" -eq 0 ]
  local script_file="$BATS_TEST_TMPDIR/comp.sh"
  printf '%s\n' "$output" > "$script_file"

  run bash -c "
    export PATH='$CLI_DIR/bin:'\$PATH
    source '$script_file'
    COMP_WORDS=('$CLI_NAME' '')
    COMP_CWORD=1
    _${CLI_NAME}_completions
    printf '%s\n' \"\${COMPREPLY[@]}\"
  "
  [ "$status" -eq 0 ]
  # visible command is present
  printf '%s\n' "$output" | grep -Fxq visible
  # secret command and BOTH of its aliases are absent
  ! printf '%s\n' "$output" | grep -Fxq secret
  ! printf '%s\n' "$output" | grep -Fxq s
  ! printf '%s\n' "$output" | grep -Fxq sec
}

# --- Compile-time validation ------------------------------------------------

# Two commands declaring the same alias name (e.g. `deploy → d` and
# `destroy → d`) must be rejected by compile.sh. Otherwise the wrapper's
# alias map silently last-write-wins and one of the routes vanishes.
@test "compile rejects duplicate alias across commands" {
  cat > "$CLI_DIR/Taskfile.yaml" <<'YAML'
version: '3'
silent: true
includes:
  deploy:
    taskfile: ./cmds/deploy
  destroy:
    taskfile: ./cmds/destroy
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

  mkdir -p "$CLI_DIR/cmds/deploy" "$CLI_DIR/cmds/destroy"
  cat > "$CLI_DIR/cmds/deploy/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS: []
tasks:
  default:
    aliases: [d]
    vars:
      FLAGS: []
    cmd: echo deploy
YAML
  cat > "$CLI_DIR/cmds/destroy/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS: []
tasks:
  default:
    aliases: [d]
    vars:
      FLAGS: []
    cmd: echo destroy
YAML

  run bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"alias 'd' declared by both 'deploy' and 'destroy'"* ]]
}

# --- Did-you-mean ------------------------------------------------------------

@test "did-you-mean: a typo near an alias suggests the alias" {
  _setup_aliased_cli
  # 'dx' is distance 1 from 'd' (and 2 from 'dep'). The closest match wins.
  run "$CLI_DIR/bin/$CLI_NAME" dx
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown command"* ]]
  [[ "$output" == *"did you mean"* ]]
  # The suggestion comes from the candidate set — alias OR canonical close.
  # 'dx' is distance 1 from 'd', distance 2 from 'dep', distance 5 from
  # 'deploy'; 'd' must win iff the alias is in the candidate set.
  [[ "$output" == *"'d'"* ]]
}
