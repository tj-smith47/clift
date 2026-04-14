#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

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

@test "setup generates module.yaml only with CFGD_VERSIONING" {
  # Without CFGD_VERSIONING, module.yaml should NOT be created
  PROMPT="false" \
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/nocfgd" "$FRAMEWORK_DIR" "nocfgd" "0.1.0" "minimal"
  [ ! -f "$TEST_DIR/nocfgd/module.yaml" ]

  # With CFGD_VERSIONING=true, module.yaml SHOULD be created
  CFGD_VERSIONING="true" \
  PROMPT="false" \
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/newcli" "$FRAMEWORK_DIR" "testmod" "0.1.0" "minimal"
  [ -f "$TEST_DIR/newcli/module.yaml" ]
  grep -q "clift" "$TEST_DIR/newcli/module.yaml"
}

@test "setup module.yaml contains CLI name" {
  CFGD_VERSIONING="true" \
  PROMPT="false" \
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/mytools" "$FRAMEWORK_DIR" "mytools" "0.1.0" "minimal"
  grep -q "name: mytools" "$TEST_DIR/mytools/module.yaml"
}

@test "setup generates CI workflow only with CLIFT_CI=true" {
  # Without CLIFT_CI, workflow should NOT be created
  PROMPT="false" \
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/noci" "$FRAMEWORK_DIR" "noci" "0.1.0" "minimal"
  [ ! -f "$TEST_DIR/noci/.github/workflows/ci.yml" ]

  # With CLIFT_CI=true, workflow SHOULD be created
  CLIFT_CI="true" \
  PROMPT="false" \
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/cigentest" "$FRAMEWORK_DIR" "cigentest" "0.1.0" "minimal"
  [ -f "$TEST_DIR/cigentest/.github/workflows/ci.yml" ]
  grep -q "shellcheck" "$TEST_DIR/cigentest/.github/workflows/ci.yml"
}

@test "update shows already-up-to-date for current repo" {
  local mock_fw="$TEST_DIR/framework"
  mkdir -p "$mock_fw/lib/update"
  cp "$FRAMEWORK_DIR/lib/update/update.sh" "$mock_fw/lib/update/update.sh"
  cp -r "$FRAMEWORK_DIR/lib/log" "$mock_fw/lib/log"
  git -C "$mock_fw" init -q
  git -C "$mock_fw" -c user.email="t@t" -c user.name="T" commit --allow-empty -m "init" -q
  # Create a fake remote that points at itself
  git -C "$mock_fw" remote add origin "$mock_fw"
  git -C "$mock_fw" fetch origin -q 2>/dev/null || true

  run bash "$mock_fw/lib/update/update.sh" "$mock_fw" 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == *"Already up to date"* ]]
}

@test "update shows pending changes when behind remote" {
  local mock_fw="$TEST_DIR/fw_behind"
  mkdir -p "$mock_fw/lib/update"
  cp "$FRAMEWORK_DIR/lib/update/update.sh" "$mock_fw/lib/update/update.sh"
  cp -r "$FRAMEWORK_DIR/lib/log" "$mock_fw/lib/log"

  # Create a "remote" repo with an extra commit
  local remote_repo="$TEST_DIR/remote"
  git init -q "$remote_repo"
  git -C "$remote_repo" -c user.email="t@t" -c user.name="T" commit --allow-empty -m "init" -q
  git -C "$remote_repo" -c user.email="t@t" -c user.name="T" commit --allow-empty -m "new feature" -q

  # Clone it as the framework dir
  git clone -q "$remote_repo" "$mock_fw/.git_tmp"
  mv "$mock_fw/.git_tmp/.git" "$mock_fw/.git"
  rm -rf "$mock_fw/.git_tmp"

  # Reset local to be 1 commit behind
  git -C "$mock_fw" reset --hard HEAD~1 -q

  # The update flow will show pending changes but then prompt for confirmation
  # which we can't answer — it will fail on the read, but we can verify the output
  run bash -c 'bash "'"$mock_fw"'/lib/update/update.sh" "'"$mock_fw"'" 2>&1 < /dev/null' || true
  [[ "$output" == *"update(s) available"* ]] || [[ "$output" == *"new feature"* ]]
}

@test "update requires FRAMEWORK_DIR" {
  run bash "$FRAMEWORK_DIR/lib/update/update.sh" ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"FRAMEWORK_DIR required"* ]]
}

@test "update fails when not a git repo" {
  local mock_fw="$TEST_DIR/notgit"
  mkdir -p "$mock_fw/lib/update"
  cp "$FRAMEWORK_DIR/lib/update/update.sh" "$mock_fw/lib/update/update.sh"
  cp -r "$FRAMEWORK_DIR/lib/log" "$mock_fw/lib/log"
  run bash "$mock_fw/lib/update/update.sh" "$mock_fw"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a git repository"* ]]
}

@test "setup module.yaml uses portable paths" {
  CFGD_VERSIONING="true" \
  PROMPT="false" \
  bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
    "$TEST_DIR/portable" "$FRAMEWORK_DIR" "mytools" "0.1.0" "minimal"
  # Should use ~/.local/share paths, not absolute machine paths
  grep -q "~/.local/share/clift" "$TEST_DIR/portable/module.yaml"
  grep -q "~/.local/share/mytools" "$TEST_DIR/portable/module.yaml"
}
