#!/usr/bin/env bash
set -euo pipefail

source "${FRAMEWORK_DIR}/lib/log/log.sh"

log_info "jarvis debug — internal state"
printf '  profile:   %s\n' "${CLIFT_FLAGS[profile]:-work}"
printf '  cli_dir:   %s\n' "${CLI_DIR:-?}"
printf '  framework: %s\n' "${FRAMEWORK_DIR:-?}"
printf '  version:   %s\n' "${CLI_VERSION:-?}"
