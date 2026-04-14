#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

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
  # Mock cfgd so the code path is always exercised
  mkdir -p "$TEST_DIR/bin"
  echo '#!/bin/sh' > "$TEST_DIR/bin/cfgd"
  chmod +x "$TEST_DIR/bin/cfgd"
  export PATH="$TEST_DIR/bin:$PATH"

  run bash "$FRAMEWORK_DIR/lib/version/version.sh" "$CLI_DIR" "$FRAMEWORK_DIR" 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == *"Managed by cfgd"* ]]
}

# --- upgrade.sh ---

@test "upgrade fails without versioning enabled" {
  unset CFGD_VERSIONING
  run bash "$FRAMEWORK_DIR/lib/version/upgrade.sh" "$CLI_DIR" "$FRAMEWORK_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not set up"* ]]
}

@test "upgrade invokes cfgd module upgrade and reports success" {
  export CFGD_VERSIONING=true
  # Mock a cfgd that records invocations and succeeds
  mkdir -p "$TEST_DIR/bin"
  cat > "$TEST_DIR/bin/cfgd" <<SH
#!/bin/sh
echo "cfgd \$*" > "$TEST_DIR/cfgd.log"
exit 0
SH
  chmod +x "$TEST_DIR/bin/cfgd"
  export PATH="$TEST_DIR/bin:$PATH"

  run bash "$FRAMEWORK_DIR/lib/version/upgrade.sh" "$CLI_DIR" "$FRAMEWORK_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Upgrade complete"* ]]
  [[ "$output" == *"cfgd apply"* ]]
  run cat "$TEST_DIR/cfgd.log"
  [[ "$output" == *"module upgrade testcli"* ]]
}

@test "upgrade dies when cfgd upgrade fails" {
  export CFGD_VERSIONING=true
  mkdir -p "$TEST_DIR/bin"
  cat > "$TEST_DIR/bin/cfgd" <<'SH'
#!/bin/sh
exit 2
SH
  chmod +x "$TEST_DIR/bin/cfgd"
  export PATH="$TEST_DIR/bin:$PATH"

  run bash "$FRAMEWORK_DIR/lib/version/upgrade.sh" "$CLI_DIR" "$FRAMEWORK_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Upgrade failed"* ]]
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

@test "version requires CLI_DIR and FRAMEWORK_DIR" {
  run bash "$FRAMEWORK_DIR/lib/version/version.sh" "" ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"required"* ]]
}

@test "version shows cfgd not installed warning when versioning enabled" {
  export CFGD_VERSIONING=true
  # Ensure cfgd is NOT on PATH by using a restricted PATH
  # that still includes jq/yq but not cfgd
  run bash -c '
    export CFGD_VERSIONING=true CLI_NAME=testcli CLI_VERSION=1.0.0
    # Remove any mock cfgd from PATH — only keep system dirs
    export PATH="/usr/bin:/bin:/usr/local/bin"
    bash "$FRAMEWORK_DIR/lib/version/version.sh" "$CLI_DIR" "$FRAMEWORK_DIR" 2>&1
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"cfgd not installed"* ]]
}

@test "version shows cfgd versioning enabled but not applied" {
  export CFGD_VERSIONING=true
  # Mock cfgd
  mkdir -p "$TEST_DIR/bin"
  echo '#!/bin/sh' > "$TEST_DIR/bin/cfgd"
  chmod +x "$TEST_DIR/bin/cfgd"
  export PATH="$TEST_DIR/bin:$PATH"

  run bash "$FRAMEWORK_DIR/lib/version/version.sh" "$CLI_DIR" "$FRAMEWORK_DIR" 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == *"versioning enabled"* ]]
}

@test "upgrade requires CLI_DIR and FRAMEWORK_DIR" {
  run bash "$FRAMEWORK_DIR/lib/version/upgrade.sh" "" ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"required"* ]]
}

@test "set requires CLI_DIR and FRAMEWORK_DIR" {
  run bash "$FRAMEWORK_DIR/lib/version/set.sh" "" ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"required"* ]]
}

