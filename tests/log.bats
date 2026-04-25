#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load test_helper

@test "log_info outputs message to stderr" {
  source "$FRAMEWORK_DIR/lib/log/log.sh"
  run --separate-stderr log_info "hello world"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"hello world"* ]]
  [ -z "$output" ]
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

@test "log_success outputs to stderr" {
  source "$FRAMEWORK_DIR/lib/log/log.sh"
  run --separate-stderr log_success "done"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"done"* ]]
  [ -z "$output" ]
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

@test "log_suggest outputs to stderr" {
  run bash -c 'source "$FRAMEWORK_DIR/lib/log/log.sh"; log_suggest "hint text" 2>&1'
  [ "$status" -eq 0 ]
  [[ "$output" == *"hint text"* ]]
}

@test "log_suggest suppressed by stdout redirect (stderr only)" {
  run bash -c 'source "$FRAMEWORK_DIR/lib/log/log.sh"; log_suggest "hint text" 2>/dev/null'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "QUIET=true suppresses log_suggest" {
  run bash -c 'export QUIET=true; source "$FRAMEWORK_DIR/lib/log/log.sh"; log_suggest "quiet hint" 2>&1'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "custom theme respects LOG_FMT_INFO format string" {
  run bash -c 'export LOG_THEME=custom LOG_FMT_INFO="[CUSTOM] %s" LOG_COLOR=false; source "$FRAMEWORK_DIR/lib/log/log.sh"; log_info "test msg"'
  [ "$status" -eq 0 ]
  [[ "$output" == "[CUSTOM] test msg" ]]
}

@test "brackets theme uses [INFO] prefix" {
  run bash -c 'export LOG_THEME=brackets; source "$FRAMEWORK_DIR/lib/log/log.sh"; log_info "msg"'
  [ "$status" -eq 0 ]
  [[ "$output" == "[INFO] msg" ]]
}

@test "minimal theme outputs bare message for info" {
  run bash -c 'export LOG_THEME=minimal; source "$FRAMEWORK_DIR/lib/log/log.sh"; log_info "bare"'
  [ "$status" -eq 0 ]
  [ "$output" = "bare" ]
}

@test "NO_COLOR=1 strips ANSI from all color themes" {
  for theme in icons-color brackets-color minimal-color; do
    run bash -c "export NO_COLOR=1 LOG_THEME=$theme; source \"\$FRAMEWORK_DIR/lib/log/log.sh\"; log_info 'test'"
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ $'\033' ]]
  done
}

@test "log message with percent signs does not crash printf" {
  run bash -c 'export LOG_THEME=icons-color; source "$FRAMEWORK_DIR/lib/log/log.sh"; log_info "100% complete"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"100% complete"* ]]
}

@test "icons theme uses arrow prefix for info" {
  run bash -c 'export LOG_THEME=icons; source "$FRAMEWORK_DIR/lib/log/log.sh"; log_info "msg"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"→"* ]]
  [[ "$output" == *"msg"* ]]
}

@test "icons-color theme includes ANSI codes" {
  run bash -c 'export LOG_THEME=icons-color; source "$FRAMEWORK_DIR/lib/log/log.sh"; log_info "colortest"'
  [ "$status" -eq 0 ]
  [[ "$output" =~ $'\033' ]]
  [[ "$output" == *"colortest"* ]]
}

@test "brackets-color theme includes ANSI codes" {
  run bash -c 'export LOG_THEME=brackets-color; source "$FRAMEWORK_DIR/lib/log/log.sh"; log_info "colortest"'
  [ "$status" -eq 0 ]
  [[ "$output" =~ $'\033' ]]
  [[ "$output" == *"colortest"* ]]
}

@test "minimal-color theme includes ANSI codes" {
  run bash -c 'export LOG_THEME=minimal-color; source "$FRAMEWORK_DIR/lib/log/log.sh"; log_info "colortest"'
  [ "$status" -eq 0 ]
  [[ "$output" =~ $'\033' ]]
  [[ "$output" == *"colortest"* ]]
}

@test "custom theme with LOG_COLOR=false skips color" {
  run bash -c 'export LOG_THEME=custom LOG_FMT_INFO=">> %s" LOG_COLOR=false; source "$FRAMEWORK_DIR/lib/log/log.sh"; log_info "noclr"'
  [ "$status" -eq 0 ]
  [[ "$output" == ">> noclr" ]]
  [[ ! "$output" =~ $'\033' ]]
}

@test "custom theme with LOG_COLOR=true adds color" {
  run bash -c 'export LOG_THEME=custom LOG_FMT_INFO=">> %s" LOG_COLOR=true; source "$FRAMEWORK_DIR/lib/log/log.sh"; log_info "clr"'
  [ "$status" -eq 0 ]
  [[ "$output" == *">> clr"* ]]
  [[ "$output" =~ $'\033' ]]
}

@test "LOG_CLR_INFO override changes info color" {
  run bash -c 'export LOG_THEME=icons-color LOG_CLR_INFO="\033[0;35m"; source "$FRAMEWORK_DIR/lib/log/log.sh"; log_info "purple"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"purple"* ]]
}

