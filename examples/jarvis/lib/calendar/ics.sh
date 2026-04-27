#!/usr/bin/env bash
# ICS calendar provider. Reads [calendar.ics] source (URL or path), parses
# VEVENT blocks, emits NDJSON {start,end,title,url} filtered to [since,until).
#
# Failure modes:
#   - missing [calendar.ics] source        -> exit 1
#   - URL fetch failure (curl error)       -> exit 1
#   - file path that doesn't exist         -> exit 1
#
# Limitations:
#   - Folded ICS lines (CRLF + space continuation) NOT unfolded — assumes flat.
#   - Only the explicit `URL:` field is consulted; meeting URL extraction
#     from titles/locations is T5's job (lib/calendar/meeting_url.sh).

# shellcheck disable=SC2317
if [[ -n "${_JARVIS_CALENDAR_ICS_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
_JARVIS_CALENDAR_ICS_LOADED=1

calendar_ics_events() {
  local since="$1" until="$2" profile="${3:-${JARVIS_PROFILE:-default}}"
  local source
  source="$(config_get calendar.ics.source "" "$profile")"
  [[ -z "$source" ]] && return 1

  local body
  if [[ "$source" =~ ^https?:// ]]; then
    command -v curl >/dev/null 2>&1 || return 1
    if ! body="$(curl -fsSL "$source" 2>/dev/null)"; then
      return 1
    fi
  else
    [[ -f "$source" ]] || return 1
    body="$(<"$source")"
  fi

  # AWK VEVENT parser. JSON-escapes title and url (\ first, then ").
  printf '%s\n' "$body" | awk -v since="$since" -v until="$until" '
    BEGIN { in_event = 0 }
    /^BEGIN:VEVENT/  { in_event = 1; dt=""; et=""; title=""; url=""; next }
    /^END:VEVENT/    {
      if (in_event && dt != "") {
        dt_iso = substr(dt,1,4)"-"substr(dt,5,2)"-"substr(dt,7,2)"T"substr(dt,10,2)":"substr(dt,12,2)":"substr(dt,14,2)"Z"
        et_iso = (et=="") ? dt_iso : substr(et,1,4)"-"substr(et,5,2)"-"substr(et,7,2)"T"substr(et,10,2)":"substr(et,12,2)":"substr(et,14,2)"Z"
        if (dt_iso >= since && dt_iso < until) {
          gsub(/\\/, "\\\\", title); gsub(/"/, "\\\"", title)
          gsub(/\\/, "\\\\", url);   gsub(/"/, "\\\"", url)
          printf "{\"start\":\"%s\",\"end\":\"%s\",\"title\":\"%s\",\"url\":\"%s\"}\n",
                 dt_iso, et_iso, title, url
        }
      }
      in_event = 0; next
    }
    in_event && /^DTSTART/ { sub(/^DTSTART[^:]*:/, ""); dt = $0; next }
    in_event && /^DTEND/   { sub(/^DTEND[^:]*:/, "");   et = $0; next }
    in_event && /^SUMMARY/ { sub(/^SUMMARY:/, "");      title = $0; next }
    in_event && /^URL/     { sub(/^URL:/, "");          url = $0; next }
  '
}

calendar_register ics calendar_ics_events
calendar_register outlook-ics calendar_ics_events
