#!/usr/bin/env bash
# Record VHS demo GIFs for the README.
# Requires: vhs (https://github.com/charmbracelet/vhs), a TTY
#
# Usage: scripts/record-demos.sh
#
# Outputs: .vhs/gifs/*.gif (committed to repo, referenced by README)

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

# Build the kube example in a temp dir — avoids polluting the repo and
# avoids the reconfigure prompt (no pre-existing .env in the copy).
DEMO_DIR="$(mktemp -d)"
trap 'rm -rf "$DEMO_DIR"' EXIT

# Redirect rc writes to temp dir but do NOT override HOME — VHS/Chrome
# need the real HOME for their caches.
export CLIFT_RC_FILE="$DEMO_DIR/.bashrc"
export PROMPT=false
export RECONFIGURE_YES=1
touch "$DEMO_DIR/.bashrc"

# Copy only the command sources, not build artifacts
mkdir -p "$DEMO_DIR/kube/cmds"
cp "$FRAMEWORK_DIR/examples/kube/Taskfile.yaml" "$DEMO_DIR/kube/"
cp -r "$FRAMEWORK_DIR/examples/kube/cmds/"* "$DEMO_DIR/kube/cmds/"

echo "Setting up kube example for recording..."
bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
  "$DEMO_DIR/kube" "$FRAMEWORK_DIR" "kube" "1.0.0" "icons-color" "standard"

export PATH="$DEMO_DIR/kube/bin:$FRAMEWORK_DIR/bin:$PATH"

echo "Recording tapes..."
for tape in "$FRAMEWORK_DIR"/.vhs/*.tape; do
  name="$(basename "$tape" .tape)"
  echo "  Recording $name..."
  vhs "$tape"
done

echo ""
echo "Done. GIFs written to .vhs/gifs/"
