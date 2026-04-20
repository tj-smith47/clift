#!/usr/bin/env bash
# TOML config loader for jarvis. Requires `dasel` on PATH.
# Usage: config_get <dotted.key> <default-value>

# shellcheck disable=SC2317
if [[ -n "${_JARVIS_STATE_CONFIG_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
_JARVIS_STATE_CONFIG_LOADED=1

config_get() {
  local key="$1"
  local default="$2"
  local cfg
  cfg="$(state_profile_dir)/config.toml"

  if [[ ! -f "$cfg" ]]; then
    printf '%s\n' "$default"
    return 0
  fi
  if ! command -v dasel >/dev/null 2>&1; then
    printf '%s\n' "$default"
    return 0
  fi

  local val
  val="$(dasel -i toml "$key" < "$cfg" 2>/dev/null || true)"
  # dasel v3 wraps string scalars in single quotes — strip them
  val="${val#\'}"
  val="${val%\'}"
  if [[ -z "$val" ]]; then
    printf '%s\n' "$default"
  else
    printf '%s\n' "$val"
  fi
}
