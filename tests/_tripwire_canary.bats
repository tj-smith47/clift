# Filesystem-tripwire canary
#
# Verifies the tripwire in test_helper.bash fires when a test mutates a
# real-$HOME file. The "negative" tests deliberately write to the real
# .bashrc and assert the tripwire fails the test — they do this by
# running the harness in a subshell so the parent test only fails if the
# tripwire DOESN'T fire (i.e. the safety net is broken).
#
# This file is named with a leading underscore so it sorts first in
# `bats tests/*.bats` — if the tripwire is broken, every other test in
# the suite is suspect, so we want the canary to fail before they run.

bats_require_minimum_version 1.5.0

load test_helper

@test "tripwire: pristine real-HOME passes through teardown clean" {
  # No mutations — common_teardown's tripwire check should be a no-op.
  :
}

@test "tripwire: writing to real ~/.bashrc is detected as drift" {
  # Synthesize the failure mode in-process: re-init the snapshot against
  # a fake "real HOME" we control, then mutate a watched file and run
  # the check. We assert the check returns 1 and prints a violation
  # banner — that's the contract every other test relies on.
  local fake_real_home; fake_real_home="$(mktemp -d)"
  printf 'original\n' > "$fake_real_home/.bashrc"
  TRIPWIRE_REAL_HOME="$fake_real_home" \
  TRIPWIRE_SNAPSHOT="$TEST_DIR/.tripwire-canary" \
    _tripwire_init

  printf 'mutated\n' >> "$fake_real_home/.bashrc"

  run -1 bash -c '
    source "'"$BATS_TEST_DIRNAME"'/test_helper.bash"
    TRIPWIRE_REAL_HOME="'"$fake_real_home"'"
    TRIPWIRE_SNAPSHOT="'"$TEST_DIR"'/.tripwire-canary"
    _tripwire_check
  '
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"FILESYSTEM TRIPWIRE"* ]]
  [[ "$output" == *".bashrc"* ]]
  rm -rf "$fake_real_home"
}

@test "tripwire: creating a previously-absent dotfile is detected" {
  local fake_real_home; fake_real_home="$(mktemp -d)"
  TRIPWIRE_REAL_HOME="$fake_real_home" \
  TRIPWIRE_SNAPSHOT="$TEST_DIR/.tripwire-canary" \
    _tripwire_init

  printf 'leak\n' > "$fake_real_home/.gitconfig"

  run -1 bash -c '
    source "'"$BATS_TEST_DIRNAME"'/test_helper.bash"
    TRIPWIRE_REAL_HOME="'"$fake_real_home"'"
    TRIPWIRE_SNAPSHOT="'"$TEST_DIR"'/.tripwire-canary"
    _tripwire_check
  '
  [[ "$status" -eq 1 ]]
  [[ "$output" == *".gitconfig"* ]]
  [[ "$output" == *"MISSING"* ]]
  rm -rf "$fake_real_home"
}

@test "tripwire: deleting a previously-present dotfile is detected" {
  local fake_real_home; fake_real_home="$(mktemp -d)"
  printf 'original\n' > "$fake_real_home/.zshrc"
  TRIPWIRE_REAL_HOME="$fake_real_home" \
  TRIPWIRE_SNAPSHOT="$TEST_DIR/.tripwire-canary" \
    _tripwire_init

  rm -f "$fake_real_home/.zshrc"

  run -1 bash -c '
    source "'"$BATS_TEST_DIRNAME"'/test_helper.bash"
    TRIPWIRE_REAL_HOME="'"$fake_real_home"'"
    TRIPWIRE_SNAPSHOT="'"$TEST_DIR"'/.tripwire-canary"
    _tripwire_check
  '
  [[ "$status" -eq 1 ]]
  [[ "$output" == *".zshrc"* ]]
  rm -rf "$fake_real_home"
}

@test "tripwire_watch: extends watchset with caller-supplied path" {
  local victim; victim="$(mktemp)"
  printf 'before\n' > "$victim"
  tripwire_watch "$victim"

  printf 'after\n' >> "$victim"

  run -1 bash -c '
    source "'"$BATS_TEST_DIRNAME"'/test_helper.bash"
    TRIPWIRE_REAL_HOME="'"$TRIPWIRE_REAL_HOME"'"
    TRIPWIRE_SNAPSHOT="'"$TRIPWIRE_SNAPSHOT"'"
    _tripwire_check
  '
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"$victim"* ]]
  rm -f "$victim"

  # Re-snapshot so the trailing common_teardown check passes — the
  # extended path is gone now, so we have to clear the snapshot file
  # entry that references it.
  _tripwire_init
}

@test "tripwire_watch: rejects relative paths" {
  run tripwire_watch "relative/path"
  [[ "$status" -eq 64 ]]
  [[ "$output" == *"must be absolute"* ]]
}
