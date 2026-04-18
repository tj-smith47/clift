#!/usr/bin/env bash
# clift Flag Schema Validator
# Usage: validate.sh <taskfile-path>
# Reads vars.FLAGS and tasks.*.vars.FLAGS from the given Taskfile
# and validates each entry against the schema in spec §4.2.
#
# Exits 0 if all entries valid; 1 with error message(s) if any invalid.

set -euo pipefail

# shellcheck disable=SC2317  # `exit 0` fallback fires only if file is run directly
if [[ -n "${_CLIFT_VALIDATE_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
_CLIFT_VALIDATE_LOADED=1

# Reserved flag names — derived from the canonical globals.json
_GLOBALS_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/globals.json"
RESERVED_NAMES=()
while IFS= read -r _rn; do RESERVED_NAMES+=("$_rn"); done < <(jq -r '.[].name' "$_GLOBALS_FILE")

# Name regex: lowercase, starts with letter, dashes allowed, NO underscores
NAME_RE='^[a-z][a-z0-9-]*$'
SHORT_RE='^[a-zA-Z0-9]$'
VALID_TYPES=(bool string int list)

# Validate a single flag entry using pre-extracted fields (no jq calls).
# Args: context entry_type name short type required has_default default_val
#       [group has_exclusive exclusive has_requires requires]
_validate_entry_fields() {
  local context="$1"
  local entry_type="$2"
  local name="$3"
  local short="$4"
  local type="$5"
  local required="$6"
  local has_default="$7"
  local default_val="$8"
  local group="${9:-}"
  local has_exclusive="${10:-false}"
  local exclusive="${11:-false}"
  local has_requires="${12:-false}"
  local requires="${13:-}"
  local has_choices="${14:-false}"
  local choices_csv="${15:-}"
  local has_pattern="${16:-false}"
  local pattern="${17:-}"

  # I4: bare-string (or any non-map) entries produce a clean error, no jq leak
  if [[ "$entry_type" != "object" ]]; then
    echo "error: ${context}: flag entry must be a map, got ${entry_type}" >&2
    return 1
  fi

  if [[ -z "$name" ]]; then
    echo "error: ${context}: flag missing 'name'" >&2
    return 1
  fi

  if [[ ! "$name" =~ $NAME_RE ]]; then
    echo "error: ${context}: flag name '$name' must match ${NAME_RE} (no underscores, lowercase)" >&2
    return 1
  fi

  for reserved in "${RESERVED_NAMES[@]}"; do
    if [[ "$name" == "$reserved" ]]; then
      echo "error: ${context}: flag name '$name' is reserved (framework global)" >&2
      return 1
    fi
  done

  # C3: spec §4.3 extended reserved names (env-var namespace collision)
  if [[ "$name" =~ ^arg- ]] || [[ "$name" == "task" ]] || [[ "$name" == "mode" ]]; then
    echo "error: ${context}: flag name '$name' is reserved (env-var namespace collision: CLIFT_ARG_*/CLIFT_TASK/CLIFT_MODE)" >&2
    return 1
  fi

  if [[ -z "$type" ]]; then
    echo "error: ${context}: flag '$name' missing 'type'" >&2
    return 1
  fi

  local type_valid=false
  for t in "${VALID_TYPES[@]}"; do
    [[ "$type" == "$t" ]] && type_valid=true
  done
  if [[ "$type_valid" != true ]]; then
    echo "error: ${context}: flag '$name' has invalid type '$type' (allowed: ${VALID_TYPES[*]})" >&2
    return 1
  fi

  if [[ -n "$short" ]] && [[ ! "$short" =~ $SHORT_RE ]]; then
    echo "error: ${context}: flag '$name' short '$short' must match ${SHORT_RE}" >&2
    return 1
  fi

  # Rule 5: required: true is mutually exclusive with default
  if [[ "$required" == "true" ]] && [[ "$has_default" == "true" ]]; then
    echo "error: ${context}: flag '$name' cannot be both required and have a default" >&2
    return 1
  fi

  # Rule 6: default must be compatible with the declared type
  if [[ "$has_default" == "true" ]]; then
    case "$type" in
      bool)
        echo "error: ${context}: flag '$name' is bool and cannot have a default (presence is the value)" >&2
        return 1
        ;;
      int)
        if [[ ! "$default_val" =~ ^-?[0-9]+$ ]]; then
          echo "error: ${context}: flag '$name' default '${default_val}' is not a valid integer" >&2
          return 1
        fi
        ;;
      list|string)
        # Any string is valid; list parses on commas at runtime
        ;;
    esac
  fi

  # Rule 7: group/exclusive/requires must be well-formed individually. The
  # cross-member consistency check (same modifier across members of a named
  # group, group required when a modifier is set) happens in the caller once
  # all layer entries are seen.
  if [[ "$has_exclusive" == "true" ]]; then
    if [[ "$exclusive" != "true" && "$exclusive" != "false" ]]; then
      echo "error: ${context}: flag '$name' exclusive must be boolean, got '$exclusive'" >&2
      return 1
    fi
  fi

  if [[ "$has_requires" == "true" ]]; then
    if [[ "$requires" != "all" ]]; then
      echo "error: ${context}: flag '$name' requires must be \"all\" (got '$requires')" >&2
      return 1
    fi
  fi

  if [[ -n "$group" ]]; then
    if [[ ! "$group" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]]; then
      echo "error: ${context}: flag '$name' group '$group' must be a non-empty identifier" >&2
      return 1
    fi
  fi

  if [[ "$exclusive" == "true" && -z "$group" ]]; then
    echo "error: ${context}: flag '$name' has exclusive: true without a group" >&2
    return 1
  fi

  if [[ "$has_requires" == "true" && -z "$group" ]]; then
    echo "error: ${context}: flag '$name' has requires without a group" >&2
    return 1
  fi

  # Rule 8: choices/pattern — value validation constraints.
  # Bool flags carry no user-supplied value (presence is the value), so
  # declaring either field on a bool is a compile error.
  if [[ "$type" == "bool" ]]; then
    if [[ "$has_choices" == "true" ]]; then
      echo "error: ${context}: flag '$name' is bool and cannot declare 'choices'" >&2
      return 1
    fi
    if [[ "$has_pattern" == "true" ]]; then
      echo "error: ${context}: flag '$name' is bool and cannot declare 'pattern'" >&2
      return 1
    fi
  fi

  if [[ "$has_choices" == "true" ]]; then
    # Empty choices array compiles down to empty csv (jq produced empty string
    # for zero-length array). Reject as meaningless — no value could pass.
    if [[ -z "$choices_csv" ]]; then
      echo "error: ${context}: flag '$name' has empty 'choices' array" >&2
      return 1
    fi
    # For int-typed flags, every choice must itself parse as an integer —
    # otherwise no user value could ever satisfy both the type check and the
    # choices check. Catch this at compile rather than ship a dead rule.
    if [[ "$type" == "int" ]]; then
      local _ci _citems
      IFS=',' read -ra _citems <<< "$choices_csv"
      for _ci in "${_citems[@]}"; do
        if [[ ! "$_ci" =~ ^-?[0-9]+$ ]]; then
          echo "error: ${context}: flag '$name' is int but 'choices' contains non-integer '$_ci'" >&2
          return 1
        fi
      done
    fi
    # Default must be one of the listed choices. For list-type defaults, each
    # comma-split element must appear. Defense against narrowing `choices` and
    # forgetting to update a stale default.
    if [[ "$has_default" == "true" && "$type" != "bool" ]]; then
      local _choice_list=" ${choices_csv//,/ } "
      if [[ "$type" == "list" ]]; then
        local _d _dflt_items
        IFS=',' read -ra _dflt_items <<< "$default_val"
        for _d in "${_dflt_items[@]}"; do
          [[ -z "$_d" ]] && continue
          if [[ "$_choice_list" != *" $_d "* ]]; then
            echo "error: ${context}: flag '$name' default element '$_d' is not in choices (${choices_csv//,/, })" >&2
            return 1
          fi
        done
      else
        if [[ "$_choice_list" != *" $default_val "* ]]; then
          echo "error: ${context}: flag '$name' default '$default_val' is not in choices (${choices_csv//,/, })" >&2
          return 1
        fi
      fi
    fi
  fi

  if [[ "$has_pattern" == "true" ]]; then
    # Literal newlines in a pattern break the runtime `[[ =~ ]]` test and are
    # almost always a YAML-literal mishap. Reject early with a clear message.
    if [[ "$pattern" == *$'\n'* ]]; then
      echo "error: ${context}: flag '$name' pattern contains a literal newline" >&2
      return 1
    fi
    if [[ -z "$pattern" ]]; then
      echo "error: ${context}: flag '$name' has empty 'pattern'" >&2
      return 1
    fi
    # Syntactically validate the regex by running it through bash's own `[[ =~ ]]`
    # in a subshell (runtime uses the same operator, so compile-time rejection
    # here exactly matches runtime acceptance). A malformed regex makes `[[ =~ ]]`
    # exit 2 and print "syntax error" on stderr; the subshell is load-bearing
    # under set -e (caller inherits pipefail+errexit from compile.sh), so we
    # keep the parens and silence the SC2234 style warning explicitly.
    #
    # Single-subshell form: capture the exit code directly. Bash returns 2 for
    # real regex syntax errors and 1 for "no match on empty string" (harmless —
    # an empty string simply not matching a valid pattern). Only rc==2 is a
    # compile-time failure. `|| true` absorbs the non-zero exit so the caller's
    # errexit doesn't abort before we inspect $rc.
    local _rc=0
    # shellcheck disable=SC2234
    ( [[ "" =~ $pattern ]] ) 2>/dev/null || _rc=$?
    if (( _rc == 2 )); then
      echo "error: ${context}: flag '$name' has invalid regex pattern '$pattern'" >&2
      return 1
    fi
  fi

  return 0
}

