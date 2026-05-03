#!/usr/bin/env bash
# clift go-task var inference
#
# Pure functions that turn go-task `vars:` and `requires.vars:` declarations
# into clift FLAG entries during `clift init --from`. The conversion is
# mechanical — go-task already encodes type intent in YAML literal form, so
# we lift that signal into clift's typed flag schema.
#
# Two entry points:
#   infer_flag <varname> <yaml-value>   # vars: {K: V}    → JSON FLAG entry
#   infer_required <varname>            # requires.vars   → JSON FLAG entry
#
# The yaml-value passed to infer_flag is the literal text as it appeared
# in the source Taskfile (or, for nested-JSON, the textual form chosen by
# the source reader): `true`, `"true"`, `3`, `1.5`, `{{.OTHER}}`, etc.
#
# Type inference rules (per design):
#   true / false (unquoted)   → bool   (no default — see "Bool semantics" below)
#   "true" / "false" (quoted) → bool   (no default — see "Bool semantics" below)
#   integer (3, 42)           → int,  default=<int>
#   float   (1.5)             → string (clift has no float), default="1.5"
#   "" (empty quoted)         → string, default=""
#   {{.OTHER}} (template)     → string, default="{{.OTHER}}" (runtime value)
#   anything else             → string, default=<as-is, with quotes stripped>
#
# Bool semantics: clift bool flags carry no `default`. Presence on the
# command line means true; absence means falsy and the framework leaves the
# var unset. The wrapper script (lib/setup/wrapper_writer.sh) emits a
# `KEY=value` assignment to go-task only when CLIFT_FLAG_<KEY> is set —
# absence forwards nothing.
#
# Caveats from go-task semantics:
#
#   * Task-level `vars: {K: V}` defaults are NOT overridable from the
#     command line. go-task treats them as task-scoped constants. The
#     generated wrapper still surfaces `--dry-run` as a clift flag, but
#     when the source Taskfile writes `vars: {DRY_RUN: false}` (a literal
#     scalar), `task ... DRY_RUN=true` has no effect.
#
#     `init_from.sh::_emit_caveats` collects every such flag and prints a
#     consolidated `==> Caveats` block after init so users see one
#     actionable punch list of what is inert and how to fix it (edit the
#     command script to read `$CLIFT_FLAG_<NAME>` directly, or rewrite
#     the source as `{{.X | default "v"}}`).
#     See: https://taskfile.dev/usage/#variables
#
#   * `requires.vars: [X]` IS satisfiable from the command line. The
#     wrapper emits `X=${CLIFT_FLAG_X}` when --x is provided, and the
#     parser's `required: true` check guarantees the env var is set
#     before the wrapper runs. `_emit_caveats` skips these.
#
#   * `vars: {RELEASE: true}` — no `--no-release` flag is generated, so
#     the user cannot toggle this back off from the CLI even when the
#     source is rewritten in the override-friendly form. Hand-edit the
#     generated FLAGS list (or rename the source var to its negative
#     form) if you need a togglable inverse.
#
# Name conversion: uppercase var names → lower-kebab clift flag names
# (DRY_RUN → dry-run). The result is validated against CLIFT_FLAG_NAME_RE
# from lib/flags/name_rules.sh; an invalid result exits nonzero.

set -euo pipefail

