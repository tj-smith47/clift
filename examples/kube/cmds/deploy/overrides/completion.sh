#!/usr/bin/env bash
# Dynamic completer for `kube deploy --target <TAB>`.
# Looked up via `declare -F clift_complete_deploy_target` at completion time.

clift_complete_deploy_target() {
  local prefix="${1:-}"
  local regions=(staging prod eu-west us-east eu-central us-west ap-south)
  for r in "${regions[@]}"; do
    [[ "$r" == "$prefix"* ]] && printf '%s\n' "$r"
  done
}
