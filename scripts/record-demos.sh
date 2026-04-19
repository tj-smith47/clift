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
#   - KUBECONFIG is preserved so the hero tape can query a live cluster.
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

# Resolve the user's kubeconfig BEFORE we swap HOME — kubectl defaults to
# $HOME/.kube/config when KUBECONFIG is unset, and the stub HOME won't have
# one. Copy the path forward explicitly so the hero tape still works.
if [[ -z "${KUBECONFIG:-}" && -f "$ORIG_HOME/.kube/config" ]]; then
  export KUBECONFIG="$ORIG_HOME/.kube/config"
fi

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
mkdir -p "$DEMO_DIR/kube/cmds"
cp "$FRAMEWORK_DIR/examples/kube/Taskfile.yaml" "$DEMO_DIR/kube/"
cp -r "$FRAMEWORK_DIR/examples/kube/cmds/"* "$DEMO_DIR/kube/cmds/"

echo "Setting up kube example for recording..."
bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
  "$DEMO_DIR/kube" "$FRAMEWORK_DIR" "kube" "1.0.0" "icons-color" "standard"

export PATH="$DEMO_DIR/kube/bin:$FRAMEWORK_DIR/bin:$PATH"

# Apply the dummy demo resources used by the hero tape. Idempotent —
# safe to run repeatedly against any cluster. The `clift-demo` namespace
# and its `web` deployment are deliberately generic so nothing in the
# recording identifies the underlying cluster.
if command -v kubectl &>/dev/null; then
  echo "Applying demo resources (namespace clift-demo)..."
  kubectl apply -f "$FRAMEWORK_DIR/examples/kube/demo-resources.yaml" >/dev/null
  kubectl -n clift-demo rollout status deployment/web --timeout=60s >/dev/null
else
  echo "warn: kubectl not found — the hero tape requires a reachable cluster" >&2
fi

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
