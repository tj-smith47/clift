#!/usr/bin/env bash
# Restart a deployment by wrapping `kubectl rollout restart` +
# `kubectl rollout status`. Advertises the value of clift: two kubectl
# commands (with explicit -n, resource type, and a polling step) become
# one simple clift command backed by a spinner.

set -euo pipefail

source "${FRAMEWORK_DIR}/lib/log/log.sh"

workload="${CLIFT_POS_1:-}"
namespace="${CLIFT_FLAG_NAMESPACE:-clift-demo}"
timeout="${CLIFT_FLAG_TIMEOUT:-60s}"

if [[ -z "$workload" ]]; then
  log_error "usage: kube restart <deployment> [--namespace NS] [--timeout DUR]"
  exit 1
fi

if ! command -v kubectl &>/dev/null; then
  log_error "kubectl not found on PATH"
  exit 1
fi

_rollout() {
  kubectl rollout restart "deployment/${workload}" -n "${namespace}" >/dev/null
  kubectl rollout status "deployment/${workload}" -n "${namespace}" --timeout="${timeout}" >/dev/null
}

if command -v gum &>/dev/null; then
  gum spin --spinner dot --title "Restarting ${workload}…" -- bash -c "$(declare -f _rollout); _rollout"
else
  log_info "Restarting ${workload} in ${namespace}…"
  _rollout
fi

log_success "restarted deployment/${workload} in ${namespace}"
