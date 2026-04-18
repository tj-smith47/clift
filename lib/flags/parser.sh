#!/usr/bin/env bash
# clift Argument Parser
# Sourced by router.sh. Exposes one function: clift_parse_args.
#
# Usage: clift_parse_args <flag-table-json-path> "$@"
#
# On success: exports CLIFT_FLAG_<NAME> and CLIFT_POS_<N> env vars; returns 0.
# On error: prints error to stderr and returns 1.

# shellcheck disable=SC2317  # `exit 0` fallback fires only if file is run directly
if [[ -n "${_CLIFT_PARSER_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
_CLIFT_PARSER_LOADED=1

_CLIFT_PARSER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CLIFT_PARSER_DIR/errors.sh"

# Transform a flag long name ("dry-run") to its env var name ("CLIFT_FLAG_DRY_RUN")
_clift_var_name() {
  local upper="${1^^}"
  _CLIFT_VAR="CLIFT_FLAG_${upper//-/_}"
}

# Write the CLIFT_FLAGS tempfile (NUL-separated <name>=<value> records) that
# the runtime prelude materializes into `declare -A CLIFT_FLAGS`. No-op when
# CLIFT_FLAGS_FILE is unset (unit-test / external-caller path — see emit-guard
# comment in clift_parse_args). Relies on bash dynamic scoping to read the
# caller's `_ft_type` assoc array (populated in clift_parse_args).
#
# Phase 3 bench-headroom: iterates all known flags. If that becomes a
# bottleneck, track only set/defaulted names during parse (a `_ft_touched`
# parallel map) and emit just those.
_clift_emit_flags_file() {
  [[ -z "${CLIFT_FLAGS_FILE:-}" ]] && return 0
  # Skip when the router will intercept before the prelude runs — the file
  # would be written and abandoned (--help execs into help/detail.sh which
  # never reads CLIFT_FLAGS_FILE; --version exits before the prelude).
  if [[ "${CLIFT_FLAG_HELP:-}" == "true" || "${CLIFT_FLAG_VERSION:-}" == "true" ]]; then
    return 0
  fi
  local _en _etype _evar _ecount_var _ecount _ei _eval _ejoined _eitem_var
  : > "$CLIFT_FLAGS_FILE"
  for _en in "${!_ft_type[@]}"; do
    _etype="${_ft_type[$_en]}"
    _clift_var_name "$_en"; _evar="$_CLIFT_VAR"
    case "$_etype" in
      list)
        _ecount_var="${_evar}_COUNT"
        _ecount="${!_ecount_var:-0}"
        (( _ecount == 0 )) && continue
        _ejoined=""
        for (( _ei=1; _ei<=_ecount; _ei++ )); do
          _eitem_var="${_evar}_${_ei}"
          if (( _ei == 1 )); then
            _ejoined="${!_eitem_var:-}"
          else
            _ejoined="${_ejoined},${!_eitem_var:-}"
          fi
        done
        printf '%s=%s\0' "$_en" "$_ejoined" >> "$CLIFT_FLAGS_FILE"
        ;;
      *)
        # bool / string / int: record only if the env var is set.
        # Unset bool means "not provided" — absent from CLIFT_FLAGS too.
        [[ -z "${!_evar+x}" ]] && continue
        _eval="${!_evar}"
        printf '%s=%s\0' "$_en" "$_eval" >> "$CLIFT_FLAGS_FILE"
        ;;
    esac
  done
}

