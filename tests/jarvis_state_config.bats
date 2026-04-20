#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load jarvis_helper

setup() {
  jarvis_common_setup
  source "$CLIFT_JARVIS_DIR/lib/state/profile.sh"
  source "$CLIFT_JARVIS_DIR/lib/state/config.sh"
  state_ensure_tree
  cat > "$JARVIS_HOME/test/config.toml" <<'EOF'
[notify]
default = "local,gotify"

[notify.slack]
webhook_url = "https://hooks.example/abc"

[calendar]
provider = "gcalcli"
EOF
}
teardown() { jarvis_common_teardown; }

@test "config_get returns scalar by dotted key" {
  run config_get notify.default ""
  [ "$status" -eq 0 ]
  [ "$output" = "local,gotify" ]
}

@test "config_get returns nested scalar" {
  run config_get notify.slack.webhook_url ""
  [ "$status" -eq 0 ]
  [ "$output" = "https://hooks.example/abc" ]
}

@test "config_get returns default when key missing" {
  run config_get notify.email.from "unset@example.com"
  [ "$status" -eq 0 ]
  [ "$output" = "unset@example.com" ]
}

@test "config_get returns default when config.toml missing" {
  rm "$JARVIS_HOME/test/config.toml"
  run config_get notify.default "none"
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
}
