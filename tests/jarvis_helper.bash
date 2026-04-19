#!/usr/bin/env bash
# Shared setup for jarvis bats suites.
# Redirects HOME to TEST_DIR; sets JARVIS_HOME to a per-test tmp.

# shellcheck disable=SC2317
if [[ -n "${_JARVIS_HELPER_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
_JARVIS_HELPER_LOADED=1

jarvis_common_setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR"
  export JARVIS_HOME="$TEST_DIR/jarvis-state"
  export JARVIS_PROFILE="test"
  export CLIFT_FRAMEWORK_DIR="${BATS_TEST_DIRNAME}/.."
  export CLIFT_JARVIS_DIR="${BATS_TEST_DIRNAME}/../examples/jarvis"
  mkdir -p "$JARVIS_HOME"
}

jarvis_common_teardown() {
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}
