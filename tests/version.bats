#!/usr/bin/env bats

load test_helper

# --- version.sh ---

@test "version shows CLI name and version" {
  run bash "$FRAMEWORK_DIR/lib/version/version.sh" "$CLI_DIR" "$FRAMEWORK_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"testcli version 1.0.0"* ]]
}

@test "version shows cfgd status when versioning enabled" {
  export CFGD_VERSIONING=true
  run bash "$FRAMEWORK_DIR/lib/version/version.sh" "$CLI_DIR" "$FRAMEWORK_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"testcli version 1.0.0"* ]]
  # Should show cfgd status (either installed or not)
  [[ "$output" == *"cfgd"* ]]
}

@test "version hides cfgd status when versioning not enabled" {
  unset CFGD_VERSIONING
  run bash "$FRAMEWORK_DIR/lib/version/version.sh" "$CLI_DIR" "$FRAMEWORK_DIR"
  [ "$status" -eq 0 ]
  # Only the version line, no cfgd info
  [ "$(echo "$output" | wc -l)" -eq 1 ]
}

@test "version shows managed status with .cfgd-managed marker" {
  export CFGD_VERSIONING=true
  touch "$CLI_DIR/.cfgd-managed"
  # Only shows "Managed by cfgd" if cfgd binary exists
  if command -v cfgd &>/dev/null; then
    run bash "$FRAMEWORK_DIR/lib/version/version.sh" "$CLI_DIR" "$FRAMEWORK_DIR"
    [[ "$output" == *"Managed by cfgd"* ]]
  fi
}

# --- upgrade.sh ---

@test "upgrade fails without versioning enabled" {
  unset CFGD_VERSIONING
  run bash "$FRAMEWORK_DIR/lib/version/upgrade.sh" "$CLI_DIR" "$FRAMEWORK_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not set up"* ]]
}

@test "upgrade fails without cfgd installed" {
  export CFGD_VERSIONING=true
  export PATH="/usr/bin:/bin"
  run bash "$FRAMEWORK_DIR/lib/version/upgrade.sh" "$CLI_DIR" "$FRAMEWORK_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not installed"* ]]
}

# --- set.sh ---

@test "set fails without versioning enabled" {
  unset CFGD_VERSIONING
  run bash "$FRAMEWORK_DIR/lib/version/set.sh" "$CLI_DIR" "$FRAMEWORK_DIR" "v1.0.0"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not set up"* ]]
}

@test "set fails without version argument" {
  export CFGD_VERSIONING=true
  # Mock cfgd as available
  mkdir -p "$TEST_DIR/bin"
  echo '#!/bin/sh' > "$TEST_DIR/bin/cfgd"
  chmod +x "$TEST_DIR/bin/cfgd"
  export PATH="$TEST_DIR/bin:$PATH"

  run bash "$FRAMEWORK_DIR/lib/version/set.sh" "$CLI_DIR" "$FRAMEWORK_DIR" ""
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage"* ]]
}

@test "set fails without cfgd installed" {
  export CFGD_VERSIONING=true
  export PATH="/usr/bin:/bin"
  run bash "$FRAMEWORK_DIR/lib/version/set.sh" "$CLI_DIR" "$FRAMEWORK_DIR" "v1.0.0"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not installed"* ]]
}

# --- setup.sh (Taskfile modification) ---

@test "setup adds version include to Taskfile" {
  # Create a minimal CLI
  mkdir -p "$TEST_DIR/setupcli"
  cat > "$TEST_DIR/setupcli/.clift.yaml" <<'YAML'
name: setupcli
version: 0.1.0
YAML
  cat > "$TEST_DIR/setupcli/.env" <<'ENV'
CLI_NAME=setupcli
CLI_VERSION=0.1.0
ENV
  cat > "$TEST_DIR/setupcli/Taskfile.yaml" <<'YAML'
version: '3'

includes:
  completion:
    taskfile: '{{.FRAMEWORK_DIR}}/lib/completion'

  # User commands (added by scaffolder)

tasks:
  default:
    desc: "Show help"

  version:
    desc: "Print version"
    cmd: echo "setupcli version 0.1.0"
YAML

  # Mock cfgd
  mkdir -p "$TEST_DIR/bin"
  echo '#!/bin/sh' > "$TEST_DIR/bin/cfgd"
  chmod +x "$TEST_DIR/bin/cfgd"
  export PATH="$TEST_DIR/bin:$PATH"

  CLI_NAME=setupcli CLI_VERSION=0.1.0 \
    run bash "$FRAMEWORK_DIR/lib/version/setup.sh" "$TEST_DIR/setupcli" "$FRAMEWORK_DIR"
  [ "$status" -eq 0 ]

  # Version include should be added
  run grep "lib/version" "$TEST_DIR/setupcli/Taskfile.yaml"
  [ "$status" -eq 0 ]

  # Simple version task should be removed
  run grep "Print version" "$TEST_DIR/setupcli/Taskfile.yaml"
  [ "$status" -ne 0 ]

  # CFGD_VERSIONING should be set in .env
  run grep "CFGD_VERSIONING=true" "$TEST_DIR/setupcli/.env"
  [ "$status" -eq 0 ]
}

