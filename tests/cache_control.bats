#!/usr/bin/env bats
# Tests for Task 4.1: --no-cache flag + CLIFT_CACHE=rebuild|bypass env var.
# Covers the cache control override surface: wrapper argv scan, cache.sh
# short-circuits, graceful degradation, and help rendering.

bats_require_minimum_version 1.5.0
load test_helper

setup() { common_setup; }
teardown() { common_teardown; }

_mtime() {
  stat -c '%Y' "$1" 2>/dev/null || stat -f '%m' "$1"
}

@test "CLIFT_CACHE=rebuild forces rebuild even when cache is fresh" {
  source "$FRAMEWORK_DIR/lib/cache.sh"
  create_test_cli "greet"
  clift_ensure_cache "$CLI_DIR" "$FRAMEWORK_DIR"
  [ -f "$CLI_DIR/.clift/checksum" ]
  local before_mtime after_mtime
  before_mtime="$(_mtime "$CLI_DIR/.clift/checksum")"
  sleep 1
  CLIFT_CACHE=rebuild clift_ensure_cache "$CLI_DIR" "$FRAMEWORK_DIR"
  after_mtime="$(_mtime "$CLI_DIR/.clift/checksum")"
  [ "$after_mtime" -gt "$before_mtime" ]
}

@test "CLIFT_CACHE=bypass skips cache entirely (no .clift/ created)" {
  source "$FRAMEWORK_DIR/lib/cache.sh"
  create_test_cli "greet"
  rm -rf "$CLI_DIR/.clift"
  CLIFT_CACHE=bypass clift_ensure_cache "$CLI_DIR" "$FRAMEWORK_DIR"
  [ ! -d "$CLI_DIR/.clift" ]
}

@test "CLIFT_CACHE=bypass is a no-op when cache already exists (doesn't rebuild, doesn't delete)" {
  source "$FRAMEWORK_DIR/lib/cache.sh"
  create_test_cli "greet"
  clift_ensure_cache "$CLI_DIR" "$FRAMEWORK_DIR"
  local before_mtime after_mtime
  before_mtime="$(_mtime "$CLI_DIR/.clift/checksum")"
  sleep 1
  CLIFT_CACHE=bypass clift_ensure_cache "$CLI_DIR" "$FRAMEWORK_DIR"
  after_mtime="$(_mtime "$CLI_DIR/.clift/checksum")"
  [ "$after_mtime" = "$before_mtime" ]
}

@test "unknown CLIFT_CACHE value falls through to default behavior" {
  source "$FRAMEWORK_DIR/lib/cache.sh"
  create_test_cli "greet"
  CLIFT_CACHE=nonsense clift_ensure_cache "$CLI_DIR" "$FRAMEWORK_DIR"
  [ -f "$CLI_DIR/.clift/checksum" ]
}

@test "unknown CLIFT_CACHE value emits warning on stderr" {
  # Typo protection: `CLIFT_CACHE=rebiuld` must surface as a warning, not
  # silent fall-through. Behavior still passes through to default.
  source "$FRAMEWORK_DIR/lib/cache.sh"
  create_test_cli "greet"
  run bash -c "
    source '$FRAMEWORK_DIR/lib/cache.sh'
    CLIFT_CACHE=typo clift_ensure_cache '$CLI_DIR' '$FRAMEWORK_DIR'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"CLIFT_CACHE='typo' not recognized"* ]]
}

@test "empty CLIFT_CACHE value falls through to default behavior" {
  source "$FRAMEWORK_DIR/lib/cache.sh"
  create_test_cli "greet"
  CLIFT_CACHE="" clift_ensure_cache "$CLI_DIR" "$FRAMEWORK_DIR"
  [ -f "$CLI_DIR/.clift/checksum" ]
}

@test "--no-cache translates to CLIFT_CACHE=rebuild in wrapper" {
  create_test_cli "greet"
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR" >/dev/null 2>&1 || true
  build_test_wrapper
  local before_mtime after_mtime
  before_mtime="$(_mtime "$CLI_DIR/.clift/checksum")"
  sleep 1
  run "$CLI_DIR/bin/$CLI_NAME" --no-cache greet
  after_mtime="$(_mtime "$CLI_DIR/.clift/checksum")"
  [ "$after_mtime" -gt "$before_mtime" ]
}

@test "--no-cache is stripped from argv before parser sees it" {
  create_test_cli "greet" "- {name: who, type: string, default: world, desc: Who}"
  cat > "$CLI_DIR/cmds/greet/greet.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
for v in $(compgen -v CLIFT_ARG_ || true); do
  printf '%s=%s\n' "$v" "${!v}"
done
echo "WHO=${CLIFT_FLAG_WHO:-}"
SH
  chmod +x "$CLI_DIR/cmds/greet/greet.sh"
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR" >/dev/null 2>&1 || true
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" --no-cache greet --who alice
  [ "$status" -eq 0 ]
  [[ "$output" != *"--no-cache"* ]]
  [[ "$output" == *"WHO=alice"* ]]
}

