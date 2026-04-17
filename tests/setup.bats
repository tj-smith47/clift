#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR"
  export FRAMEWORK_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export PROMPT="false"
  export CLIFT_RC_FILE="$HOME/.bashrc"
  touch "$HOME/.bashrc"
  touch "$HOME/.zshrc"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "setup.sh creates CLI directory and .env" {
  run bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "1.0.0" "minimal" "standard"
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/mycli/.env" ]
  [ -d "$TEST_DIR/mycli/cmds" ]
}

@test "setup.sh creates Taskfile.yaml" {
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "1.0.0" "minimal" "standard"
  [ -f "$TEST_DIR/mycli/Taskfile.yaml" ]
}

@test "setup.sh creates .clift.yaml metadata" {
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "1.0.0" "minimal" "standard"
  [ -f "$TEST_DIR/mycli/.clift.yaml" ]
}

@test "setup.sh does not create module.yaml without CFGD_VERSIONING" {
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "1.0.0" "minimal" "standard"
  [ ! -f "$TEST_DIR/mycli/module.yaml" ]
}

@test "setup.sh creates module.yaml when CFGD_VERSIONING=true" {
  CFGD_VERSIONING=true bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "1.0.0" "minimal" "standard"
  [ -f "$TEST_DIR/mycli/module.yaml" ]
  grep -q "mycli" "$TEST_DIR/mycli/module.yaml"
}

@test "setup.sh standard mode creates wrapper script" {
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "1.0.0" "minimal" "standard"
  [ -x "$TEST_DIR/mycli/bin/mycli" ]
}

@test "setup.sh standard mode adds PATH with \$HOME to rc file" {
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "1.0.0" "minimal" "standard"
  grep -q "export PATH" "$HOME/.bashrc"
  # PATH should use $HOME, not absolute path
  grep -q '\$HOME' "$HOME/.bashrc"
  # PATH should not contain /./
  ! grep -q '/\./' "$HOME/.bashrc"
}

@test "setup.sh task mode creates alias with \$HOME in rc file" {
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "1.0.0" "minimal" "task"
  grep -q "alias mycli=" "$HOME/.bashrc"
  # Alias should use $HOME, not absolute path
  grep -q '\$HOME' "$HOME/.bashrc"
}

@test "setup.sh task mode does not create wrapper script" {
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "1.0.0" "minimal" "task"
  [ ! -f "$TEST_DIR/mycli/bin/mycli" ]
}

@test "setup.sh .env contains correct CLI_NAME" {
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "2.0.0" "brackets" "standard"
  grep -q "CLI_NAME=mycli" "$TEST_DIR/mycli/.env"
  grep -q "CLI_VERSION=2.0.0" "$TEST_DIR/mycli/.env"
  grep -q "LOG_THEME=brackets" "$TEST_DIR/mycli/.env"
}

@test "setup.sh rejects invalid CLI_NAME" {
  run bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "My-CLI!" "1.0.0" "minimal" "standard"
  [ "$status" -ne 0 ]
  [[ "$output" == *"lowercase"* ]]
}

@test "setup.sh rejects invalid CLIFT_MODE" {
  run bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "1.0.0" "minimal" "badmode"
  [ "$status" -eq 1 ]
  [[ "$output" == *"CLIFT_MODE"* ]]
}

@test "setup.sh defaults CLI_NAME to basename of target" {
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/myapp" "$FRAMEWORK_DIR" "" "1.0.0" "minimal" "standard"
  grep -q "CLI_NAME=myapp" "$TEST_DIR/myapp/.env"
}

@test "setup.sh requires TARGET_DIR and FRAMEWORK_DIR" {
  run bash "$FRAMEWORK_DIR/lib/setup/setup.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires"* ]]
}

@test "setup.sh strips Taskfile.yaml from path" {
  mkdir -p "$TEST_DIR/sub"
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/sub/Taskfile.yaml" "$FRAMEWORK_DIR" "sub" "1.0.0" "minimal" "standard"
  [ -f "$TEST_DIR/sub/.env" ]
}

@test "setup.sh reconfigure updates .env" {
  # First install
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "1.0.0" "minimal" "standard"
  grep -q "CLI_VERSION=1.0.0" "$TEST_DIR/mycli/.env"

  # Reconfigure — prompt.sh uses --var to check env, so set the vars
  export RECONFIGURE_YES=1
  export _RECONFIG_NAME="mycli"
  export _RECONFIG_VERSION="2.0.0"
  export _RECONFIG_THEME="brackets"
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "2.0.0" "brackets" "standard"
  grep -q "CLI_VERSION=2.0.0" "$TEST_DIR/mycli/.env"
}

