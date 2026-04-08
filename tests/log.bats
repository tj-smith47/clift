#!/usr/bin/env bats

load test_helper

@test "log_info outputs message to stdout" {
  source "$FRAMEWORK_DIR/lib/log/log.sh"
  run log_info "hello world"
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello world"* ]]
}

@test "log_warn outputs to stderr" {
  source "$FRAMEWORK_DIR/lib/log/log.sh"
  run bash -c 'source "$FRAMEWORK_DIR/lib/log/log.sh"; log_warn "danger" 2>&1'
  [ "$status" -eq 0 ]
  [[ "$output" == *"danger"* ]]
}

@test "log_warn goes to stderr not stdout" {
  source "$FRAMEWORK_DIR/lib/log/log.sh"
  run bash -c 'source "$FRAMEWORK_DIR/lib/log/log.sh"; log_warn "danger" 2>/dev/null'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "log_error outputs to stderr" {
  source "$FRAMEWORK_DIR/lib/log/log.sh"
  run bash -c 'source "$FRAMEWORK_DIR/lib/log/log.sh"; log_error "broken" 2>&1'
  [ "$status" -eq 0 ]
  [[ "$output" == *"broken"* ]]
}

@test "log_error goes to stderr not stdout" {
  source "$FRAMEWORK_DIR/lib/log/log.sh"
  run bash -c 'source "$FRAMEWORK_DIR/lib/log/log.sh"; log_error "broken" 2>/dev/null'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "log_success outputs to stdout" {
  source "$FRAMEWORK_DIR/lib/log/log.sh"
  run log_success "done"
  [ "$status" -eq 0 ]
  [[ "$output" == *"done"* ]]
}

@test "log_debug is silent without VERBOSE" {
  export VERBOSE=""
  source "$FRAMEWORK_DIR/lib/log/log.sh"
  run bash -c 'source "$FRAMEWORK_DIR/lib/log/log.sh"; log_debug "hidden" 2>&1'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "log_debug outputs when VERBOSE=true" {
  export VERBOSE=true
  source "$FRAMEWORK_DIR/lib/log/log.sh"
  run bash -c 'export VERBOSE=true; source "$FRAMEWORK_DIR/lib/log/log.sh"; log_debug "visible" 2>&1'
  [ "$status" -eq 0 ]
  [[ "$output" == *"visible"* ]]
}

@test "QUIET=true suppresses log_info" {
  export QUIET=true
  source "$FRAMEWORK_DIR/lib/log/log.sh"
  run log_info "silenced"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "QUIET=true suppresses log_success" {
  export QUIET=true
  source "$FRAMEWORK_DIR/lib/log/log.sh"
  run log_success "silenced"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "NO_COLOR=1 strips ANSI codes" {
  run bash -c 'export NO_COLOR=1 LOG_THEME=minimal-color; source "$FRAMEWORK_DIR/lib/log/log.sh"; log_info "plain"'
  [ "$status" -eq 0 ]
  # Should not contain escape sequences
  [[ ! "$output" =~ $'\033' ]]
  [[ "$output" == *"plain"* ]]
}

@test "die exits with correct code" {
  source "$FRAMEWORK_DIR/lib/log/log.sh"
  run bash -c 'source "$FRAMEWORK_DIR/lib/log/log.sh"; die "fatal" 42'
  [ "$status" -eq 42 ]
}

@test "die defaults to exit code 1" {
  source "$FRAMEWORK_DIR/lib/log/log.sh"
  run bash -c 'source "$FRAMEWORK_DIR/lib/log/log.sh"; die "fatal"'
  [ "$status" -eq 1 ]
}

@test "exit code constants are exported" {
  source "$FRAMEWORK_DIR/lib/log/log.sh"
  [ "$EXIT_OK" -eq 0 ]
  [ "$EXIT_ERROR" -eq 1 ]
  [ "$EXIT_USAGE" -eq 2 ]
  [ "$EXIT_NOT_FOUND" -eq 127 ]
}
