#!/usr/bin/env bash
# build_cal.sh — Builds jarvis-cal into bin/jarvis-cal.
#
# Wave A placeholder: writes a stub binary that prints "1" (protocol version).
# Wave B replaces the body with: cargo build --release --manifest-path jarvis-cal/Cargo.toml
# and copies the result to bin/jarvis-cal.
#
# Must be invoked from the jarvis CLI root (examples/jarvis/).

set -euo pipefail

JARVIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mkdir -p "$JARVIS_DIR/bin"

printf '#!/bin/sh\necho 1\n' > "$JARVIS_DIR/bin/jarvis-cal"
chmod +x "$JARVIS_DIR/bin/jarvis-cal"