@test "version/setup.sh standalone mode configures module.yaml" {
  mkdir -p "$TEST_DIR/standcli"
  cat > "$TEST_DIR/standcli/.clift.yaml" <<'YAML'
name: standcli
version: 0.1.0
YAML
  cat > "$TEST_DIR/standcli/.env" <<'ENV'
CLI_NAME=standcli
CLI_VERSION=0.1.0
ENV
  cat > "$TEST_DIR/standcli/Taskfile.yaml" <<'YAML'
version: '3'
includes:
  # User commands
tasks:
  default:
    desc: "Show help"
  version:
    desc: "Print version"
    cmd: echo "standcli version 0.1.0"
YAML

  # Mock cfgd
  mkdir -p "$TEST_DIR/bin"
  echo '#!/bin/sh' > "$TEST_DIR/bin/cfgd"
  chmod +x "$TEST_DIR/bin/cfgd"
  export PATH="$TEST_DIR/bin:$PATH"

  # Init a git repo so _set_git_source can find a remote
  git -C "$TEST_DIR/standcli" init -q
  git -C "$TEST_DIR/standcli" -c user.email="t@t" -c user.name="T" commit --allow-empty -m "init" -q

  CLI_NAME=standcli CLI_VERSION=0.1.0 \
    run bash "$FRAMEWORK_DIR/lib/version/setup.sh" "$TEST_DIR/standcli" "$FRAMEWORK_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Standalone module configured"* ]]
  # CFGD_VERSIONING should be set in .env
  grep -q "CFGD_VERSIONING=true" "$TEST_DIR/standcli/.env"
}

@test "version/setup.sh updates existing CFGD_VERSIONING line in .env" {
  mkdir -p "$TEST_DIR/updcli"
  cat > "$TEST_DIR/updcli/.clift.yaml" <<'YAML'
name: updcli
version: 0.1.0
YAML
  cat > "$TEST_DIR/updcli/.env" <<'ENV'
CLI_NAME=updcli
CFGD_VERSIONING=false
ENV
  cat > "$TEST_DIR/updcli/Taskfile.yaml" <<'YAML'
version: '3'
includes:
  # User commands
tasks:
  default:
    desc: "Show help"
  version:
    desc: "Print version"
    cmd: echo "updcli version 0.1.0"
YAML

  mkdir -p "$TEST_DIR/bin"
  echo '#!/bin/sh' > "$TEST_DIR/bin/cfgd"
  chmod +x "$TEST_DIR/bin/cfgd"
  export PATH="$TEST_DIR/bin:$PATH"

  CLI_NAME=updcli CLI_VERSION=0.1.0 \
    run bash "$FRAMEWORK_DIR/lib/version/setup.sh" "$TEST_DIR/updcli" "$FRAMEWORK_DIR"
  [ "$status" -eq 0 ]
  # Should have updated the existing line, not appended a second
  [ "$(grep -c 'CFGD_VERSIONING' "$TEST_DIR/updcli/.env")" -eq 1 ]
  grep -q "CFGD_VERSIONING=true" "$TEST_DIR/updcli/.env"
}

@test "version/setup.sh injects version include before tasks: when no User commands marker" {
  mkdir -p "$TEST_DIR/nomkr"
  cat > "$TEST_DIR/nomkr/.clift.yaml" <<'YAML'
name: nomkr
version: 0.1.0
YAML
  cat > "$TEST_DIR/nomkr/.env" <<'ENV'
CLI_NAME=nomkr
ENV
  cat > "$TEST_DIR/nomkr/Taskfile.yaml" <<'YAML'
version: '3'
includes:
tasks:
  default:
    desc: "Show help"
  version:
    desc: "Print version"
    cmd: echo "nomkr version 0.1.0"
YAML

  mkdir -p "$TEST_DIR/bin"
  echo '#!/bin/sh' > "$TEST_DIR/bin/cfgd"
  chmod +x "$TEST_DIR/bin/cfgd"
  export PATH="$TEST_DIR/bin:$PATH"

  CLI_NAME=nomkr CLI_VERSION=0.1.0 \
    run bash "$FRAMEWORK_DIR/lib/version/setup.sh" "$TEST_DIR/nomkr" "$FRAMEWORK_DIR"
  [ "$status" -eq 0 ]
  grep -q "lib/version" "$TEST_DIR/nomkr/Taskfile.yaml"
}

