#!/usr/bin/env bash
# Live cluster status — calls kubectl against the user's current kubeconfig.
# Used as the hero demo; chosen namespace defaults to kube-system so the output
# is the same shape on any cluster and doesn't leak workload topology.

set -euo pipefail

source "${FRAMEWORK_DIR}/lib/log/log.sh"

ns="${CLIFT_FLAG_NAMESPACE:-kube-system}"
wide="${CLIFT_FLAG_WIDE:-}"

if ! command -v kubectl &>/dev/null; then
  log_error "kubectl not found on PATH"
  exit 1
fi

_kubectl_args=(get pods -n "$ns")
[[ "$wide" == "true" ]] && _kubectl_args+=(-o wide)

if command -v gum &>/dev/null; then
  # Spinner while kubectl runs. --show-output lets kubectl's output appear
  # after the spinner completes.
  gum spin --spinner dot --title "Querying ${ns}…" --show-output -- \
    kubectl "${_kubectl_args[@]}"
else
  log_info "Querying ${ns}…"
  kubectl "${_kubectl_args[@]}"
fi