@test "setup skips if already configured" {
  export CFGD_VERSIONING=true
  export CLI_NAME=testcli

  run bash "$FRAMEWORK_DIR/lib/version/setup.sh" "$CLI_DIR" "$FRAMEWORK_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already configured"* ]]
}

@test "setup copies module to CFGD_CONFIG_DIR when set" {
  # Create CLI with module.yaml
  mkdir -p "$TEST_DIR/teamcli"
  cat > "$TEST_DIR/teamcli/.clift.yaml" <<'YAML'
name: teamcli
version: 0.1.0
YAML
  cat > "$TEST_DIR/teamcli/.env" <<'ENV'
CLI_NAME=teamcli
ENV
  cat > "$TEST_DIR/teamcli/Taskfile.yaml" <<'YAML'
version: '3'
includes:
  # User commands (added by scaffolder)
tasks:
  default:
    desc: "Show help"
  version:
    desc: "Print version"
    cmd: echo "teamcli version 0.1.0"
YAML
  sed -e "s|%%CLI_NAME%%|teamcli|g" \
    "$FRAMEWORK_DIR/templates/cli/module.yaml.tmpl" > "$TEST_DIR/teamcli/module.yaml"

  # Create cfgd config dir
  mkdir -p "$TEST_DIR/cfgd-config/modules"

  # Mock cfgd
  mkdir -p "$TEST_DIR/bin"
  echo '#!/bin/sh' > "$TEST_DIR/bin/cfgd"
  chmod +x "$TEST_DIR/bin/cfgd"
  export PATH="$TEST_DIR/bin:$PATH"

  CLI_NAME=teamcli CLI_VERSION=0.1.0 \
  CFGD_CONFIG_DIR="$TEST_DIR/cfgd-config" \
    run bash "$FRAMEWORK_DIR/lib/version/setup.sh" "$TEST_DIR/teamcli" "$FRAMEWORK_DIR"
  [ "$status" -eq 0 ]

  # Module should be copied to cfgd config
  [ -f "$TEST_DIR/cfgd-config/modules/teamcli/module.yaml" ]
  run grep "name: teamcli" "$TEST_DIR/cfgd-config/modules/teamcli/module.yaml"
  [ "$status" -eq 0 ]
}

@test "setup adds module to cfgd profiles when CFGD_PROFILES set" {
  mkdir -p "$TEST_DIR/profilecli"
  cat > "$TEST_DIR/profilecli/.clift.yaml" <<'YAML'
name: profilecli
version: 0.1.0
YAML
  cat > "$TEST_DIR/profilecli/.env" <<'ENV'
CLI_NAME=profilecli
ENV
  cat > "$TEST_DIR/profilecli/Taskfile.yaml" <<'YAML'
version: '3'
includes:
  # User commands (added by scaffolder)
tasks:
  default:
    desc: "Show help"
  version:
    desc: "Print version"
    cmd: echo "profilecli version 0.1.0"
YAML

  # Create cfgd config with profiles
  mkdir -p "$TEST_DIR/cfgd-config/modules"
  mkdir -p "$TEST_DIR/cfgd-config/profiles"
  cat > "$TEST_DIR/cfgd-config/profiles/dev.yaml" <<'YAML'
apiVersion: cfgd.io/v1alpha1
kind: Profile
spec:
  modules: []
YAML

  # Mock cfgd
  mkdir -p "$TEST_DIR/bin"
  echo '#!/bin/sh' > "$TEST_DIR/bin/cfgd"
  chmod +x "$TEST_DIR/bin/cfgd"
  export PATH="$TEST_DIR/bin:$PATH"

  CLI_NAME=profilecli CLI_VERSION=0.1.0 \
  CFGD_CONFIG_DIR="$TEST_DIR/cfgd-config" \
  CFGD_PROFILES="dev" \
    run bash "$FRAMEWORK_DIR/lib/version/setup.sh" "$TEST_DIR/profilecli" "$FRAMEWORK_DIR"
  [ "$status" -eq 0 ]

  # Profile should contain the module
  run yq '.spec.modules[]' "$TEST_DIR/cfgd-config/profiles/dev.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"profilecli"* ]]
}

@test "setup fails with nonexistent CFGD_CONFIG_DIR" {
  mkdir -p "$TEST_DIR/badcli"
  cat > "$TEST_DIR/badcli/.clift.yaml" <<'YAML'
name: badcli
version: 0.1.0
YAML
  cat > "$TEST_DIR/badcli/.env" <<'ENV'
CLI_NAME=badcli
ENV

  # Mock cfgd
  mkdir -p "$TEST_DIR/bin"
  echo '#!/bin/sh' > "$TEST_DIR/bin/cfgd"
  chmod +x "$TEST_DIR/bin/cfgd"
  export PATH="$TEST_DIR/bin:$PATH"

  CLI_NAME=badcli CLI_VERSION=0.1.0 \
  CFGD_CONFIG_DIR="$TEST_DIR/no_such_cfgd_config_dir" \
    run bash "$FRAMEWORK_DIR/lib/version/setup.sh" "$TEST_DIR/badcli" "$FRAMEWORK_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}
