#!/usr/bin/env bash
# Run tests with kcov coverage.
# Usage: scripts/coverage.sh [bats-args...]
# Output: coverage/ directory with HTML report
#
# Examples:
#   scripts/coverage.sh                    # full suite
#   scripts/coverage.sh tests/log.bats     # single file
#   scripts/coverage.sh --jobs 4           # parallel

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COVERAGE_DIR="$PROJECT_DIR/coverage"

if ! command -v kcov &>/dev/null; then
  echo "error: kcov is required for coverage. Install via:" >&2
  echo "  brew install kcov    # macOS / Linuxbrew" >&2
  echo "  apt install kcov     # Ubuntu (if available)" >&2
  echo "  # or build from source: https://github.com/SimonKagstrom/kcov" >&2
  exit 1
fi

if ! command -v bats &>/dev/null; then
  echo "error: bats is required. See https://github.com/bats-core/bats-core" >&2
  exit 1
fi

# Default: run all tests
args=("${@:-tests/}")

echo "Running tests with coverage..."
rm -rf "$COVERAGE_DIR"

kcov \
  --include-path="$PROJECT_DIR/lib" \
  --exclude-pattern=".bats,test_helper" \
  "$COVERAGE_DIR" \
  bats "${args[@]}"

# Extract summary from JSON
if [[ -f "$COVERAGE_DIR/bats/coverage.json" ]]; then
  percent="$(jq -r '.percent_covered' "$COVERAGE_DIR/bats/coverage.json")"
  covered="$(jq -r '.covered_lines' "$COVERAGE_DIR/bats/coverage.json")"
  total="$(jq -r '.total_lines' "$COVERAGE_DIR/bats/coverage.json")"
  echo ""
  echo "Coverage: ${percent}% (${covered}/${total} lines)"
  echo "Report:   $COVERAGE_DIR/bats/index.html"
fi
