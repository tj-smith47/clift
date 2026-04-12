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

# Reserved flag names (framework globals — cannot be redeclared)
RESERVED_NAMES=(help verbose quiet no-color version)

# Name regex: lowercase, starts with letter, dashes allowed, NO underscores
NAME_RE='^[a-z][a-z0-9-]*$'
SHORT_RE='^[a-zA-Z0-9]$'
VALID_TYPES=(bool string int list)

_validate_entry() {
  local entry_json="$1"
  local context="$2"

  local name
  name="$(echo "$entry_json" | jq -r '.name // empty')"
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

  local type
  type="$(echo "$entry_json" | jq -r '.type // empty')"
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

  local short
  short="$(echo "$entry_json" | jq -r '.short // empty')"
  if [[ -n "$short" ]] && [[ ! "$short" =~ $SHORT_RE ]]; then
    echo "error: ${context}: flag '$name' short '$short' must match ${SHORT_RE}" >&2
    return 1
  fi

  # Rule 5: required: true is mutually exclusive with default
  local required has_default
  required="$(echo "$entry_json" | jq -r '.required // false')"
  has_default="$(echo "$entry_json" | jq -r '.default // "__none__"')"
  if [[ "$required" == "true" ]] && [[ "$has_default" != "__none__" ]]; then
    echo "error: ${context}: flag '$name' cannot be both required and have a default" >&2
    return 1
  fi

  # Rule 6: default must be compatible with the declared type
  if [[ "$has_default" != "__none__" ]]; then
    case "$type" in
      bool)
        echo "error: ${context}: flag '$name' is bool and cannot have a default (presence is the value)" >&2
        return 1
        ;;
      int)
        if [[ ! "$has_default" =~ ^-?[0-9]+$ ]]; then
          echo "error: ${context}: flag '$name' default '${has_default}' is not a valid integer" >&2
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

_validate_layer() {
  local layer_yaml="$1"
  local context="$2"

  # Null/absent layer is fine
  if [[ "$layer_yaml" == "null" ]] || [[ -z "$layer_yaml" ]]; then
    return 0
  fi

  local count
  count="$(echo "$layer_yaml" | yq 'length')"
  if [[ "$count" == "0" ]]; then
    return 0
  fi

  local seen_names="" seen_shorts=""
  for ((i=0; i<count; i++)); do
    local entry
    entry="$(echo "$layer_yaml" | yq -o=json ".[$i]")"
    _validate_entry "$entry" "${context}[$i]" || return 1

    local name short
    name="$(echo "$entry" | jq -r '.name')"
    short="$(echo "$entry" | jq -r '.short // empty')"

    if [[ " $seen_names " == *" $name "* ]]; then
      echo "error: ${context}: duplicate flag name '$name' within layer" >&2
      return 1
    fi
    seen_names="$seen_names $name"

    if [[ -n "$short" ]] && [[ " $seen_shorts " == *" $short "* ]]; then
      echo "error: ${context}: duplicate short alias '$short' within layer" >&2
      return 1
    fi
    [[ -n "$short" ]] && seen_shorts="$seen_shorts $short"
  done

  return 0
}

# Validate top-level vars.FLAGS
top_layer="$(yq '.vars.FLAGS // null' "$TASKFILE")"
_validate_layer "$top_layer" "${TASKFILE}:vars.FLAGS"

# Validate every tasks.*.vars.FLAGS
task_names="$(yq '.tasks | keys | .[]' "$TASKFILE" 2>/dev/null || echo "")"
while IFS= read -r task_name; do
  [[ -z "$task_name" ]] && continue
  task_layer="$(yq ".tasks.${task_name}.vars.FLAGS // null" "$TASKFILE")"
  _validate_layer "$task_layer" "${TASKFILE}:tasks.${task_name}.vars.FLAGS"
done <<< "$task_names"

exit 0
