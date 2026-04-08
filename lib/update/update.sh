#!/usr/bin/env bash
# Updates the DIYCLI framework to the latest version.
# Usage: update.sh <FRAMEWORK_DIR>

set -euo pipefail

FRAMEWORK_DIR="${1:-}"

if [[ -z "$FRAMEWORK_DIR" ]]; then
  echo "error: FRAMEWORK_DIR required" >&2
  exit 1
fi

source "${FRAMEWORK_DIR}/lib/log/log.sh"

# Check it's a git repo
if [[ ! -d "${FRAMEWORK_DIR}/.git" ]]; then
  die "Framework directory is not a git repository"
fi

# Fetch latest
log_info "Checking for updates..."
git -C "$FRAMEWORK_DIR" fetch --quiet 2>/dev/null || {
  die "Failed to fetch updates. Check your network connection."
}

# Get current and remote branch
current_branch=$(git -C "$FRAMEWORK_DIR" rev-parse --abbrev-ref HEAD)
remote_ref="origin/${current_branch}"

local_sha=$(git -C "$FRAMEWORK_DIR" rev-parse HEAD)
remote_sha=$(git -C "$FRAMEWORK_DIR" rev-parse "$remote_ref" 2>/dev/null) || {
  die "Could not find remote branch: $remote_ref"
}

if [[ "$local_sha" == "$remote_sha" ]]; then
  log_success "Already up to date"
  exit 0
fi

# Show pending changes
commit_count=$(git -C "$FRAMEWORK_DIR" rev-list --count HEAD.."$remote_ref")
log_info "${commit_count} update(s) available:"
echo ""
git -C "$FRAMEWORK_DIR" log --oneline HEAD.."$remote_ref" | sed 's/^/  /'
echo ""

# Prompt
read -rp "Update now? [y/N] " response </dev/tty
if [[ ! "$response" =~ ^[Yy] ]]; then
  log_info "Update cancelled"
  exit 0
fi

# Pull
git -C "$FRAMEWORK_DIR" pull --quiet || {
  die "Update failed. You may need to resolve conflicts manually."
}

# Check if min_task_version changed
if [[ -f "${FRAMEWORK_DIR}/.task-cli.yaml" ]]; then
  min_ver=$(grep 'min_task_version' "${FRAMEWORK_DIR}/.task-cli.yaml" | sed 's/.*"\(.*\)".*/\1/' || true)
  if [[ -n "$min_ver" ]]; then
    log_info "Minimum task version: ${min_ver}"
  fi
fi

log_success "Updated to latest version"