@test "setup.sh mode switch from task to standard" {
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "1.0.0" "minimal" "task"
  grep -q "alias mycli=" "$HOME/.bashrc"

  export RECONFIGURE_YES=1
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "1.0.0" "minimal" "standard"
  # Alias should be gone, PATH should be there
  ! grep -q "alias mycli=" "$HOME/.bashrc"
  grep -q "export PATH" "$HOME/.bashrc"
}

@test "setup.sh does not copy CI workflow without CLIFT_CI" {
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "1.0.0" "minimal" "standard"
  [ ! -f "$TEST_DIR/mycli/.github/workflows/ci.yml" ]
}

@test "setup.sh copies CI workflow with CLIFT_CI=true" {
  CLIFT_CI=true bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "1.0.0" "minimal" "standard"
  [ -f "$TEST_DIR/mycli/.github/workflows/ci.yml" ]
}

@test "setup.sh precompiles cache" {
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mycli" "$FRAMEWORK_DIR" "mycli" "1.0.0" "minimal" "standard"
  [ -d "$TEST_DIR/mycli/.clift" ]
}

@test "setup.sh detects zsh shell for rc file" {
  export SHELL=/bin/zsh
  unset CLIFT_RC_FILE
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/zshcli" "$FRAMEWORK_DIR" "zshcli" "1.0.0" "minimal" "standard"
  grep -q "zshcli" "$HOME/.zshrc"
}

@test "setup.sh renders template placeholders correctly" {
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/tmplcli" "$FRAMEWORK_DIR" "tmplcli" "0.5.0" "brackets" "standard"
  # .env should have resolved placeholders, not raw %%TOKENS%%
  ! grep -q '%%' "$TEST_DIR/tmplcli/.env"
  grep -q "CLI_NAME=tmplcli" "$TEST_DIR/tmplcli/.env"
  grep -q "CLI_VERSION=0.5.0" "$TEST_DIR/tmplcli/.env"
  grep -q "LOG_THEME=brackets" "$TEST_DIR/tmplcli/.env"
}

@test "setup.sh does not overwrite existing Taskfile" {
  mkdir -p "$TEST_DIR/existing"
  echo "custom content" > "$TEST_DIR/existing/Taskfile.yaml"
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/existing" "$FRAMEWORK_DIR" "existing" "1.0.0" "minimal" "standard"
  # Taskfile should still have the custom content
  grep -q "custom content" "$TEST_DIR/existing/Taskfile.yaml"
}

@test "setup.sh creates parent directory if needed" {
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/deep/nested/cli" "$FRAMEWORK_DIR" "nested" "1.0.0" "minimal" "standard"
  [ -f "$TEST_DIR/deep/nested/cli/.env" ]
}

@test "setup.sh resolves . target without /./bin in PATH" {
  mkdir -p "$TEST_DIR/dotcli"
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/dotcli/." "$FRAMEWORK_DIR" "dotcli" "1.0.0" "minimal" "standard"
  # PATH entry should not contain /./
  ! grep -q '/\./' "$HOME/.bashrc"
  # Wrapper should exist at the resolved path
  [ -x "$TEST_DIR/dotcli/bin/dotcli" ]
}

@test "setup.sh success message shows standard mode next steps" {
  run bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/nextstep" "$FRAMEWORK_DIR" "nextstep" "1.0.0" "minimal" "standard"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nextstep new cmd"* ]]
}

@test "setup.sh with CFGD_VERSIONING triggers version setup" {
  # Mock cfgd
  mkdir -p "$TEST_DIR/bin"
  cat > "$TEST_DIR/bin/cfgd" <<'SH'
#!/bin/sh
echo "mock-cfgd"
SH
  chmod +x "$TEST_DIR/bin/cfgd"
  export PATH="$TEST_DIR/bin:$PATH"

  CFGD_VERSIONING=true \
  run bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/vcli" "$FRAMEWORK_DIR" "vcli" "1.0.0" "minimal" "standard" 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == *"versioning"* ]]
}

@test "setup.sh success message shows task mode next steps" {
  run bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/taskstep" "$FRAMEWORK_DIR" "taskstep" "1.0.0" "minimal" "task"
  [ "$status" -eq 0 ]
  [[ "$output" == *"new:cmd"* ]]
}

# Task 5.3: completion install

@test "setup.sh installs bash completion sourcing line in standard mode" {
  export SHELL=/bin/bash
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/comp1" "$FRAMEWORK_DIR" "comp1" "1.0.0" "minimal" "standard"
  grep -q "# clift: comp1-completion" "$HOME/.bashrc"
  grep -q 'source <(comp1 completion bash)' "$HOME/.bashrc"
}

