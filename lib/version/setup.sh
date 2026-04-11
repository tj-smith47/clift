#!/usr/bin/env bash
# Sets up cfgd versioning for a clift CLI.
# Usage: setup.sh <CLI_DIR> <FRAMEWORK_DIR>
#
# Environment variables:
#   CFGD_CONFIG_DIR — path to existing cfgd config repo (standalone mode if unset)
#   CFGD_PROFILES   — comma-separated list of cfgd profiles to add the module to

set -euo pipefail

CLI_DIR="${1:-}"
FRAMEWORK_DIR="${2:-}"

if [[ -z "$CLI_DIR" || -z "$FRAMEWORK_DIR" ]]; then
  echo "error: CLI_DIR and FRAMEWORK_DIR required" >&2
  exit 1
fi

source "${FRAMEWORK_DIR}/lib/log/log.sh"

cli_name="${CLI_NAME:-$(yq '.name' "${CLI_DIR}/.clift.yaml" 2>/dev/null)}"
cli_version="${CLI_VERSION:-$(yq '.version' "${CLI_DIR}/.clift.yaml" 2>/dev/null)}"

if [[ -z "$cli_name" || "$cli_name" == "null" ]]; then
  die "Could not determine CLI name from .clift.yaml"
fi

# Already configured?
if [[ "${CFGD_VERSIONING:-}" == "true" ]]; then
  log_info "Versioning is already configured for ${cli_name}"
  exit 0
fi

# --- Step 1: Ensure cfgd is installed ---
if ! command -v cfgd &>/dev/null; then
  log_info "Installing cfgd..."

  if ! curl -fsSL https://raw.githubusercontent.com/tj-smith47/cfgd/master/install.sh | sh; then
    die "Failed to install cfgd. Install manually: https://github.com/tj-smith47/cfgd"
  fi

  export PATH="${HOME}/.local/bin:${PATH}"

  if ! command -v cfgd &>/dev/null; then
    die "cfgd installed but not found in PATH. Add ~/.local/bin to your PATH and try again."
  fi

  log_success "cfgd installed"
fi

# --- Step 2: Detect git remote ---
git_remote=""
if git -C "$CLI_DIR" rev-parse --git-dir &>/dev/null; then
  git_remote=$(git -C "$CLI_DIR" remote get-url origin 2>/dev/null || true)
fi

# --- Step 3: Configure module ---
cfgd_config_dir="${CFGD_CONFIG_DIR:-}"
cfgd_profiles="${CFGD_PROFILES:-}"

_ensure_module_yaml() {
  local dest="$1"
  if [[ ! -f "$dest" ]]; then
    sed -e "s|%%CLI_NAME%%|${cli_name}|g" \
      "${FRAMEWORK_DIR}/templates/cli/module.yaml.tmpl" > "$dest"
  fi
}

_set_git_source() {
  local module_file="$1"
  if [[ -n "$git_remote" ]]; then
    yq -i ".spec.files = [{\"source\": \"${git_remote}@main\", \"target\": \"~/.local/share/${cli_name}\"}]" "$module_file"
  fi
}

if [[ -n "$cfgd_config_dir" ]]; then
  # --- Mode: Add module to existing cfgd config repo ---
  if [[ ! -d "$cfgd_config_dir" ]]; then
    die "CFGD_CONFIG_DIR does not exist: ${cfgd_config_dir}"
  fi

  module_dest="${cfgd_config_dir}/modules/${cli_name}"
  mkdir -p "$module_dest"

  if [[ -f "${CLI_DIR}/module.yaml" ]]; then
    cp "${CLI_DIR}/module.yaml" "${module_dest}/module.yaml"
  else
    _ensure_module_yaml "${module_dest}/module.yaml"
  fi

  _set_git_source "${module_dest}/module.yaml"
  log_success "Module added to ${module_dest}"

  # Add to profiles if specified
  if [[ -n "$cfgd_profiles" ]]; then
    IFS=',' read -ra profiles <<< "$cfgd_profiles"
    for profile in "${profiles[@]}"; do
      profile=$(echo "$profile" | xargs)
      profile_file="${cfgd_config_dir}/profiles/${profile}.yaml"
      if [[ -f "$profile_file" ]]; then
        yq -i ".spec.modules += [\"${cli_name}\"] | .spec.modules |= unique" "$profile_file"
        log_success "Added ${cli_name} to profile: ${profile}"
      else
        log_warn "Profile not found: ${profile_file}"
      fi
    done
  fi
else
  # --- Mode: Standalone module repo ---
  _ensure_module_yaml "${CLI_DIR}/module.yaml"
  _set_git_source "${CLI_DIR}/module.yaml"

  if [[ -n "$git_remote" ]]; then
    log_info "Module configured with remote: ${git_remote}"
  else
    log_warn "No git remote found — module.yaml source URL left as placeholder"
    log_suggest "Set a remote and re-run version:setup to update"
  fi

  log_success "Standalone module configured at ${CLI_DIR}/module.yaml"
fi

# --- Step 4: Enable versioning in .env ---
env_file="${CLI_DIR}/.env"
if [[ -f "$env_file" ]] && grep -q "^CFGD_VERSIONING=" "$env_file" 2>/dev/null; then
  sed -i "s|^CFGD_VERSIONING=.*|CFGD_VERSIONING=true|" "$env_file"
else
  echo "CFGD_VERSIONING=true" >> "$env_file"
fi

# --- Step 5: Add version namespace to CLI Taskfile ---
taskfile="${CLI_DIR}/Taskfile.yaml"
if [[ -f "$taskfile" ]]; then
  # Add version include if not already present
  if ! grep -q "taskfile:.*lib/version" "$taskfile" 2>/dev/null; then
    if grep -q "# User commands" "$taskfile"; then
      sed -i "/# User commands/i\\
  version:\\
    taskfile: '{{.FRAMEWORK_DIR}}/lib/version'" "$taskfile"
    else
      sed -i "/^tasks:/i\\
  version:\\
    taskfile: '{{.FRAMEWORK_DIR}}/lib/version'" "$taskfile"
    fi
  fi

  # Remove simple version task (matches "  version:" with desc "Print version")
  sed -i '/^  version:$/{N;/Print version/{N;d;}}' "$taskfile"
fi

log_success "Versioning enabled for ${cli_name}"
echo ""
log_info "Next steps:"
if [[ -z "$git_remote" ]]; then
  echo "  git remote add origin <your-repo-url>"
  echo "  ${cli_name} version:setup   # re-run to update module.yaml"
fi
echo "  git tag \"${cli_name}/v${cli_version}\""
echo "  git push origin --tags"