clift_parse_args() {
  local flag_table_file="$1"; shift

  if [[ ! -f "$flag_table_file" ]]; then
    echo "error: flag table file not found: $flag_table_file" >&2
    return 1
  fi

  local table_json
  table_json="$(<"$flag_table_file")"

  # Pre-build lookup tables, known names, required flags, AND defaults in a
  # single jq call — the only fork in the parser init path.
  # Output: eight NUL-separated sections via process substitution (NUL bytes
  # can't survive bash command substitution, so we read from an fd).
  #   1. name\x01short\x01type lines  (lookup tables)
  #   2. space-joined known names      (error suggestions; includes aliases)
  #   3. required flag names           (one per line)
  #   4. name\x01type\x01default lines (non-bool defaults)
  #   5. alias\x01canonical-name lines (alias -> canonical lookup)
  #   6. name\x01message lines         (deprecated flags; empty/null filtered)
  #   7. name\x01group\x01mode lines   (group membership; mode="exclusive"|"requires-all")
  #   8. name\x01choices-csv\x01pattern lines (value validation; empty fields
  #                                    mean "no constraint" for that column)
  local _ft_lines="" known_names="" _required_names="" _defaults_tsv="" _alias_lines="" _deprecated_lines="" _group_lines="" _valid_lines=""
  {
    IFS= read -r -d '' _ft_lines || true
    IFS= read -r -d '' known_names || true
    IFS= read -r -d '' _required_names || true
    IFS= read -r -d '' _defaults_tsv || true
    IFS= read -r -d '' _alias_lines || true
    IFS= read -r -d '' _deprecated_lines || true
    IFS= read -r -d '' _group_lines || true
    IFS= read -r -d '' _valid_lines || true
  } < <(jq -j '
    ([.[] | [.name, (.short // ""), .type] | join("\u0001")] | join("\n")) + "\u0000" +
    ([.[] | [.name] + (.aliases // []) | .[]] | join(" ")) + "\u0000" +
    ([.[] | select(.required == true) | .name] | join("\n")) + "\u0000" +
    ([.[] | select(.default != null and .type != "bool")
      | [.name, .type, (.default | tostring)] | join("\u0001")]
      | join("\n")) + "\u0000" +
    ([.[] as $f | ($f.aliases // [])[] | [., $f.name] | join("\u0001")]
      | join("\n")) + "\u0000" +
    ([.[] | select((.deprecated // "") != "")
      | [.name, .deprecated] | join("\u0001")]
      | join("\n")) + "\u0000" +
    ([.[] | select((.group // "") != "")
      | [.name, .group,
         (if .exclusive == true then "exclusive"
          elif (.requires // "") == "all" then "requires-all"
          else "" end)]
      | select(.[2] != "")
      | join("\u0001")]
      | join("\n")) + "\u0000" +
    ([.[] | select(((.choices // null) != null) or ((.pattern // "") != ""))
      | [.name,
         (if ((.choices // null) | type) == "array"
          then (.choices | map(tostring) | join(","))
          else "" end),
         (.pattern // "")]
      | join("\u0001")]
      | join("\n")) + "\u0000"
  ' <<< "$table_json")

  # Co-locate all _ft_* lookup maps here so future readers see the full set at
  # a glance. _ft_choices / _ft_pattern are populated further below from the
  # value-validation rows.
  declare -A _ft_type _ft_name_by_short _ft_alias_to_name _ft_deprecated _ft_choices _ft_pattern
  while IFS=$'\x01' read -r _fn _fs _ftype; do
    [[ -z "$_fn" ]] && continue
    _ft_type["$_fn"]="$_ftype"
    [[ -n "$_fs" ]] && _ft_name_by_short["$_fs"]="$_fn"
  done <<< "$_ft_lines"

  # Populate alias → canonical-name map. Empty lines (no aliases declared)
  # are skipped.
  while IFS=$'\x01' read -r _alias _canonical; do
    [[ -z "$_alias" ]] && continue
    _ft_alias_to_name["$_alias"]="$_canonical"
  done <<< "$_alias_lines"

  # Populate canonical-name → deprecation-message map. Flags without a
  # `deprecated` field (or with empty string) don't appear here.
  while IFS=$'\x01' read -r _dname _dmsg; do
    [[ -z "$_dname" ]] && continue
    _ft_deprecated["$_dname"]="$_dmsg"
  done <<< "$_deprecated_lines"

  # Populate group membership. _group_members[$group] is a space-separated
  # list of member canonical names (leading space for safe substring matching).
  # _group_mode[$group] is "exclusive" or "requires-all".
  declare -A _group_members _group_mode
  while IFS=$'\x01' read -r _gname _ggroup _gmode; do
    [[ -z "$_gname" ]] && continue
    # Safe: group name regex-restricted at compile (see validate.sh)
    _group_members["$_ggroup"]="${_group_members[$_ggroup]:+${_group_members[$_ggroup]} }$_gname"
    _group_mode["$_ggroup"]="$_gmode"
  done <<< "$_group_lines"

  # Populate value-validation maps. _ft_choices[name] is the comma-separated
  # choice list (empty means no constraint); _ft_pattern[name] is the regex
  # pattern (empty means no constraint). Either or both may be set. Arrays
  # themselves are declared at the top of the function next to the other
  # _ft_* maps for scan-ability.
  while IFS=$'\x01' read -r _vname _vchoices _vpattern; do
    [[ -z "$_vname" ]] && continue
    [[ -n "$_vchoices" ]] && _ft_choices["$_vname"]="$_vchoices"
    [[ -n "$_vpattern" ]] && _ft_pattern["$_vname"]="$_vpattern"
  done <<< "$_valid_lines"

  # Validate a scalar value against a flag's choices/pattern constraints.
  # Returns 1 (via the err helper) on failure. For list flags, the caller
  # invokes this once per element.
  _clift_validate_value() {
    local name="$1" value="$2"
    local choices="${_ft_choices[$name]:-}"
    local pattern="${_ft_pattern[$name]:-}"
    if [[ -n "$choices" ]]; then
      local _cl=" ${choices//,/ } "
      if [[ "$_cl" != *" $value "* ]]; then
        clift_err_invalid_choice "$name" "$value" "$choices"
        return 1
      fi
    fi
    if [[ -n "$pattern" ]]; then
      # SC2076: pattern must NOT be quoted — bash =~ requires unquoted regex on RHS.
      # shellcheck disable=SC2076
      if ! [[ "$value" =~ $pattern ]]; then
        clift_err_invalid_pattern "$name" "$value" "$pattern"
        return 1
      fi
    fi
    return 0
  }

  # Emit a one-shot deprecation warning for a canonical flag name if one is
  # registered. The warning fires per-invocation, not per-occurrence, so
  # `--old x --old y` warns once — matching Cobra's behavior.
  declare -A _warned_deprecated
  _clift_warn_deprecated() {
    local name="$1"
    local msg="${_ft_deprecated[$name]:-}"
    [[ -z "$msg" ]] && return 0
    [[ -n "${_warned_deprecated[$name]:-}" ]] && return 0
    _warned_deprecated["$name"]=1
    printf '%s\n' "warning: --${name} is deprecated: ${msg}" >&2
  }

  # Apply defaults first. For list flags, we track "defaulted" state separately
  # so that when a user passes the first --list=value, we can wipe the default
  # and start fresh — a user-supplied value REPLACES a default, not appends to
  # it. This matches Cobra semantics.
  #
  # Persistent flags bound pre-command by the wrapper are already exported;
  # don't overwrite them with defaults here (user-provided wins over default
  # by position — the wrapper's bind IS a user value). The wrapper advertises
  # which names it bound via CLIFT_PERSIST_BOUND (space-separated).
  local _persist_bound=" ${CLIFT_PERSIST_BOUND:-} "
  declare -A _list_was_defaulted
  while IFS=$'\x01' read -r dname dtype ddefault; do
    [[ -z "$dname" ]] && continue
    # Skip default application for flags the wrapper already bound. Treat
    # wrapper-bound list flags as "not defaulted" so the clear-on-first-use
    # logic doesn't wipe them.
    if [[ "$_persist_bound" == *" $dname "* ]]; then
      continue
    fi
    _clift_var_name "$dname"; local dvar="$_CLIFT_VAR"
    if [[ "$dtype" == "list" ]]; then
      if [[ -n "$ddefault" ]]; then
        local idx=0
        IFS=',' read -ra items <<< "$ddefault"
        for item in "${items[@]}"; do
          idx=$((idx+1))
          export "${dvar}_${idx}=${item}"
        done
        export "${dvar}_COUNT=${idx}"
      else
        # Empty string default → empty list, not a single empty element.
        export "${dvar}_COUNT=0"
      fi
      _list_was_defaulted["$dname"]=1
    else
      export "${dvar}=${ddefault}"
    fi
  done <<< "$_defaults_tsv"

  # Helper: clear a list flag's defaulted values before appending a user value.
  # Only fires once per list flag per parse.
  _clift_list_clear_if_defaulted() {
    local name="$1" var
    _clift_var_name "$name"; var="$_CLIFT_VAR"
    if [[ -n "${_list_was_defaulted[$name]:-}" ]]; then
      local count_var="${var}_COUNT"
      local cnt="${!count_var:-0}"
      for (( i=1; i<=cnt; i++ )); do
        unset "${var}_${i}"
      done
      export "${var}_COUNT=0"
      unset "_list_was_defaulted[$name]"
    fi
  }

  # Set a parsed flag value. Handles int validation, list append with comma
  # splitting, and plain string/bool export. Centralizes logic shared between
  # long-flag, short-flag, and -x=value code paths.
  # Args: tok name type value
  _clift_set_flag_value() {
    local tok="$1" name="$2" type="$3" value="$4"
    local var
    _clift_var_name "$name"; var="$_CLIFT_VAR"

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
        local _items _item
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

      # Resolve alias to canonical name before lookup.
      if [[ -n "${_ft_alias_to_name[$name]:-}" ]]; then
        name="${_ft_alias_to_name[$name]}"
      fi

      if [[ -z "${_ft_type[$name]+x}" ]]; then
        clift_err_unknown_flag "$tok" "$known_names"
        return 1
      fi
      local type="${_ft_type[$name]}"
      local var
      _clift_var_name "$name"; var="$_CLIFT_VAR"

      if [[ "$type" == "bool" ]]; then
        # Bool flags do not accept inline values. Writing `--flag=foo`
        # silently storing "foo" (or treating empty as "true") led to
        # confusing command scripts; explicit rejection is the right UX.
        if [[ "$has_inline" == true ]]; then
          clift_err_bool_with_value "$name" "$inline_val"
          return 1
        fi
        _clift_set_flag_value "$tok" "$name" "$type" "true" || return 1
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
      _clift_warn_deprecated "$name"
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
        local name="${_ft_name_by_short[$short]:-}"
        if [[ -z "$name" ]]; then
          clift_err_unknown_flag "$tok" "$known_names"
          return 1
        fi
        local type="${_ft_type[$name]}"
        local var
        _clift_var_name "$name"; var="$_CLIFT_VAR"

        # Mirror the long-flag rule: bool flags reject inline values.
        if [[ "$type" == "bool" ]]; then
          clift_err_bool_with_value "$name" "$value"
          return 1
        fi

        _clift_set_flag_value "$tok" "$name" "$type" "$value" || return 1
        seen_names="$seen_names $name"
        _clift_warn_deprecated "$name"
        shift
        continue
      fi

      # Cluster or single short
      if (( ${#rest} > 1 )); then
        # Check all-bool
        local all_bool=true nonbool_letter=""
        for (( i=0; i<${#rest}; i++ )); do
          local c="${rest:$i:1}"
          local name_for_c="${_ft_name_by_short[$c]:-}"
          if [[ -z "$name_for_c" ]]; then
            clift_err_unknown_flag "-$c" "$known_names"
            return 1
          fi
          local t="${_ft_type[$name_for_c]}"
          if [[ "$t" != "bool" ]]; then
            all_bool=false
            nonbool_letter="$c"
            break
          fi
        done
        if [[ "$all_bool" != true ]]; then
          clift_err_nonbool_in_cluster "$nonbool_letter" "$tok" "command flag '${_ft_name_by_short[$nonbool_letter]:-unknown}' (type: ${_ft_type[${_ft_name_by_short[$nonbool_letter]:-}]:-unknown})"
          return 1
        fi
        # All bool — set each
        for (( i=0; i<${#rest}; i++ )); do
          local c="${rest:$i:1}"
          local n="${_ft_name_by_short[$c]}"
          local v
          _clift_var_name "$n"; v="$_CLIFT_VAR"
          export "${v}=true"
          seen_names="$seen_names $n"
          _clift_warn_deprecated "$n"
        done
        shift
        continue
      fi

      # Single short with separate value
      local short="$rest"
      local name="${_ft_name_by_short[$short]:-}"
      if [[ -z "$name" ]]; then
        clift_err_unknown_flag "$tok" "$known_names"
        return 1
      fi
      local type="${_ft_type[$name]}"
      local var
      _clift_var_name "$name"; var="$_CLIFT_VAR"

      if [[ "$type" == "bool" ]]; then
        _clift_set_flag_value "$tok" "$name" "$type" "true"
        seen_names="$seen_names $name"
        _clift_warn_deprecated "$name"
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
      _clift_warn_deprecated "$name"
      shift
      continue
    fi

    # Positional
    positionals+=("$tok")
    shift
  done

  # Emit positionals (safe expansion for bash < 4.4 with set -u)
  export "CLIFT_POS_COUNT=${#positionals[@]}"
  local pi=0
  for p in "${positionals[@]+"${positionals[@]}"}"; do
    pi=$((pi+1))
    export "CLIFT_POS_${pi}=${p}"
  done

  # Group constraint validation. For each registered group, walk the member
  # list and partition into "set" (seen this invocation) vs "unset". Then:
  #   - exclusive: if >1 members set, error naming all set members.
  #   - requires-all: if 0 < set < total, error naming the missing members.
  # A single-member group is a no-op by design — you can't violate an
  # exclusive constraint alone, and a lone requires-all trivially satisfies.
  local _grp
  for _grp in "${!_group_members[@]}"; do
    local _members="${_group_members[$_grp]}"
    local _mode="${_group_mode[$_grp]}"
    local _set_members="" _missing_members="" _set_count=0 _total=0
    local _m
    for _m in $_members; do
      _total=$((_total+1))
      if [[ " $seen_names " == *" $_m "* ]]; then
        _set_members="$_set_members $_m"
        _set_count=$((_set_count+1))
      else
        _missing_members="$_missing_members $_m"
      fi
    done
    case "$_mode" in
      exclusive)
        if (( _set_count > 1 )); then
          clift_err_mutex_group "$_grp" "$_set_members"
          return 1
        fi
        ;;
      requires-all)
        if (( _set_count > 0 && _set_count < _total )); then
          clift_err_requires_all_group "$_grp" "$_set_members" "$_missing_members"
          return 1
        fi
        ;;
    esac
  done

  # Value validation: choices + pattern. Runs AFTER assignment (so defaults
  # are also validated — catching stale defaults that would otherwise slip past
  # a choices tightening) and BEFORE required-flag validation, so the error
  # named is the one the user can actually fix. For list flags, each element
  # is validated individually; the first failing element reports the error.
  #
  # Iterate in lexicographic order of flag name so that when multiple flags
  # have invalid values the reported error is deterministic across machines —
  # bash associative-array key order is otherwise undefined.
  local _vn _vtype _vvar _vcount _vi _vitem
  for _vn in $(printf '%s\n' "${!_ft_type[@]}" | sort); do
    # Skip flags with no constraint declared
    if [[ -z "${_ft_choices[$_vn]:-}" && -z "${_ft_pattern[$_vn]:-}" ]]; then
      continue
    fi
    _vtype="${_ft_type[$_vn]}"
    # Bool flags reject choices/pattern at compile; defensively skip here too.
    [[ "$_vtype" == "bool" ]] && continue
    _clift_var_name "$_vn"; _vvar="$_CLIFT_VAR"

    if [[ "$_vtype" == "list" ]]; then
      _vcount_var="${_vvar}_COUNT"
      _vcount="${!_vcount_var:-0}"
      (( _vcount == 0 )) && continue
      for (( _vi=1; _vi<=_vcount; _vi++ )); do
        _vitem_var="${_vvar}_${_vi}"
        _vitem="${!_vitem_var:-}"
        _clift_validate_value "$_vn" "$_vitem" || return 1
      done
    else
      # string/int — unset means "not provided, not defaulted"; skip.
      [[ -z "${!_vvar+x}" ]] && continue
      _clift_validate_value "$_vn" "${!_vvar}" || return 1
    fi
  done

  # Required-flag validation (uses pre-computed list from initial jq batch)
  while IFS= read -r rname; do
    [[ -z "$rname" ]] && continue
    if [[ " $seen_names " != *" $rname "* ]]; then
      clift_err_missing_required "$rname"
      return 1
    fi
  done <<< "$_required_names"

  # Emit the CLIFT_FLAGS assoc-array source-of-truth. The prelude reads this
  # file (NUL-separated <name>=<value> records) and materializes
  # declare -A CLIFT_FLAGS with dash-preserving keys. The existing
  # CLIFT_FLAG_<NAME> env vars above stay untouched for back-compat.
  #
  # Emit once at end-of-parse (not per-assignment) so:
  #   - list flags record a single comma-joined value (no dup key rewrite)
  #   - defaults, persistent-flag pre-binds, and user values are all included
  #   - a failing parse writes nothing (router's trap still cleans the file)
  #
  # Intentional: parser is also invoked from unit tests (and potentially other
  # external callers) without a router-side tempfile; _clift_emit_flags_file
  # no-ops in that case. The router always sets CLIFT_FLAGS_FILE for real
  # invocations, so a regression there would surface as the assoc array
  # being empty in user scripts (covered by flags_assoc.bats).
  _clift_emit_flags_file

  return 0
}
