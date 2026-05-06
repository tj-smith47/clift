#!/usr/bin/env bash
# Standalone-argv → CLIFT_FLAGS / CLIFT_POS_* fallback.
#
# Library — does NOT call `set -euo pipefail`. See lib/store.sh for the
# rationale: shell options leak into the caller and conditionals here
# would abort the caller on benign no-match cases.
#
# Production path: the framework router populates CLIFT_FLAGS and
# CLIFT_FLAG_* before exec'ing the command script. Direct invocation
# (`bash cmds/add/add.sh ...`) leaves CLIFT_FLAGS unset and $@ holding
# raw argv — bm_argv_parse fills the gap so each cmd script can read
# the same env-var contract regardless of how it was launched.
#
# Spec format (JSON array):
#   [{"name":"tag","type":"list"},
#    {"name":"format","type":"string"},
#    {"name":"force","type":"bool"}]

# shellcheck disable=SC2317
if [[ -n "${_BM_ARGV_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
_BM_ARGV_LOADED=1

bm_argv_parse() {
  local spec="$1"; shift
  declare -gA CLIFT_FLAGS=()
  local -A _bm_types=()
  local line n t
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    n="${line%%=*}"; t="${line#*=}"
    _bm_types["$n"]="$t"
  done < <(jq -r '.[] | "\(.name)=\(.type)"' <<< "$spec" 2>/dev/null)

  local pos_count=0
  local a name val type upper count_var count
  while (( $# > 0 )); do
    a="$1"
    case "$a" in
      --)
        shift
        while (( $# > 0 )); do
          pos_count=$((pos_count+1))
          printf -v "CLIFT_POS_$pos_count" '%s' "$1"
          export "CLIFT_POS_$pos_count"
          shift
        done
        ;;
      --*=*)
        name="${a%%=*}"; name="${name#--}"
        val="${a#*=}"
        _bm_argv_assign "$name" "$val"
        shift
        ;;
      --*)
        name="${a#--}"
        type="${_bm_types[$name]:-string}"
        if [[ "$type" == "bool" ]]; then
          CLIFT_FLAGS["$name"]="true"
          shift
        else
          _bm_argv_assign "$name" "${2:-}"
          if (( $# >= 2 )); then shift 2; else shift; fi
        fi
        ;;
      *)
        # Short alias for --force on rm: treat -f as bool.
        if [[ "$a" == "-f" ]] && [[ "${_bm_types[force]:-}" == "bool" ]]; then
          CLIFT_FLAGS[force]="true"; shift; continue
        fi
        # Short alias for --name on add: -n VAL.
        if [[ "$a" == "-n" ]] && [[ "${_bm_types[name]:-}" == "string" ]]; then
          _bm_argv_assign name "${2:-}"
          if (( $# >= 2 )); then shift 2; else shift; fi
          continue
        fi
        pos_count=$((pos_count+1))
        printf -v "CLIFT_POS_$pos_count" '%s' "$a"
        export "CLIFT_POS_$pos_count"
        shift
        ;;
    esac
  done
  export CLIFT_POS_COUNT="$pos_count"
}

# Internal: set scalar / bump list counter.
_bm_argv_assign() {
  local name="$1" val="$2"
  local type="${_bm_types[$name]:-string}"
  if [[ "$type" == "list" ]]; then
    local upper="${name^^}"; upper="${upper//-/_}"
    local count_var="CLIFT_FLAG_${upper}_COUNT"
    local count="${!count_var:-0}"
    count=$((count+1))
    printf -v "CLIFT_FLAG_${upper}_${count}" '%s' "$val"
    printf -v "$count_var" '%s' "$count"
    export "CLIFT_FLAG_${upper}_${count}"
    export "CLIFT_FLAG_${upper}_COUNT"
  else
    # shellcheck disable=SC2034  # consumed via "${CLIFT_FLAGS[$name]}" by caller
    CLIFT_FLAGS["$name"]="$val"
  fi
}
