#!/usr/bin/env bash
set -euo pipefail

# Resolve framework/CLI dirs with fallback so this script runs standalone in tests.
: "${FRAMEWORK_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)}"
: "${CLI_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# shellcheck source=/dev/null
source "${FRAMEWORK_DIR}/lib/log/log.sh"
# shellcheck source=/dev/null
source "${CLI_DIR}/lib/state/profile.sh"
# shellcheck source=/dev/null
source "${CLI_DIR}/lib/state/lock.sh"
# shellcheck source=/dev/null
source "${CLI_DIR}/lib/state/json.sh"
# shellcheck source=/dev/null
source "${CLI_DIR}/lib/slug.sh"
# shellcheck source=/dev/null
source "${CLI_DIR}/lib/frontmatter.sh"
# shellcheck source=/dev/null
source "${CLI_DIR}/lib/note/resolve.sh"
# shellcheck source=/dev/null
source "${CLI_DIR}/lib/note/index.sh"
# shellcheck source=/dev/null
source "${CLI_DIR}/lib/note/store.sh"
# shellcheck source=/dev/null
source "${CLI_DIR}/lib/note/current.sh"

# CLIFT_FLAGS may not be declared when invoked standalone (tests, direct calls).
# In that case, parse argv ourselves for the flags the router would normally
# have exported. The router path leaves $@ empty and sets CLIFT_FLAGS +
# CLIFT_FLAG_TAG_*; the standalone path reads remaining argv.
if ! declare -p CLIFT_FLAGS >/dev/null 2>&1; then
  declare -A CLIFT_FLAGS=()
  _tag_idx=0
  while (( $# > 0 )); do
    case "$1" in
      --tag)
        _tag_idx=$((_tag_idx + 1))
        printf -v "CLIFT_FLAG_TAG_${_tag_idx}" '%s' "$2"
        export "CLIFT_FLAG_TAG_${_tag_idx}"
        shift 2
        ;;
      --tag=*)
        _tag_idx=$((_tag_idx + 1))
        printf -v "CLIFT_FLAG_TAG_${_tag_idx}" '%s' "${1#--tag=}"
        export "CLIFT_FLAG_TAG_${_tag_idx}"
        shift
        ;;
      --on)         CLIFT_FLAGS[on]="$2"; shift 2 ;;
      --on=*)       CLIFT_FLAGS[on]="${1#--on=}"; shift ;;
      --no-timestamp) CLIFT_FLAGS[no-timestamp]="true"; shift ;;
      --format)     CLIFT_FLAGS[format]="$2"; shift 2 ;;
      --format=*)   CLIFT_FLAGS[format]="${1#--format=}"; shift ;;
      *)
        clift_exit 2 "unknown argument: $1"
        ;;
    esac
  done
  if (( _tag_idx > 0 )); then
    export CLIFT_FLAG_TAG_COUNT="$_tag_idx"
  fi
fi

body="${CLIFT_POS_1:-}"
on="${CLIFT_FLAGS[on]:-}"
no_ts="${CLIFT_FLAGS[no-timestamp]:-}"
fmt="${CLIFT_FLAGS[format]:-}"

if [[ -z "$body" ]]; then
  clift_exit 2 "usage: jarvis note <body> [--tag NAME]... [--on TARGET] [--no-timestamp] [--format STRFTIME]"
fi

state_ensure_tree

# Collect tags (list flag) into a JSON array.
tag_count="${CLIFT_FLAG_TAG_COUNT:-0}"
tags_json="[]"
if (( tag_count > 0 )); then
  tag_args=()
  for (( i=1; i<=tag_count; i++ )); do
    var="CLIFT_FLAG_TAG_${i}"
    tag_args+=("${!var}")
  done
  tags_json="$(printf '%s\n' "${tag_args[@]}" | jq -R . | jq -sc .)"
fi

# Build append-flag array with safe expansion under `set -u`.
append_flags=()
if [[ "$no_ts" == "true" || "$no_ts" == "1" ]]; then
  append_flags+=(--no-timestamp)
fi
if [[ -n "$fmt" ]]; then
  append_flags+=(--format "$fmt")
fi

# _create_in_inbox <title> — mint a new inbox/<slug> note from a title string.
# Uses slug_from_desc + slug_resolve_collision against the notes root.
_create_in_inbox() {
  local title="$1"
  local base slug file
  base="$(slug_from_desc "$title")" || clift_exit 2 "title is empty after slug normalization"
  # Resolve slug collisions against any existing .md in the inbox/ subtree.
  local inbox_dir
  inbox_dir="$(note_root)/inbox"
  mkdir -p "$inbox_dir"
  local candidate="$base" n=2
  while [[ -e "$inbox_dir/$candidate.md" ]]; do
    candidate="${base}-${n}"
    n=$((n + 1))
  done
  slug="$candidate"
  note_store_new inbox "$slug" "$title" --tags "$tags_json" >/dev/null
  file="$(note_path "inbox/$slug")"
  printf '%s\n' "inbox/$slug"
  _last_created_file="$file"
}

# _ensure_daily <yyyy-mm-dd> — create daily/<date> from the daily template if
# absent; no-op if it already exists. Echoes the key.
_ensure_daily() {
  local date="$1"
  local key="daily/$date"
  local file
  file="$(note_path "$key")"
  if [[ ! -f "$file" ]]; then
    note_store_new daily "$date" "$date" \
      --template "$CLI_DIR/templates/daily.md" \
      --tags "$tags_json" >/dev/null
  fi
  printf '%s\n' "$key"
}

target=""
if [[ -n "$on" ]]; then
  # --on TARGET: resolve an existing note, or create inbox/<slug-of-title>.
  if resolved="$(note_resolve "$on" 2>/dev/null)"; then
    target="$resolved"
  else
    target="$(_create_in_inbox "$on")"
  fi
elif current_line="$(note_current_read)" && [[ -n "$current_line" ]]; then
  # current-note routing.
  case "$current_line" in
    kind=daily)
      today="$(date +%F)"
      target="$(_ensure_daily "$today")"
      ;;
    slug=*)
      key="${current_line#slug=}"
      # Resolve through note_resolve so we pick up retitled/moved notes.
      if resolved="$(note_resolve "$key" 2>/dev/null)"; then
        target="$resolved"
      else
        clift_exit 1 "current note '$key' no longer exists"
      fi
      ;;
    *)
      clift_exit 1 "current note state malformed: $current_line"
      ;;
  esac
else
  # Quick capture: mint inbox/<slug-from-body>.
  target="$(_create_in_inbox "$body")"
  # When --no-timestamp / --format were passed for a create-only path, they
  # do not apply (no append happens). Silently ignored, matching other
  # capture flags.
  log_success "$target"
  exit 0
fi

# Append to the resolved target.
note_store_append "$target" "$body" ${append_flags[@]+"${append_flags[@]}"}
log_success "$target"