@test "--no-cache between command and subcommand is also stripped" {
  # Wrapper's argv scan must work regardless of position. Here --no-cache
  # sits between the command token and a trailing positional that the
  # user script echoes back.
  create_test_cli "greet" "- {name: who, type: string, default: world, desc: Who}"
  cat > "$CLI_DIR/cmds/greet/greet.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
for v in $(compgen -v CLIFT_ARG_ || true); do
  printf '%s=%s\n' "$v" "${!v}"
done
echo "WHO=${CLIFT_FLAG_WHO:-}"
SH
  chmod +x "$CLI_DIR/cmds/greet/greet.sh"
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR" >/dev/null 2>&1 || true
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" greet --no-cache --who bob
  [ "$status" -eq 0 ]
  [[ "$output" != *"--no-cache"* ]]
  [[ "$output" == *"WHO=bob"* ]]
}

@test "CLIFT_CACHE=bypass + no .clift/ + valid task runs via go-task dispatch" {
  # Graceful-degrade: the wrapper must hand off argv to go-task when the cache
  # is absent under bypass mode. Asserting the task actually RUNS (not just
  # that the wrapper exits cleanly) proves the short-circuit wires argv
  # through to `task` correctly.
  create_test_cli "greet"
  cat > "$CLI_DIR/cmds/greet/greet.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "GREET_RAN=yes"
SH
  chmod +x "$CLI_DIR/cmds/greet/greet.sh"
  build_test_wrapper
  rm -rf "$CLI_DIR/.clift"
  run env CLIFT_CACHE=bypass "$CLI_DIR/bin/$CLI_NAME" greet
  [ "$status" -eq 0 ]
  [[ "$output" == *"GREET_RAN=yes"* ]]
  [[ "$output" != *"task cache missing"* ]]
}

@test "CLIFT_CACHE=bypass + no .clift/ + unknown command yields go-task error (not wrapper error)" {
  # Unknown-task errors must bubble up from go-task, not from the wrapper's
  # own "unknown command" path — the wrapper has no cache to consult for
  # did-you-mean suggestions under bypass+no-cache.
  create_test_cli "greet"
  build_test_wrapper
  rm -rf "$CLI_DIR/.clift"
  run env CLIFT_CACHE=bypass "$CLI_DIR/bin/$CLI_NAME" nonexistent-command
  [ "$status" -ne 0 ]
  # Wrapper's own unknown-command error must NOT fire under this path.
  [[ "$output" != *"error: unknown command"* ]]
  [[ "$output" != *"task cache missing"* ]]
}

@test "--no-cache appears in --help global flag listing" {
  create_test_cli "greet"
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR" >/dev/null 2>&1 || true
  build_test_wrapper
  run "$CLI_DIR/bin/$CLI_NAME" greet --help
  [[ "$output" == *"--no-cache"* ]]
  [[ "$output" == *"Force-rebuild"* ]]
}

@test "--no-cache after -- terminator is NOT consumed (bash convention)" {
  # Per bash convention, everything after `--` is literal. A user invoking
  # `mycli greet -- --no-cache some-file` almost certainly means "pass
  # --no-cache as a literal argument to my script." The wrapper's scan
  # must stop at `--`.
  create_test_cli "greet"
  cat > "$CLI_DIR/cmds/greet/greet.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
for v in $(compgen -v CLIFT_ARG_ || true); do
  printf '%s=%s\n' "$v" "${!v}"
done
SH
  chmod +x "$CLI_DIR/cmds/greet/greet.sh"
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR" >/dev/null 2>&1 || true
  build_test_wrapper
  local before_mtime after_mtime
  before_mtime="$(_mtime "$CLI_DIR/.clift/checksum")"
  sleep 1
  run "$CLI_DIR/bin/$CLI_NAME" greet -- --no-cache
  [ "$status" -eq 0 ]
  # Cache must NOT have been rebuilt (the --no-cache after -- is literal)
  after_mtime="$(_mtime "$CLI_DIR/.clift/checksum")"
  [ "$after_mtime" = "$before_mtime" ]
  # And the user script should see --no-cache as a positional
  [[ "$output" == *"--no-cache"* ]]
}

