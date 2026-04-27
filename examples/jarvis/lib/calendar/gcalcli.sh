#!/usr/bin/env bash
# gcalcli calendar provider. Shells to `gcalcli agenda --tsv` and maps the
# tab-separated agenda rows to our NDJSON event shape: {start,end,title,url}.
#
# TSV columns (gcalcli >=4.x):
#   start_date \t start_time \t end_date \t end_time \t link \t title
#
# Failure modes:
#   - gcalcli not on PATH      -> exit 1, no stderr (silent: covered by doctor)
#   - gcalcli nonzero exit     -> exit 1, single-line stderr ("gcalcli: agenda call failed")
#   - empty agenda             -> exit 0, no output

# shellcheck disable=SC2317
if [[ -n "${_JARVIS_CALENDAR_GCALCLI_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
_JARVIS_CALENDAR_GCALCLI_LOADED=1

calendar_gcalcli_events() {
  local since="$1" until="$2"
  if ! command -v gcalcli >/dev/null 2>&1; then
    return 1
  fi
  local tsv
  if ! tsv="$(gcalcli agenda --tsv "$since" "$until" 2>/dev/null)"; then
    printf 'gcalcli: agenda call failed\n' >&2
    return 1
  fi
  [[ -z "$tsv" ]] && return 0
  # Columns: start_date \t start_time \t end_date \t end_time \t link \t title
  printf '%s\n' "$tsv" \
    | awk -F'\t' 'NF >= 6 {
        printf "{\"start\":\"%sT%s:00\",\"end\":\"%sT%s:00\",\"title\":\"%s\",\"url\":\"%s\"}\n", \
               $1, $2, $3, $4, $6, $5
      }'
}

calendar_register gcalcli calendar_gcalcli_events
