#!/usr/bin/env bash
# update-coverage-badge.sh — Generate and push a coverage badge to the badges branch.
# Reads kcov output from coverage/bats/coverage.json.
# Designed to run in CI after scripts/coverage.sh.
set -euo pipefail

COVERAGE_JSON="${1:-coverage/bats/coverage.json}"

if [[ ! -f "$COVERAGE_JSON" ]]; then
  echo "error: coverage report not found at $COVERAGE_JSON" >&2
  echo "  run scripts/coverage.sh first" >&2
  exit 1
fi

# Parse coverage percentage from kcov output
COVERAGE=$(jq -r '.percent_covered' "$COVERAGE_JSON")

if [[ -z "$COVERAGE" || "$COVERAGE" == "null" ]]; then
  echo "error: could not parse percent_covered from $COVERAGE_JSON" >&2
  exit 1
fi

# Determine badge color based on thresholds
if (( $(echo "$COVERAGE >= 90" | bc -l) )); then COLOR="brightgreen"
elif (( $(echo "$COVERAGE >= 80" | bc -l) )); then COLOR="green"
elif (( $(echo "$COVERAGE >= 70" | bc -l) )); then COLOR="yellowgreen"
elif (( $(echo "$COVERAGE >= 60" | bc -l) )); then COLOR="yellow"
else COLOR="red"; fi

echo "Coverage: ${COVERAGE}% (${COLOR})"

# Setup git for github-actions bot
git config user.email "github-actions[bot]@users.noreply.github.com"
git config user.name "github-actions[bot]"

# Fetch or create the badges branch
git fetch origin badges:badges 2>/dev/null || true
if git show-ref --verify --quiet refs/heads/badges; then
  git checkout badges
else
  git checkout --orphan badges
  git rm -rf . > /dev/null 2>&1 || true
fi

# Generate shields.io endpoint badge JSON
BADGE="{\"schemaVersion\":1,\"label\":\"coverage\",\"message\":\"${COVERAGE}%\",\"color\":\"${COLOR}\"}"
echo "$BADGE" > coverage.json

# Commit and force-push to badges branch
git add coverage.json
git diff --cached --quiet || git commit -m "Update coverage to ${COVERAGE}%"
git push origin badges --force
