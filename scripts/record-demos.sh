#!/usr/bin/env bash
# Record VHS demo GIFs for the README.
# Requires: vhs (https://github.com/charmbracelet/vhs), a TTY
#
# Usage: scripts/record-demos.sh
#
# Outputs: .vhs/gifs/*.gif (committed to repo, referenced by README)
#
# Isolation contract:
#   - HOME is redirected to a tempdir for the duration of recording, so VHS's
#     spawned bash sources a stub ~/.bashrc (neutral prompt, no aliases, no
#     hostname, no history) rather than the developer's real one.
#   - The jarvis example is hermetic (no network, no cluster) — demos are
#     reproducible anywhere.
#   - Original HOME is restored on EXIT/INT/TERM.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRAMEWORK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! command -v vhs &>/dev/null; then
  echo "error: vhs not installed. Install: go install github.com/charmbracelet/vhs@latest" >&2
  exit 1
fi

# Chrome won't run as root without --no-sandbox; VHS respects this env var.
export VHS_NO_SANDBOX=true

mkdir -p "$FRAMEWORK_DIR/.vhs/gifs"

DEMO_DIR="$(mktemp -d)"
ORIG_HOME="$HOME"
trap 'rm -rf "$DEMO_DIR"; export HOME="$ORIG_HOME"' EXIT INT TERM

# Stub bashrc: neutral prompt, no history, no aliases, no user customization.
# Anything VHS's bash might source gets pointed here.
cat > "$DEMO_DIR/.bashrc" <<'STUB'
# Recording stub — no user customization leaks into committed .gif files.
set +H
unset PROMPT_COMMAND
export PS1='$ '
export HISTFILE=/dev/null
export HISTSIZE=0
STUB
cp "$DEMO_DIR/.bashrc" "$DEMO_DIR/.bash_profile"

# Swap HOME for the duration. Framework rc-file writes go to the stub too.
export HOME="$DEMO_DIR"
export CLIFT_RC_FILE="$DEMO_DIR/.bashrc"
export PROMPT=false
export RECONFIGURE_YES=1

# Copy only the command sources, not build artifacts
mkdir -p "$DEMO_DIR/jarvis/cmds"
cp "$FRAMEWORK_DIR/examples/jarvis/Taskfile.yaml" "$FRAMEWORK_DIR/examples/jarvis/.env" "$DEMO_DIR/jarvis/"
cp -r "$FRAMEWORK_DIR/examples/jarvis/cmds/"* "$DEMO_DIR/jarvis/cmds/"

echo "Setting up jarvis example for recording..."
bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
  "$DEMO_DIR/jarvis" "$FRAMEWORK_DIR" "jarvis" "1.0.0" "icons-color" "standard"

export PATH="$DEMO_DIR/jarvis/bin:$FRAMEWORK_DIR/bin:$PATH"

# Purge stale GIFs BEFORE recording so renamed/deleted tapes don't leave
# orphans committed. Invariant: after a successful run, the set of gifs in
# .vhs/gifs/ equals the set of .tape files.
echo "Purging stale gifs..."
find "$FRAMEWORK_DIR/.vhs/gifs" -maxdepth 1 -type f -name '*.gif' -delete

echo "Recording tapes (HOME=$HOME)..."
for tape in "$FRAMEWORK_DIR"/.vhs/*.tape; do
  name="$(basename "$tape" .tape)"
  echo "  Recording $name..."
  vhs "$tape"
done

echo ""
echo "Done. GIFs written to .vhs/gifs/"
