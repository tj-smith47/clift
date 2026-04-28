#!/usr/bin/env bash
# build_state.sh — Builds jarvis-state into bin/jarvis-state.
#
# Wave A placeholder: writes a stub binary that prints "1" (protocol version).
# Wave B replaces the body with: go build -o bin/jarvis-state ./jarvis-state/...
#
# Must be invoked from the jarvis CLI root (examples/jarvis/).

set -euo pipefail

JARVIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mkdir -p "$JARVIS_DIR/bin"

printf '#!/bin/sh\necho 1\n' > "$JARVIS_DIR/bin/jarvis-state"
chmod +x "$JARVIS_DIR/bin/jarvis-state"
