#!/usr/bin/env bash
# clift shared alias-filter jq fragment.
#
# Two consumers render or validate the user-facing form of task aliases:
#
#   1. lib/flags/compile.sh — builds `user_aliases` for index.json and runs
#      the duplicate-alias clash check; strips the canonical namespace off
#      each raw alias and drops aliases that would not surface as a valid
#      top-level user shortcut.
#
#   2. lib/help/detail.sh — renders the `Aliases:` line under a command's
#      detail page; uses index.json when available, falls back to
#      tasks.json (applying the same filter inline) for framework-lib
#      commands whose aliases never reach index.json.
#
# The namespace-strip transform and the three-filter "user-surfaceable"
# predicate are identical across both callers. Previously each one
# inlined its own copy of the logic (three copies total — two in
# compile.sh, one in detail.sh), meaning a future filter rule change had
# to be applied in three places. This module is the single source of
# truth, spliced into each jq program as a prelude.
#
# Extra filters that only one caller applies (e.g. compile.sh's
# user_aliases also drops aliases that would be shadowed by an existing
# top-level command segment) live at that call site, composed AFTER the
# shared predicate. The shared definitions are deliberately small so
# they compose cleanly.

# shellcheck disable=SC2317  # `exit 0` fallback fires only if file is run directly
if [[ -n "${_CLIFT_ALIAS_FILTER_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
_CLIFT_ALIAS_FILTER_LOADED=1

# Splice this fragment into any jq program that needs the shared alias
# primitives. Both definitions live at the jq-program top level; callers
# invoke them like any jq function.
#
#   strip_ns($ns; $a)
#     If $ns is non-empty AND $a starts with "$ns:", returns $a with
#     "$ns:" stripped. Otherwise returns $a unchanged. Used to convert a
#     raw alias (as declared in the Taskfile) into its bare top-level
#     form — e.g. the alias `config:s` on task `config:show` strips to
#     `s`, matching what the wrapper binds as `mycli s`.
#
#   is_user_surfaceable_alias($a; $canonical)
#     Predicate. Returns true when $a (already ns-stripped) would render
#     as a usable bare user alias:
#       - non-empty after stripping;
#       - does not itself still contain ":" (would not be a valid
#         single-token shortcut);
#       - is not equal to the canonical task's display name (a
#         self-referential alias like `config:show` → `show` under
#         namespace `config` adds no new surface).
#
# Callers that need additional filters (e.g. shadow-by-top-level-command)
# compose them in the surrounding `select(...)` alongside this predicate.
# shellcheck disable=SC2034  # spliced into jq programs in compile.sh / detail.sh
# shellcheck disable=SC2016  # $ns, $a, $canonical are jq vars, not shell; single-quote is required
readonly CLIFT_ALIAS_FILTER_JQ_DEFS='
def strip_ns($ns; $a):
  if $ns != "" and ($a | startswith($ns + ":"))
  then ($a | ltrimstr($ns + ":"))
  else $a
  end;

def is_user_surfaceable_alias($a; $canonical):
  $a != ""
  and ($a | contains(":") | not)
  and $a != $canonical;
'
