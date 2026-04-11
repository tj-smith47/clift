# Common test helper
#
# FILESYSTEM ISOLATION: every test must run with HOME redirected into
# TEST_DIR so nothing can write to the developer's real shell rc files,
# config dirs, or caches. Past test runs without this guard polluted the
# developer's real ~/.bashrc with stray alias entries pointing at /tmp dirs
# that no longer exist. Never remove the HOME redirect below.
setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR"
  # FRAMEWORK_DIR derives from the test file location so tests work regardless
  # of where the repo is checked out (main worktree, feature worktree, /tmp, etc.)
  export FRAMEWORK_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export CLI_DIR="$TEST_DIR"
  export CLI_NAME="testcli"
  export CLI_VERSION="1.0.0"
  export LOG_THEME="minimal"
  export PROMPT="false"
  # Give tests a real (but isolated) rc file so setup.sh can write into it.
  touch "$HOME/.bashrc"
  touch "$HOME/.zshrc"
}

teardown() {
  rm -rf "$TEST_DIR"
}
