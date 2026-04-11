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
  export FRAMEWORK_DIR="/opt/repos/task-cli"
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