@test "--no-cache=anything is rejected by the parser (bool with inline value)" {
  # The flag is declared as bool and does not accept inline values. The
  # wrapper's scan matches exactly "--no-cache" (no `=` form), so
  # `--no-cache=foo` falls through to the parser, which rejects it with
  # the bool-with-value error path.
  create_test_cli "greet"
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR" >/dev/null 2>&1 || true
  build_test_wrapper
  local before_mtime after_mtime
  before_mtime="$(_mtime "$CLI_DIR/.clift/checksum")"
  sleep 1
  run "$CLI_DIR/bin/$CLI_NAME" greet --no-cache=foo
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not take a value"* ]]
  # Cache must NOT have been rebuilt (the value-form isn't treated as the flag)
  after_mtime="$(_mtime "$CLI_DIR/.clift/checksum")"
  [ "$after_mtime" = "$before_mtime" ]
}

@test "--no-cache overrides CLIFT_CACHE=bypass (flag wins over env)" {
  # The wrapper translates --no-cache to CLIFT_CACHE=rebuild before calling
  # into cache.sh, overwriting whatever CLIFT_CACHE was inherited. The cache
  # rebuild (evidence: refreshed checksum mtime) is the observable proof
  # that the flag won out over the env var. Exit status is immaterial —
  # test fixtures have no greet.sh script, so go-task errors downstream;
  # the cache state is the thing under test.
  create_test_cli "greet"
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR" >/dev/null 2>&1 || true
  build_test_wrapper
  local before after
  before="$(_mtime "$CLI_DIR/.clift/checksum")"
  sleep 1
  run env CLIFT_CACHE=bypass "$CLI_DIR/bin/$CLI_NAME" --no-cache greet
  after="$(_mtime "$CLI_DIR/.clift/checksum")"
  [ "$after" -gt "$before" ]
}

@test "concurrent CLIFT_CACHE=rebuild invocations both compile (winner+loser)" {
  source "$FRAMEWORK_DIR/lib/cache.sh"
  create_test_cli "greet"
  clift_ensure_cache "$CLI_DIR" "$FRAMEWORK_DIR"
  # Run two rebuilds in parallel. Best-effort contention test: the primary
  # assertion is that neither invocation deadlocks or errors under the lock.
  # `|| true` on the wait calls prevents bash's set -e (bats enables it)
  # from failing the whole test when `wait` reports a non-zero rc — we
  # capture the rc explicitly and assert on it below.
  local rc1=0 rc2=0
  (CLIFT_CACHE=rebuild clift_ensure_cache "$CLI_DIR" "$FRAMEWORK_DIR") &
  local pid1=$!
  (CLIFT_CACHE=rebuild clift_ensure_cache "$CLI_DIR" "$FRAMEWORK_DIR") &
  local pid2=$!
  wait "$pid1" || rc1=$?
  wait "$pid2" || rc2=$?
  [ "$rc1" -eq 0 ]
  [ "$rc2" -eq 0 ]
  # Both should have written/refreshed the checksum (file exists + non-empty)
  [ -s "$CLI_DIR/.clift/checksum" ]
}

@test "--no-cache as the last argv token still triggers rebuild" {
  # Position coverage: the wrapper's argv scan must handle --no-cache
  # anywhere, including trailing position after other flags. Use a real
  # greet.sh so exit status can be asserted alongside the mtime bump.
  create_test_cli "greet" "- {name: who, type: string, default: world, desc: Who}"
  cat > "$CLI_DIR/cmds/greet/greet.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "WHO=${CLIFT_FLAG_WHO:-}"
SH
  chmod +x "$CLI_DIR/cmds/greet/greet.sh"
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR" >/dev/null 2>&1 || true
  build_test_wrapper
  local before after
  before="$(_mtime "$CLI_DIR/.clift/checksum")"
  sleep 1
  run "$CLI_DIR/bin/$CLI_NAME" greet --who bob --no-cache
  [ "$status" -eq 0 ]
  after="$(_mtime "$CLI_DIR/.clift/checksum")"
  [ "$after" -gt "$before" ]
  [[ "$output" == *"WHO=bob"* ]]
}

@test "--no-cache interleaved with another global still rebuilds and runs help" {
  # --no-cache before the command + --help after should trigger BOTH the
  # rebuild and the help render.
  create_test_cli "greet"
  bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$CLI_DIR" >/dev/null 2>&1 || true
  build_test_wrapper
  local before after
  before="$(_mtime "$CLI_DIR/.clift/checksum")"
  sleep 1
  run "$CLI_DIR/bin/$CLI_NAME" --no-cache greet --help
  [ "$status" -eq 0 ]
  # Cache rebuilt
  after="$(_mtime "$CLI_DIR/.clift/checksum")"
  [ "$after" -gt "$before" ]
  # Help rendered (global flag section visible)
  [[ "$output" == *"--help"* ]]
}
