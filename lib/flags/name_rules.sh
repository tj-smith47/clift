#!/usr/bin/env bash
# clift name-rule constants. Single source of truth for the regexes that
# validate user-supplied command names and flag names across the framework.
#
# Sourced by scaffold.sh, import.sh (via CLIFT_CMD_NAME_RE), and exposed for
# any other module that needs to validate user-facing identifiers. Flag-name
# validation at `lib/flags/validate.sh` keeps its own local `NAME_RE` so this
# module has no runtime dependency on validate.sh; both constants are kept
# in sync by convention (comments below).
#
# Command names: lowercase alphanumeric + colons (for subcommand namespacing).
# No dashes (colons-only avoids the dash-vs-colon ambiguity of `mycli
# deploy-prod` vs `mycli deploy prod`).
#
# Flag names: lowercase alphanumeric + dashes (Cobra-style). No colons — the
# parser would have to split the token to find the value.

# shellcheck disable=SC2317  # `exit 0` fallback fires only if file is run directly
if [[ -n "${_CLIFT_NAME_RULES_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
_CLIFT_NAME_RULES_LOADED=1

# Matches: greet, greet:loud, deploy:prod:eu. Rejects: Greet, deploy-prod,
# deploy:, :prod, deploy::prod.
# shellcheck disable=SC2034  # read by scaffold.sh and import.sh after sourcing this file
CLIFT_CMD_NAME_RE='^[a-z][a-z0-9]*(:[a-z][a-z0-9]*)*$'

# Matches: help, dry-run, my-flag. Rejects: Help, dry_run, a:b, 1st.
# validate.sh keeps its own local copy (same regex) to avoid sourcing this
# file on the parser hot path; the two MUST stay identical.
# shellcheck disable=SC2034  # mirror of validate.sh's local CLIFT_FLAG_NAME_RE for external consumers
CLIFT_FLAG_NAME_RE='^[a-z][a-z0-9-]*$'
