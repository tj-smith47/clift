#!/usr/bin/env bash
# clift Argument Parser
# Sourced by router.sh. Exposes one function: clift_parse_args.
#
# Usage: clift_parse_args <flag-table-json-path> "$@"
#
# On success: exports CLIFT_FLAG_<NAME> and CLIFT_POS_<N> env vars; returns 0.
# On error: prints error to stderr and returns 1.

if [[ -n "${_CLIFT_PARSER_LOADED:-}" ]]; then return 0; fi
_CLIFT_PARSER_LOADED=1

_CLIFT_PARSER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CLIFT_PARSER_DIR/errors.sh"

# Transform a flag long name ("dry-run") to its env var name ("CLIFT_FLAG_DRY_RUN")
_clift_var_name() {
  local name="$1"
  local upper="${name^^}"
  echo "CLIFT_FLAG_${upper//-/_}"
}

# Look up a flag entry by name or short. Prints the JSON entry or empty.
_clift_find_flag() {
  local table_json="$1" key="$2" field="$3"
  jq -c --arg k "$key" ".[] | select(.${field} == \$k)" <<< "$table_json" | head -1
}

clift_parse_args() {
  local flag_table_file="$1"; shift

  if [[ ! -f "$flag_table_file" ]]; then
    echo "error: flag table file not found: $flag_table_file" >&2
    return 1
  fi

  local table_json
  table_json="$(cat "$flag_table_file")"

  # Pre-compute known names for error suggestions
  local known_names
  known_names="$(jq -r '[.[].name] | join(" ")' <<< "$table_json")"

  # Apply defaults first. For list flags, we track "defaulted" state separately
  # so that when a user passes the first --list=value, we can wipe the default
  # and start fresh — a user-supplied value REPLACES a default, not appends to
  # it. This matches Cobra semantics.
  declare -A _list_was_defaulted
  local defaults
  defaults="$(jq -c '.[] | select(.default != null and .type != "bool") | {name, default, type}' <<< "$table_json")"
  while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    local dname dtype ddefault dvar
    dname="$(jq -r '.name' <<< "$d")"
    dtype="$(jq -r '.type' <<< "$d")"
    ddefault="$(jq -r '.default' <<< "$d")"
    dvar="$(_clift_var_name "$dname")"
    if [[ "$dtype" == "list" ]]; then
      local idx=0
      IFS=',' read -ra items <<< "$ddefault"
      for item in "${items[@]}"; do
        idx=$((idx+1))
        export "${dvar}_${idx}=${item}"
      done
      export "${dvar}_COUNT=${idx}"
      _list_was_defaulted["$dname"]=1
    else
      export "${dvar}=${ddefault}"
    fi
  done <<< "$defaults"

  # Helper: clear a list flag's defaulted values before appending a user value.
  # Only fires once per list flag per parse.
  _clift_list_clear_if_defaulted() {
    local name="$1" var
    var="$(_clift_var_name "$name")"
    if [[ -n "${_list_was_defaulted[$name]:-}" ]]; then
      local count_var="${var}_COUNT"
      local cnt="${!count_var:-0}"
      for (( i=1; i<=cnt; i++ )); do
        unset "${var}_${i}"
      done
      export "${var}_COUNT=0"
      unset _list_was_defaulted["$name"]
    fi
  }

  # Set a parsed flag value. Handles int validation, list append with comma
  # splitting, and plain string/bool export. Centralizes logic shared between
  # long-flag, short-flag, and -x=value code paths.
  # Args: tok name type value
  _clift_set_flag_value() {
    local tok="$1" name="$2" type="$3" value="$4"
    local var
    var="$(_clift_var_name "$name")"

    case "$type" in
      bool)
        export "${var}=${value}"
        ;;
      int)
        if [[ ! "$value" =~ ^-?[0-9]+$ ]]; then
          clift_err_wrong_type "$tok" "an integer" "$value"
          return 1
        fi
        export "${var}=${value}"
        ;;
      list)
        _clift_list_clear_if_defaulted "$name"
        # Spec §5.1 step 6: list values split on commas
        IFS=',' read -ra _items <<< "$value"
        local count_var="${var}_COUNT"
        local current="${!count_var:-0}"
        for _item in "${_items[@]}"; do
          current=$((current+1))
          export "${var}_${current}=${_item}"
        done
        export "${count_var}=${current}"
        ;;
      *)
        export "${var}=${value}"
        ;;
    esac
  }

  # Main parse loop
  local positionals=() seen_names=""
  while (( $# > 0 )); do
    local tok="$1"

    # End-of-flags marker
    if [[ "$tok" == "--" ]]; then
      shift
      positionals+=("$@")
      break
    fi

    # Long flag: --name or --name=value
    if [[ "$tok" == --* ]]; then
      local name="${tok#--}" inline_val="" has_inline=false
      if [[ "$name" == *=* ]]; then
        inline_val="${name#*=}"
        name="${name%%=*}"
        has_inline=true
      fi

      local entry
      entry="$(_clift_find_flag "$table_json" "$name" name)"
      if [[ -z "$entry" ]]; then
        clift_err_unknown_flag "$tok" "$known_names"
        return 1
      fi

      local type
      type="$(jq -r '.type' <<< "$entry")"
      local var
      var="$(_clift_var_name "$name")"

      if [[ "$type" == "bool" ]]; then
        if [[ "$has_inline" == true ]]; then
          _clift_set_flag_value "$tok" "$name" "$type" "$inline_val"
        else
          _clift_set_flag_value "$tok" "$name" "$type" "true"
        fi
      else
        local value
        if [[ "$has_inline" == true ]]; then
          value="$inline_val"
        else
          if (( $# < 2 )); then
            clift_err_missing_value "$tok"
            return 1
          fi
          shift
          value="$1"
        fi
        _clift_set_flag_value "$tok" "$name" "$type" "$value" || return 1
      fi

      seen_names="$seen_names $name"
      shift
      continue
    fi

    # Short flag: -x, -x value, -xyz cluster, -x=value
    if [[ "$tok" == -?* ]]; then
      local rest="${tok#-}"

      # -x=value
      if [[ "$rest" == ?=* ]]; then
        local short="${rest:0:1}"
        local value="${rest#*=}"
        local entry
        entry="$(_clift_find_flag "$table_json" "$short" short)"
        if [[ -z "$entry" ]]; then
          clift_err_unknown_flag "$tok" "$known_names"
          return 1
        fi
        local name type var
        name="$(jq -r '.name' <<< "$entry")"
        type="$(jq -r '.type' <<< "$entry")"
        var="$(_clift_var_name "$name")"

        _clift_set_flag_value "$tok" "$name" "$type" "$value" || return 1
        seen_names="$seen_names $name"
        shift
        continue
      fi

      # Cluster or single short
      if (( ${#rest} > 1 )); then
        # Check all-bool
        local all_bool=true nonbool_letter=""
        for (( i=0; i<${#rest}; i++ )); do
          local c="${rest:$i:1}"
          local e
          e="$(_clift_find_flag "$table_json" "$c" short)"
          if [[ -z "$e" ]]; then
            clift_err_unknown_flag "-$c" "$known_names"
            return 1
          fi
          local t
          t="$(jq -r '.type' <<< "$e")"
          if [[ "$t" != "bool" ]]; then
            all_bool=false
            nonbool_letter="$c"
            break
          fi
        done
        if [[ "$all_bool" != true ]]; then
          clift_err_nonbool_in_cluster "$nonbool_letter" "$tok" "merged flag table"
          return 1
        fi
        # All bool — set each
        for (( i=0; i<${#rest}; i++ )); do
          local c="${rest:$i:1}"
          local e n v
          e="$(_clift_find_flag "$table_json" "$c" short)"
          n="$(jq -r '.name' <<< "$e")"
          v="$(_clift_var_name "$n")"
          export "${v}=true"
          seen_names="$seen_names $n"
        done
        shift
        continue
      fi

      # Single short with separate value
      local short="$rest"
      local entry
      entry="$(_clift_find_flag "$table_json" "$short" short)"
      if [[ -z "$entry" ]]; then
        clift_err_unknown_flag "$tok" "$known_names"
        return 1
      fi
      local name type var
      name="$(jq -r '.name' <<< "$entry")"
      type="$(jq -r '.type' <<< "$entry")"
      var="$(_clift_var_name "$name")"

      if [[ "$type" == "bool" ]]; then
        _clift_set_flag_value "$tok" "$name" "$type" "true"
        seen_names="$seen_names $name"
        shift
        continue
      fi

      if (( $# < 2 )); then
        clift_err_missing_value "$tok"
        return 1
      fi
      shift
      local value="$1"
      _clift_set_flag_value "$tok" "$name" "$type" "$value" || return 1
      seen_names="$seen_names $name"
      shift
      continue
    fi

    # Positional
    positionals+=("$tok")
    shift
  done

  # Emit positionals
  export "CLIFT_POS_COUNT=${#positionals[@]}"
  local pi=0
  for p in "${positionals[@]}"; do
    pi=$((pi+1))
    export "CLIFT_POS_${pi}=${p}"
  done

  # Required-flag validation
  local required_names
  required_names="$(jq -r '.[] | select(.required == true) | .name' <<< "$table_json")"
  while IFS= read -r rname; do
    [[ -z "$rname" ]] && continue
    if [[ " $seen_names " != *" $rname "* ]]; then
      clift_err_missing_required "$rname"
      return 1
    fi
  done <<< "$required_names"

  return 0
}
