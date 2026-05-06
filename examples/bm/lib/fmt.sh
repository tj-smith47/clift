#!/usr/bin/env bash
# bm output formatters — table / json / yaml.
#
# Library — does NOT call `set -euo pipefail`. See lib/store.sh for the
# rationale: shell options leak to the caller and conditionals would
# abort the caller on benign no-match cases.
#
# All three formatters consume an NDJSON stream on stdin (one bookmark
# per line) and write to stdout. Empty input → empty output (no header).

# shellcheck disable=SC2317
if [[ -n "${_BM_FMT_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
_BM_FMT_LOADED=1

# bm_fmt_table — pretty 4-column output (name / url / tags / age).
bm_fmt_table() {
  local now_epoch
  now_epoch="$(date -u +%s)"
  jq -r --argjson now "$now_epoch" '
    [.name,
     .url,
     (.tags | join(",")),
     ((.added_at | sub("\\.[0-9]+Z$";"Z") | fromdateiso8601 | ($now - .)) as $d
      | if   $d < 60      then "\($d)s"
        elif $d < 3600    then "\(($d/60   |floor))m"
        elif $d < 86400   then "\(($d/3600 |floor))h"
        else                   "\(($d/86400|floor))d"
        end)
    ] | @tsv
  ' | _bm_fmt_align "NAME" "URL" "TAGS" "AGE"
}

# Internal: render a TSV stream as a 4-col aligned table with a header row.
_bm_fmt_align() {
  local h1="$1" h2="$2" h3="$3" h4="$4"
  awk -F'\t' -v h1="$h1" -v h2="$h2" -v h3="$h3" -v h4="$h4" '
    BEGIN { rows = 0 }
    { c1[rows]=$1; c2[rows]=$2; c3[rows]=$3; c4[rows]=$4; rows++ }
    function maxw(arr, hdr,   m, i) {
      m = length(hdr)
      for (i = 0; i < rows; i++) if (length(arr[i]) > m) m = length(arr[i])
      return m
    }
    END {
      w1 = maxw(c1, h1); w2 = maxw(c2, h2); w3 = maxw(c3, h3); w4 = maxw(c4, h4)
      fmt = "%-" w1 "s  %-" w2 "s  %-" w3 "s  %-" w4 "s\n"
      printf fmt, h1, h2, h3, h4
      for (i = 0; i < rows; i++) printf fmt, c1[i], c2[i], c3[i], c4[i]
    }'
}

# bm_fmt_json — emit a JSON array of all rows.
bm_fmt_json() { jq -s '.'; }

# bm_fmt_yaml — emit YAML (one document per row, in array form). Hand-rolled
# to keep the example dependency-light (no yq at runtime).
bm_fmt_yaml() {
  jq -r '
    "- name: " + (.name|tostring),
    "  url: " + (.url|tostring),
    "  description: " + (.description|tostring),
    "  tags: [" + (.tags | map("\"" + . + "\"") | join(", ")) + "]",
    "  added_at: " + (.added_at|tostring)
  '
}