@test "setup.sh installs zsh completion sourcing line" {
  export SHELL=/bin/zsh
  unset CLIFT_RC_FILE
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/comp2" "$FRAMEWORK_DIR" "comp2" "1.0.0" "minimal" "standard"
  grep -q "# clift: comp2-completion" "$HOME/.zshrc"
  grep -q 'source <(comp2 completion zsh)' "$HOME/.zshrc"
}

@test "setup.sh uses colon form for task mode completion" {
  export SHELL=/bin/bash
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/comp3" "$FRAMEWORK_DIR" "comp3" "1.0.0" "minimal" "task"
  grep -q 'source <(comp3 completion:bash)' "$HOME/.bashrc"
}

@test "setup.sh CLIFT_COMPLETIONS=false skips completion install" {
  export SHELL=/bin/bash
  CLIFT_COMPLETIONS=false bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/comp4" "$FRAMEWORK_DIR" "comp4" "1.0.0" "minimal" "standard"
  ! grep -q "comp4-completion" "$HOME/.bashrc"
  ! grep -q "source <(comp4 completion" "$HOME/.bashrc"
}

@test "setup.sh CLIFT_COMPLETIONS=auto skips unsupported shells silently" {
  export SHELL=/usr/bin/fish
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/comp5" "$FRAMEWORK_DIR" "comp5" "1.0.0" "minimal" "standard"
  ! grep -q "comp5-completion" "$HOME/.bashrc"
}

@test "setup.sh CLIFT_COMPLETIONS=true warns on unsupported shell" {
  export SHELL=/usr/bin/fish
  run bash -c "CLIFT_COMPLETIONS=true bash '$FRAMEWORK_DIR/lib/setup/setup.sh' \
    '$TEST_DIR/comp6' '$FRAMEWORK_DIR' comp6 1.0.0 minimal standard 2>&1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fish"* ]]
  [[ "$output" == *"not supported"* ]]
  ! grep -q "comp6-completion" "$HOME/.bashrc"
}

@test "setup.sh rejects unknown CLIFT_COMPLETIONS value with warning" {
  export SHELL=/bin/bash
  run bash -c "CLIFT_COMPLETIONS=maybe bash '$FRAMEWORK_DIR/lib/setup/setup.sh' \
    '$TEST_DIR/comp7' '$FRAMEWORK_DIR' comp7 1.0.0 minimal standard 2>&1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"maybe"* ]]
  ! grep -q "comp7-completion" "$HOME/.bashrc"
}

@test "setup.sh reconfigure replaces completion line instead of duplicating" {
  export SHELL=/bin/bash
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/comp8" "$FRAMEWORK_DIR" "comp8" "1.0.0" "minimal" "standard"
  # Exactly one completion sentinel
  [ "$(grep -c '# clift: comp8-completion' "$HOME/.bashrc")" -eq 1 ]

  export RECONFIGURE_YES=1
  export _RECONFIG_NAME="comp8"
  export _RECONFIG_VERSION="2.0.0"
  export _RECONFIG_THEME="minimal"
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/comp8" "$FRAMEWORK_DIR" "comp8" "2.0.0" "minimal" "standard"
  # Still exactly one after reconfigure
  [ "$(grep -c '# clift: comp8-completion' "$HOME/.bashrc")" -eq 1 ]
}

@test "setup.sh mode switch standard→task rewrites completion with colon form" {
  export SHELL=/bin/bash
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/comp9" "$FRAMEWORK_DIR" "comp9" "1.0.0" "minimal" "standard"
  grep -q 'source <(comp9 completion bash)' "$HOME/.bashrc"

  export RECONFIGURE_YES=1
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/comp9" "$FRAMEWORK_DIR" "comp9" "1.0.0" "minimal" "task"
  ! grep -q 'source <(comp9 completion bash)' "$HOME/.bashrc"
  grep -q 'source <(comp9 completion:bash)' "$HOME/.bashrc"
}

@test "setup.sh success message announces completion install" {
  export SHELL=/bin/bash
  run bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/comp10" "$FRAMEWORK_DIR" "comp10" "1.0.0" "minimal" "standard"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Shell completion for bash installed"* ]]
}

@test "setup.sh success message omits completion line when disabled" {
  export SHELL=/bin/bash
  run bash -c "CLIFT_COMPLETIONS=false bash '$FRAMEWORK_DIR/lib/setup/setup.sh' \
    '$TEST_DIR/comp11' '$FRAMEWORK_DIR' comp11 1.0.0 minimal standard"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Shell completion for"* ]]
}