# Validate every entry in a FLAGS layer. Uses a single jq TSV batch emission
# so the per-entry cost is a single bash loop iteration (no subprocess forks).
# Takes the layer as pre-normalized JSON so there's at most one jq fork per
# layer regardless of entry count.
_validate_layer() {
  local layer_json="$1"
  local context="$2"

  # Null/absent/empty layer is fine
  if [[ "$layer_json" == "null" ]] || [[ -z "$layer_json" ]] || [[ "$layer_json" == "[]" ]]; then
    return 0
  fi

  # Emit one TSV row per entry: index, entry_type, name, short, type,
  # required, has_default_key, default_value, aliases_csv. has_default_key
  # distinguishes "no default" from "default: null", which matters for the
  # required-vs-default mutual-exclusion rule. Bare-string (non-map) entries
  # get entry_type=string and empty fields — _validate_entry_fields rejects
  # them with a clean message. aliases_csv is a comma-separated list of
  # alias strings (commas aren't permitted in flag names, so this is
  # unambiguous).
  #
  # Every field is prefixed with a literal "x" sentinel because bash's `read`
  # with `IFS=$'\t'` collapses runs of tabs (tabs are IFS-whitespace in bash),
  # which would eat empty fields and shift columns. The sentinel guarantees
  # no field is ever empty; we strip it after reading.
  local tsv
  tsv="$(echo "$layer_json" | jq -r '
    to_entries[] |
    [ "x" + (.key|tostring),
      "x" + (.value | type),
      "x" + (if (.value|type) == "object" then (.value.name // "") else "" end),
      "x" + (if (.value|type) == "object" then (.value.short // "") else "" end),
      "x" + (if (.value|type) == "object" then (.value.type // "") else "" end),
      "x" + (if (.value|type) == "object" then (.value.required // false | tostring) else "false" end),
      "x" + (if (.value|type) == "object" then (.value | has("default") | tostring) else "false" end),
      "x" + (if (.value|type) == "object" then (.value.default // "" | tostring) else "" end),
      "x" + (if (.value|type) == "object" then ((.value.aliases // []) | join(",")) else "" end),
      "x" + (if (.value|type) == "object" then (.value.group // "") else "" end),
      "x" + (if (.value|type) == "object" then (.value | has("exclusive") | tostring) else "false" end),
      "x" + (if (.value|type) == "object" then (.value.exclusive // false | tostring) else "false" end),
      "x" + (if (.value|type) == "object" then (.value | has("requires") | tostring) else "false" end),
      "x" + (if (.value|type) == "object" then (.value.requires // "" | tostring) else "" end),
      "x" + (if (.value|type) == "object" then (.value | has("choices") | tostring) else "false" end),
      "x" + (if (.value|type) == "object"
             then (if ((.value.choices // null) | type) == "array"
                   then (.value.choices | map(tostring) | join(","))
                   else "__CLIFT_NONARRAY__" end)
             else "" end),
      "x" + (if (.value|type) == "object" then (.value | has("pattern") | tostring) else "false" end),
      "x" + (if (.value|type) == "object" then (.value.pattern // "" | tostring) else "" end)
    ] | @tsv
  ')"

  local seen_names="" seen_shorts="" seen_envs=""
  # seen_name_owner maps a name/alias back to the flag that introduced it, so
  # a collision error can name both ends of the conflict.
  declare -A seen_name_owner
  # Track group → modifier ("exclusive"|"requires-all"|"none") for the
  # cross-member consistency check. A named group must have exactly one
  # modifier across ALL its members (or none — purely cosmetic group).
  # Mixing — including any member without a modifier when others have one —
  # is a compile error. group_first_owner records the first-seen member so
  # the error can name both endpoints of the inconsistency.
  # group_member_count tallies members per group for the single-member
  # modifier-with-one-flag check.
  declare -A group_modifier
  declare -A group_first_owner
  declare -A group_member_count
  while IFS=$'\t' read -r idx entry_type name short type required has_default default_val aliases_csv \
      group has_exclusive exclusive has_requires requires \
      has_choices choices_csv has_pattern pattern; do
    [[ -z "$idx" ]] && continue
    # Strip sentinel prefix from each field
    idx="${idx#x}"
    entry_type="${entry_type#x}"
    name="${name#x}"
    short="${short#x}"
    type="${type#x}"
    required="${required#x}"
    has_default="${has_default#x}"
    default_val="${default_val#x}"
    aliases_csv="${aliases_csv#x}"
    group="${group#x}"
    has_exclusive="${has_exclusive#x}"
    exclusive="${exclusive#x}"
    has_requires="${has_requires#x}"
    requires="${requires#x}"
    has_choices="${has_choices#x}"
    choices_csv="${choices_csv#x}"
    has_pattern="${has_pattern#x}"
    pattern="${pattern#x}"

    # Non-array choices get a sentinel from the jq emitter; surface a clean
    # error instead of passing the sentinel to value-validation.
    if [[ "$has_choices" == "true" && "$choices_csv" == "__CLIFT_NONARRAY__" ]]; then
      echo "error: ${context}[${idx}]: flag '$name' 'choices' must be a non-empty array of strings" >&2
      return 1
    fi

    _validate_entry_fields "${context}[${idx}]" "$entry_type" "$name" "$short" "$type" "$required" "$has_default" "$default_val" \
      "$group" "$has_exclusive" "$exclusive" "$has_requires" "$requires" \
      "$has_choices" "$choices_csv" "$has_pattern" "$pattern" || return 1

    # Cross-member group consistency: every flag sharing a group name must
    # agree on the modifier — either ALL declare the same modifier
    # (exclusive | requires-all) or NONE declare one (purely cosmetic group
    # used only for help partitioning). The first member fixes the group's
    # mode (including "none"); any later member that disagrees is a compile
    # error. This catches the trap where the first-seen member is bare and
    # later members silently turn the group into a no-op constraint.
    if [[ -n "$group" ]]; then
      local this_mod="none"
      if [[ "$exclusive" == "true" ]]; then
        this_mod="exclusive"
      elif [[ "$has_requires" == "true" ]]; then
        this_mod="requires-all"
      fi
      group_member_count["$group"]=$(( ${group_member_count[$group]:-0} + 1 ))
      if [[ -n "${group_modifier[$group]:-}" ]]; then
        if [[ "${group_modifier[$group]}" != "$this_mod" ]]; then
          local _first_owner="${group_first_owner[$group]}"
          local _first_mod="${group_modifier[$group]}"
          local _msg_this _msg_first
          if [[ "$this_mod" == "none" ]]; then
            _msg_this="declares neither 'exclusive' nor 'requires'"
          elif [[ "$this_mod" == "exclusive" ]]; then
            _msg_this="declares 'exclusive: true'"
          else
            _msg_this="declares 'requires: all'"
          fi
          if [[ "$_first_mod" == "none" ]]; then
            _msg_first="declares neither 'exclusive' nor 'requires'"
          elif [[ "$_first_mod" == "exclusive" ]]; then
            _msg_first="declares 'exclusive: true'"
          else
            _msg_first="declares 'requires: all'"
          fi
          echo "error: ${context}: flag '$name' in group '$group' $_msg_this but flag '$_first_owner' in the same group $_msg_first (group modifier must be consistent across all members)" >&2
          return 1
        fi
      else
        group_modifier["$group"]="$this_mod"
        group_first_owner["$group"]="$name"
      fi
    fi

    # Dedup checks only run after entry validation succeeds, so $name is non-empty and sane.
    if [[ -n "$name" ]]; then
      if [[ " $seen_names " == *" $name "* ]]; then
        local _owner="${seen_name_owner[$name]:-}"
        if [[ -n "$_owner" && "$_owner" != "$name" ]]; then
          echo "error: ${context}: alias '$name' conflicts with name/alias of flag '$_owner'" >&2
        else
          echo "error: ${context}: duplicate flag name '$name' within layer" >&2
        fi
        return 1
      fi
      seen_names="$seen_names $name"
      seen_name_owner["$name"]="$name"
    fi

    # Aliases share the same namespace as names. Split the CSV and check each
    # against every previously seen name/alias (including the current flag's
    # own canonical name, so a self-collision is caught too).
    if [[ -n "$aliases_csv" ]]; then
      local _alias _aliases
      IFS=',' read -ra _aliases <<< "$aliases_csv"
      for _alias in "${_aliases[@]}"; do
        [[ -z "$_alias" ]] && continue
        if [[ ! "$_alias" =~ $NAME_RE ]]; then
          echo "error: ${context}: flag '$name' alias '$_alias' must match ${NAME_RE} (no underscores, lowercase)" >&2
          return 1
        fi
        if [[ " $seen_names " == *" $_alias "* ]]; then
          local _owner="${seen_name_owner[$_alias]:-}"
          echo "error: ${context}: alias '$_alias' conflicts with name/alias of flag '$_owner'" >&2
          return 1
        fi
        seen_names="$seen_names $_alias"
        seen_name_owner["$_alias"]="$name"
      done
    fi

    if [[ -n "$short" ]]; then
      if [[ " $seen_shorts " == *" $short "* ]]; then
        echo "error: ${context}: duplicate short alias '$short' within layer" >&2
        return 1
      fi
      seen_shorts="$seen_shorts $short"
    fi

    # Env-var collision check: two different names could transform to the
    # same CLIFT_FLAG_X if they differ only in dash placement. With the
    # no-underscore rule this is extremely unlikely, but spec §4.4 #10
    # requires the check as a safety net.
    if [[ -n "$name" ]]; then
      local env_form="${name^^}"
      env_form="CLIFT_FLAG_${env_form//-/_}"
      if [[ " $seen_envs " == *" $env_form "* ]]; then
        echo "error: ${context}: flag name '$name' transforms to env var '$env_form' which collides with another flag" >&2
        return 1
      fi
      seen_envs="$seen_envs $env_form"
    fi
  done <<< "$tsv"

  # Single-member group with a modifier is silently a no-op at runtime — a
  # lone flag can't violate exclusivity, and a lone requires-all trivially
  # satisfies. Almost always a typo (wrong group name on the would-be
  # second member), so reject at compile time rather than ship a dead rule.
  local _g
  for _g in "${!group_modifier[@]}"; do
    local _mod="${group_modifier[$_g]}"
    [[ "$_mod" == "none" ]] && continue
    local _count="${group_member_count[$_g]:-0}"
    if (( _count < 2 )); then
      echo "error: ${context}: group '$_g' with '$_mod' must have >=2 members (got $_count)" >&2
      return 1
    fi
  done

  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Direct execution mode — validate the given file

  TASKFILE="${1:-}"

  if [[ -z "$TASKFILE" ]] || [[ ! -f "$TASKFILE" ]]; then
    echo "error: validate.sh requires a valid Taskfile path" >&2
    exit 1
  fi

  # Read the entire Taskfile as JSON once. Every further query is a cheap
  # in-memory jq filter over this blob — no more per-task yq forks.
  # I7: a malformed Taskfile causes yq to fail here with its real error message
  # (set -e will propagate it) instead of silently validating as empty.
  TASKFILE_JSON="$(yq -o=json '.' "$TASKFILE")"

  # Validate top-level vars.FLAGS. _validate_layer now takes JSON directly, so
  # the only fork here is the single jq call to extract the layer.
  top_layer_json="$(echo "$TASKFILE_JSON" | jq -c '.vars.FLAGS // null')"
  _validate_layer "$top_layer_json" "${TASKFILE}:vars.FLAGS" || exit 1

  # Validate vars.PERSISTENT_FLAGS (CLI-wide flags declared at the root
  # Taskfile). Same schema as a regular FLAGS layer. Reserved-name check
  # ensures a persistent flag cannot shadow a framework global.
  persistent_layer_json="$(echo "$TASKFILE_JSON" | jq -c '.vars.PERSISTENT_FLAGS // null')"
  _validate_layer "$persistent_layer_json" "${TASKFILE}:vars.PERSISTENT_FLAGS" || exit 1

  # Validate every tasks.*.vars.FLAGS.
  # I7: only iterate if .tasks is actually an object. Missing / non-object is
  # treated as "no tasks" — this preserves "root-only Taskfile with no tasks"
  # as legal.
  tasks_type="$(echo "$TASKFILE_JSON" | jq -r '.tasks | type')"
  if [[ "$tasks_type" == "object" ]]; then
    # Emit NUL-separated (name, flags_json) pairs from a single jq call. Task
    # names round-trip as opaque strings, so colons/dots/spaces are safe
    # (C1 fix: no path parser ever sees the task name).
    while IFS= read -r -d '' task_name && IFS= read -r -d '' task_flags_json; do
      [[ -z "$task_name" ]] && continue
      _validate_layer "$task_flags_json" "${TASKFILE}:tasks.${task_name}.vars.FLAGS" || exit 1
    done < <(echo "$TASKFILE_JSON" | jq -j '
      .tasks | to_entries[] |
      .key + "\u0000" + ((.value.vars.FLAGS // null) | tojson) + "\u0000"
    ')
  fi

  exit 0
fi