# shellcheck disable=SC2317  # `exit 0` fallback fires only if file is run directly
if [[ -n "${_CLIFT_VAR_INFERENCE_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
_CLIFT_VAR_INFERENCE_LOADED=1

# Resolve module siblings. Source name_rules.sh for CLIFT_FLAG_NAME_RE.
_CLIFT_VAR_INFERENCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../flags/name_rules.sh
. "$_CLIFT_VAR_INFERENCE_DIR/../flags/name_rules.sh"

# _vi_to_flag_name <UPPER_SNAKE>
# Converts FOO_BAR_BAZ → foo-bar-baz. Validates the result against the
# strict flag-name regex (CLIFT_FLAG_NAME_RE — unchanged by the relaxed
# command-name rules in tier 1C). Echoes the converted name on success;
# exits nonzero with a clear stderr message on failure.
_vi_to_flag_name() {
  local raw="$1"
  if [[ -z "$raw" ]]; then
    echo "error: var_inference: empty variable name" >&2
    return 1
  fi
  # Lowercase, then map underscores to dashes. ${var,,} requires bash 4.0+
  # (already a framework requirement; see check/deps.sh).
  local lower="${raw,,}"
  local kebab="${lower//_/-}"
  if [[ ! "$kebab" =~ $CLIFT_FLAG_NAME_RE ]]; then
    echo "error: var_inference: variable '$raw' converts to '$kebab' which is not a valid flag name (must match ${CLIFT_FLAG_NAME_RE})" >&2
    return 1
  fi
  printf '%s' "$kebab"
}

# infer_flag <varname> <yaml-value>
# Emits a single-line JSON object on stdout describing a clift FLAG entry.
# The yaml-value is interpreted by literal form, mirroring how a human
# reading the Taskfile would classify it.
infer_flag() {
  if [[ $# -lt 2 ]]; then
    echo "error: var_inference: infer_flag requires <varname> <yaml-value>" >&2
    return 1
  fi
  local varname="$1"
  local raw="$2"

  local flag_name
  flag_name="$(_vi_to_flag_name "$varname")" || return 1

  # Bool literal (unquoted true/false) — must match before generic int/string
  # detection so a quoted "true" still falls into the quoted-bool branch
  # below rather than the generic-string branch. Bool entries omit `default`
  # entirely: validate.sh rule 6 rejects bool flags with `default`, because
  # clift bool semantics are presence-driven (see header comment).
  if [[ "$raw" == "true" || "$raw" == "false" ]]; then
    jq -cn --arg n "$flag_name" '{name:$n, type:"bool"}'
    return 0
  fi

  # Quoted bool — "true" / "false" / 'true' / 'false'. Treated as bool so
  # users who quote everything in their Taskfile (a common YAML hygiene
  # habit) still get parsed flags. Same default-less emission as above.
  if [[ "$raw" == '"true"' || "$raw" == "'true'" \
     || "$raw" == '"false"' || "$raw" == "'false'" ]]; then
    jq -cn --arg n "$flag_name" '{name:$n, type:"bool"}'
    return 0
  fi

  # Integer (signed). Must be wholly numeric — no decimal point.
  if [[ "$raw" =~ ^-?[0-9]+$ ]]; then
    jq -cn --arg n "$flag_name" --argjson d "$raw" '{name:$n, type:"int", default:$d}'
    return 0
  fi

  # Strip surrounding quotes for string defaults so the JSON value carries
  # the user-visible string, not the YAML escaping. Floats keep their
  # textual form (clift has no float type — they downgrade to string).
  local stripped="$raw"
  if [[ ${#raw} -ge 2 && "${raw:0:1}" == '"' && "${raw: -1}" == '"' ]]; then
    stripped="${raw:1:${#raw}-2}"
  elif [[ ${#raw} -ge 2 && "${raw:0:1}" == "'" && "${raw: -1}" == "'" ]]; then
    stripped="${raw:1:${#raw}-2}"
  fi

  # Everything else — floats, bare strings, quoted strings, go-task
  # templates ({{.OTHER}}) — falls through to string. Templates are
  # runtime values; we don't try to resolve them here.
  jq -cn --arg n "$flag_name" --arg d "$stripped" '{name:$n, type:"string", default:$d}'
}

# infer_required <varname>
# Emits a JSON FLAG entry for a required-string flag (no default permitted
# alongside required:true; see validate.sh rule 5).
infer_required() {
  if [[ $# -lt 1 ]]; then
    echo "error: var_inference: infer_required requires <varname>" >&2
    return 1
  fi
  local varname="$1"
  local flag_name
  flag_name="$(_vi_to_flag_name "$varname")" || return 1
  jq -cn --arg n "$flag_name" '{name:$n, type:"string", required:true}'
}
