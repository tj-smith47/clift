#!/usr/bin/env bats

load test_helper

@test "update detects .cfgd-managed and refuses git pull" {
  # Create a mock framework dir in TEST_DIR to avoid touching the real repo
  local mock_fw="$TEST_DIR/framework"
  mkdir -p "$mock_fw/lib/update"
  cp "$FRAMEWORK_DIR/lib/update/update.sh" "$mock_fw/lib/update/update.sh"
  cp -r "$FRAMEWORK_DIR/lib/log" "$mock_fw/lib/log"
  touch "$mock_fw/.cfgd-managed"
  run bash "$mock_fw/lib/update/update.sh" "$mock_fw"
  [ "$status" -eq 0 ]
  [[ "$output" == *"managed by cfgd"* ]]
  [[ "$output" == *"cfgd module upgrade clift"* ]]
}

@test "update proceeds normally without .cfgd-managed" {
  # Without .cfgd-managed, update should reach the git check phase.
  # Use a mock framework dir to avoid real git fetches.
  local mock_fw="$TEST_DIR/framework"
  mkdir -p "$mock_fw/lib/update"
  cp "$FRAMEWORK_DIR/lib/update/update.sh" "$mock_fw/lib/update/update.sh"
  cp -r "$FRAMEWORK_DIR/lib/log" "$mock_fw/lib/log"
  # init a git repo so update.sh's git commands don't fail immediately
  git -C "$mock_fw" init -q
  git -C "$mock_fw" -c user.email="test@test.com" -c user.name="Test" commit --allow-empty -m "init" -q
  run bash "$mock_fw/lib/update/update.sh" "$mock_fw" 2>&1
  [[ "$output" != *"managed by cfgd"* ]]
}

@test "setup generates module.yaml" {
  CLI_NAME="testmod" \
  CLI_VERSION="0.1.0" \
  LOG_THEME="minimal" \
  PROMPT="false" \
  run bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/newcli" "$FRAMEWORK_DIR" "testmod" "0.1.0" "minimal"
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/newcli/module.yaml" ]
  # Verify it references the right module dependency
  run grep "clift" "$TEST_DIR/newcli/module.yaml"
  [ "$status" -eq 0 ]
}

@test "setup module.yaml contains CLI name" {
  CLI_NAME="mytools" \
  CLI_VERSION="0.1.0" \
  LOG_THEME="minimal" \
  PROMPT="false" \
  run bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mytools" "$FRAMEWORK_DIR" "mytools" "0.1.0" "minimal"
  [ "$status" -eq 0 ]
  run grep "name: mytools" "$TEST_DIR/mytools/module.yaml"
  [ "$status" -eq 0 ]
}

@test "setup generates CI workflow" {
  PROMPT="false" \
  run bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/cigentest" "$FRAMEWORK_DIR" "cigentest" "0.1.0" "minimal"
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/cigentest/.github/workflows/ci.yml" ]
  run grep "shellcheck" "$TEST_DIR/cigentest/.github/workflows/ci.yml"
  [ "$status" -eq 0 ]
}

@test "setup module.yaml uses portable paths" {
  CLI_NAME="mytools" \
  CLI_VERSION="0.1.0" \
  LOG_THEME="minimal" \
  PROMPT="false" \
  run bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/portable" "$FRAMEWORK_DIR" "mytools" "0.1.0" "minimal"
  [ "$status" -eq 0 ]
  # Should use ~/.local/share paths, not absolute machine paths
  run grep "~/.local/share/clift" "$TEST_DIR/portable/module.yaml"
  [ "$status" -eq 0 ]
  run grep "~/.local/share/mytools" "$TEST_DIR/portable/module.yaml"
  [ "$status" -eq 0 ]
}