@test "set uses cli-name/version ref convention" {
  export CFGD_VERSIONING=true
  # Mock cfgd that always fails (no real version to pin)
  mkdir -p "$TEST_DIR/bin"
  cat > "$TEST_DIR/bin/cfgd" <<'SH'
#!/bin/sh
echo "mock-cfgd: $*"
exit 1
SH
  chmod +x "$TEST_DIR/bin/cfgd"
  export PATH="$TEST_DIR/bin:$PATH"

  run bash "$FRAMEWORK_DIR/lib/version/set.sh" "$CLI_DIR" "$FRAMEWORK_DIR" "v1.0.0" 2>&1
  [ "$status" -ne 0 ]
  # The mock should receive the ref with cli-name prefix
  [[ "$output" == *"testcli/v1.0.0"* ]]
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

@test "version/setup.sh requires CLI_DIR and FRAMEWORK_DIR" {
  run bash "$FRAMEWORK_DIR/lib/version/setup.sh" "" ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"required"* ]]
}

@test "version/setup.sh dies when .clift.yaml has no name" {
  mkdir -p "$TEST_DIR/noname"
  echo "version: 0.1.0" > "$TEST_DIR/noname/.clift.yaml"
  echo "CLI_VERSION=0.1.0" > "$TEST_DIR/noname/.env"

  unset CLI_NAME
  run bash "$FRAMEWORK_DIR/lib/version/setup.sh" "$TEST_DIR/noname" "$FRAMEWORK_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Could not determine CLI name"* ]]
}

@test "version/setup.sh standalone mode logs remote when git origin is set" {
  mkdir -p "$TEST_DIR/remotecli"
  cat > "$TEST_DIR/remotecli/.clift.yaml" <<'YAML'
name: remotecli
version: 0.1.0
YAML
  cat > "$TEST_DIR/remotecli/.env" <<'ENV'
CLI_NAME=remotecli
CLI_VERSION=0.1.0
ENV
  cat > "$TEST_DIR/remotecli/Taskfile.yaml" <<'YAML'
version: '3'
includes:
  # User commands
tasks:
  default:
    desc: "Show help"
YAML
  git -C "$TEST_DIR/remotecli" init -q
  git -C "$TEST_DIR/remotecli" remote add origin "https://example.com/remotecli.git"

  mkdir -p "$TEST_DIR/bin"
  echo '#!/bin/sh' > "$TEST_DIR/bin/cfgd"
  chmod +x "$TEST_DIR/bin/cfgd"
  export PATH="$TEST_DIR/bin:$PATH"

  CLI_NAME=remotecli CLI_VERSION=0.1.0 \
    run bash "$FRAMEWORK_DIR/lib/version/setup.sh" "$TEST_DIR/remotecli" "$FRAMEWORK_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Module configured with remote"* ]]
  # yq injection via strenv should populate the source field with the remote URL
  run yq '.spec.files[0].source' "$TEST_DIR/remotecli/module.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"example.com/remotecli.git"* ]]
}

@test "version/setup.sh warns when a CFGD_PROFILES entry does not exist" {
  mkdir -p "$TEST_DIR/missprofcli"
  cat > "$TEST_DIR/missprofcli/.clift.yaml" <<'YAML'
name: missprofcli
version: 0.1.0
YAML
  cat > "$TEST_DIR/missprofcli/.env" <<'ENV'
CLI_NAME=missprofcli
ENV
  cat > "$TEST_DIR/missprofcli/Taskfile.yaml" <<'YAML'
version: '3'
includes:
  # User commands
tasks:
  default:
    desc: "Show help"
YAML
  mkdir -p "$TEST_DIR/cfgd-config/modules"
  mkdir -p "$TEST_DIR/cfgd-config/profiles"

  mkdir -p "$TEST_DIR/bin"
  echo '#!/bin/sh' > "$TEST_DIR/bin/cfgd"
  chmod +x "$TEST_DIR/bin/cfgd"
  export PATH="$TEST_DIR/bin:$PATH"

  CLI_NAME=missprofcli CLI_VERSION=0.1.0 \
  CFGD_CONFIG_DIR="$TEST_DIR/cfgd-config" \
  CFGD_PROFILES="ghost" \
    run bash "$FRAMEWORK_DIR/lib/version/setup.sh" "$TEST_DIR/missprofcli" "$FRAMEWORK_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Profile not found"* ]]
  [[ "$output" == *"ghost"* ]]
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
