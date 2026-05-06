#!/usr/bin/env bash
# Dynamic completers for bm.
#
# Naming contract (lib/wrapper/wrapper.sh.tmpl + docs/cli/completion.md):
#   clift_complete_<task-colons→underscores>_<flag-dashes→underscores>
# Positional slots use the synthetic flag name "pos<N>".
#
# Sourced standalone by the hidden `_complete` subcommand; we must not
# rely on bm libs already being loaded — the store path is computed
# inline using lib/store.sh's defaults.

_bm_completion_store_path() {
  local home="${BM_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/bm}"
  local profile="${BM_PROFILE:-default}"
  printf '%s/%s/store\n' "$home" "$profile"
}

_bm_completion_names() {
  local prefix="${1:-}" f
  f="$(_bm_completion_store_path)"
  [[ -f "$f" ]] || return 0
  jq -r --arg p "$prefix" 'select(.name | startswith($p)) | .name' "$f" 2>/dev/null
}

_bm_completion_tags() {
  local prefix="${1:-}" f
  f="$(_bm_completion_store_path)"
  [[ -f "$f" ]] || return 0
  jq -r --arg p "$prefix" '.tags[] | select(startswith($p))' "$f" 2>/dev/null \
    | sort -u
}

# Positional name completers — `open <TAB>`, `rm <TAB>`, `tag <TAB>`.
clift_complete_open_pos1() { _bm_completion_names "${1:-}"; }
clift_complete_rm_pos1()   { _bm_completion_names "${1:-}"; }
clift_complete_tag_pos1()  { _bm_completion_names "${1:-}"; }

# Tag-value completers — `add --tag <TAB>`, `list --tag <TAB>`, etc.
clift_complete_add_tag()    { _bm_completion_tags "${1:-}"; }
clift_complete_list_tag()   { _bm_completion_tags "${1:-}"; }
clift_complete_tag_add()    { _bm_completion_tags "${1:-}"; }
clift_complete_tag_remove() { _bm_completion_tags "${1:-}"; }
