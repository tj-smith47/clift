#!/usr/bin/env bash
# clift Flag Schema Validator
# Usage: validate.sh <taskfile-path>
# Reads vars.FLAGS and tasks.*.vars.FLAGS from the given Taskfile
# and validates each entry against the schema in spec §4.2.
#
# Exits 0 if all entries valid; 1 with error message(s) if any invalid.

set -euo pipefail

TASKFILE="${1:-}"

if [[ -z "$TASKFILE" ]] || [[ ! -f "$TASKFILE" ]]; then
  echo "error: validate.sh requires a valid Taskfile path" >&2
  exit 1
fi

# Reserved flag names — derived from the canonical globals.json
_GLOBALS_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/globals.json"
mapfile -t RESERVED_NAMES < <(jq -r '.[].name' "$_GLOBALS_FILE")

# Name regex: lowercase, starts with letter, dashes allowed, NO underscores
NAME_RE='^[a-z][a-z0-9-]*$'
SHORT_RE='^[a-zA-Z0-9]$'
VALID_TYPES=(bool string int list)

# Validate a single flag entry using pre-extracted fields (no jq calls).
# Args: context entry_type name short type required has_default default_val
_validate_entry_fields() {
  local context="$1"
  local entry_type="$2"
  local name="$3"
  local short="$4"
  local type="$5"
  local required="$6"
  local has_default="$7"
  local default_val="$8"

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
  # required, has_default_key, default_value. has_default_key distinguishes
  # "no default" from "default: null", which matters for the required-vs-default
  # mutual-exclusion rule. Bare-string (non-map) entries get entry_type=string
  # and empty fields — _validate_entry_fields rejects them with a clean message.
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
      "x" + (if (.value|type) == "object" then (.value.default // "" | tostring) else "" end)
    ] | @tsv
  ')"

  local seen_names="" seen_shorts="" seen_envs=""
  while IFS=$'\t' read -r idx entry_type name short type required has_default default_val; do
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
    _validate_entry_fields "${context}[${idx}]" "$entry_type" "$name" "$short" "$type" "$required" "$has_default" "$default_val" || return 1

    # Dedup checks only run after entry validation succeeds, so $name is non-empty and sane.
    if [[ -n "$name" ]]; then
      if [[ " $seen_names " == *" $name "* ]]; then
        echo "error: ${context}: duplicate flag name '$name' within layer" >&2
        return 1
      fi
      seen_names="$seen_names $name"
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

  return 0
}

# Read the entire Taskfile as JSON once. Every further query is a cheap
# in-memory jq filter over this blob — no more per-task yq forks.
# I7: a malformed Taskfile causes yq to fail here with its real error message
# (set -e will propagate it) instead of silently validating as empty.
TASKFILE_JSON="$(yq -o=json '.' "$TASKFILE")"

# Validate top-level vars.FLAGS. _validate_layer now takes JSON directly, so
# the only fork here is the single jq call to extract the layer.
top_layer_json="$(echo "$TASKFILE_JSON" | jq -c '.vars.FLAGS // null')"
_validate_layer "$top_layer_json" "${TASKFILE}:vars.FLAGS" || exit 1

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