@test "unknown theme falls back to level: message format" {
  run bash -c 'export LOG_THEME=bogus; source "$FRAMEWORK_DIR/lib/log/log.sh"; log_info "fallback"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"info: fallback"* ]]
}

@test "log_warn with brackets theme shows [WARN]" {
  run bash -c 'export LOG_THEME=brackets; source "$FRAMEWORK_DIR/lib/log/log.sh"; log_warn "oops" 2>&1'
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN]"* ]]
  [[ "$output" == *"oops"* ]]
}

@test "log_error with brackets theme shows [ERROR]" {
  run bash -c 'export LOG_THEME=brackets; source "$FRAMEWORK_DIR/lib/log/log.sh"; log_error "bad" 2>&1'
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ERROR]"* ]]
}

@test "log_success with brackets theme shows [OK]" {
  run bash -c 'export LOG_THEME=brackets; source "$FRAMEWORK_DIR/lib/log/log.sh"; log_success "done"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"[OK]"* ]]
}

@test "log_debug with brackets theme shows [DEBUG]" {
  run bash -c 'export LOG_THEME=brackets VERBOSE=true; source "$FRAMEWORK_DIR/lib/log/log.sh"; log_debug "trace" 2>&1'
  [ "$status" -eq 0 ]
  [[ "$output" == *"[DEBUG]"* ]]
}

@test "minimal theme warn prefix" {
  run bash -c 'export LOG_THEME=minimal; source "$FRAMEWORK_DIR/lib/log/log.sh"; log_warn "careful" 2>&1'
  [ "$status" -eq 0 ]
  [[ "$output" == "warn: careful" ]]
}

@test "minimal theme error prefix" {
  run bash -c 'export LOG_THEME=minimal; source "$FRAMEWORK_DIR/lib/log/log.sh"; log_error "broke" 2>&1'
  [ "$status" -eq 0 ]
  [[ "$output" == "error: broke" ]]
}

@test "custom theme LOG_FMT_WARN format string" {
  run bash -c 'export LOG_THEME=custom LOG_FMT_WARN="!! %s" LOG_COLOR=false; source "$FRAMEWORK_DIR/lib/log/log.sh"; log_warn "danger" 2>&1'
  [ "$status" -eq 0 ]
  [[ "$output" == "!! danger" ]]
}

@test "custom theme LOG_FMT_ERROR format string" {
  run bash -c 'export LOG_THEME=custom LOG_FMT_ERROR="** %s" LOG_COLOR=false; source "$FRAMEWORK_DIR/lib/log/log.sh"; log_error "fatal" 2>&1'
  [ "$status" -eq 0 ]
  [[ "$output" == "** fatal" ]]
}

@test "custom theme LOG_FMT_SUCCESS format string" {
  run bash -c 'export LOG_THEME=custom LOG_FMT_SUCCESS="+++ %s" LOG_COLOR=false; source "$FRAMEWORK_DIR/lib/log/log.sh"; log_success "ok"'
  [ "$status" -eq 0 ]
  [[ "$output" == "+++ ok" ]]
}

@test "custom theme LOG_FMT_DEBUG format string" {
  run bash -c 'export LOG_THEME=custom LOG_FMT_DEBUG=".. %s" LOG_COLOR=false VERBOSE=true; source "$FRAMEWORK_DIR/lib/log/log.sh"; log_debug "trace" 2>&1'
  [ "$status" -eq 0 ]
  [[ "$output" == ".. trace" ]]
}

@test "icons-color warn uses yellow prefix" {
  run bash -c 'export LOG_THEME=icons-color; source "$FRAMEWORK_DIR/lib/log/log.sh"; log_warn "oops" 2>&1'
  [ "$status" -eq 0 ]
  [[ "$output" == *"oops"* ]]
  [[ "$output" =~ $'\033' ]]
}

@test "icons-color debug uses cyan prefix when VERBOSE" {
  run bash -c 'export LOG_THEME=icons-color VERBOSE=true; source "$FRAMEWORK_DIR/lib/log/log.sh"; log_debug "dbg" 2>&1'
  [ "$status" -eq 0 ]
  [[ "$output" == *"dbg"* ]]
}

@test "custom theme warn/error/success/debug with color" {
  for level_func_fmt in "log_warn:LOG_FMT_WARN:!! %s" "log_error:LOG_FMT_ERROR:** %s" "log_success:LOG_FMT_SUCCESS:++ %s" "log_debug:LOG_FMT_DEBUG:.. %s"; do
    IFS=: read -r func var fmt <<< "$level_func_fmt"
    extra=""
    [[ "$func" == "log_debug" ]] && extra="VERBOSE=true"
    redir=""
    [[ "$func" == "log_warn" || "$func" == "log_error" || "$func" == "log_debug" ]] && redir="2>&1"
    run bash -c "export LOG_THEME=custom ${var}='${fmt}' LOG_COLOR=true ${extra}; source \"\$FRAMEWORK_DIR/lib/log/log.sh\"; ${func} 'test' ${redir}"
    [ "$status" -eq 0 ]
    [[ "$output" =~ $'\033' ]]
  done
}
