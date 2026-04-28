#!/usr/bin/env bash
# build_when.sh — Builds jarvis-when into bin/jarvis-when.
#
# Wave A placeholder: writes a stub binary that prints "1" (protocol version).
# Wave B replaces the body with a Python zipapp build via
# jarvis-when/scripts/build_zipapp.sh.
#
# Must be invoked from the jarvis CLI root (examples/jarvis/).

set -euo pipefail

JARVIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mkdir -p "$JARVIS_DIR/bin"

printf '#!/bin/sh\necho 1\n' > "$JARVIS_DIR/bin/jarvis-when"
chmod +x "$JARVIS_DIR/bin/jarvis-when"
