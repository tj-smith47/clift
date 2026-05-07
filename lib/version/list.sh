#!/usr/bin/env bash
# List available versions of this CLI.
# Usage: list.sh <CLI_DIR> <FRAMEWORK_DIR>
#
# Two source modes, auto-detected (mirrors check.sh):
#   - cfgd-managed: a `.cfgd-managed` marker exists. Reads versions from
#     `cfgd module list --json` for this CLI when the JSON shape provides
#     them; falls back to git tags otherwise.
#   - Standalone:   `git fetch --tags`, then walk local tags matching either
#     `vX.Y.Z` or `<cli-name>/vX.Y.Z`.
#
# Output (default — table):
#     CURRENT  VERSION  TAG          DATE        COMMIT
#     *        1.2.0    bm/v1.2.0    2026-05-06  9621f7a
#              1.1.0    bm/v1.1.0    2026-04-12  e34abc1
#
# Flags:
#   --json          machine output (one object per row)
#   --limit N       cap rows; default 10, 0 = no cap
#   --since vX.Y.Z  only include versions >= floor (semver)
#   -q | --quiet    drop header + asterisk; one row per line, version-only

set -euo pipefail

CLI_DIR="${1:-}"
FRAMEWORK_DIR="${2:-}"

if [[ -z "$CLI_DIR" || -z "$FRAMEWORK_DIR" ]]; then
  echo "error: CLI_DIR and FRAMEWORK_DIR required" >&2
  exit 1
fi
shift 2 || true

# shellcheck source=../log/log.sh
source "${FRAMEWORK_DIR}/lib/log/log.sh"

# --- arg parsing -------------------------------------------------------------

args=()
if [[ -n "${CLIFT_ARG_COUNT:-}" ]]; then
  for ((i=1; i<=CLIFT_ARG_COUNT; i++)); do
    var="CLIFT_ARG_$i"
    args+=("${!var}")
  done
elif (( $# > 0 )); then
  args=("$@")
fi

JSON=0
QUIET=0
LIMIT=10
SINCE=""

i=0
while (( i < ${#args[@]} )); do
  a="${args[$i]}"
  case "$a" in
    --json) JSON=1 ;;
    -q|--quiet) QUIET=1 ;;
    --limit)
      ((i++)) || true
      LIMIT="${args[$i]:-}"
      [[ -z "$LIMIT" ]] && { log_error "--limit requires a value"; exit 2; }
      [[ "$LIMIT" =~ ^[0-9]+$ ]] || { log_error "--limit must be a non-negative integer"; exit 2; }
      ;;
    --limit=*) LIMIT="${a#--limit=}"
      [[ "$LIMIT" =~ ^[0-9]+$ ]] || { log_error "--limit must be a non-negative integer"; exit 2; }
      ;;
    --since)
      ((i++)) || true
      SINCE="${args[$i]:-}"
      [[ -z "$SINCE" ]] && { log_error "--since requires a value"; exit 2; }
      ;;
    --since=*) SINCE="${a#--since=}" ;;
    -h|--help)
      cat <<EOF
Usage: ${CLI_NAME:-clift} version:list [--json] [-q|--quiet] [--limit N] [--since vX.Y.Z]

List available versions of this CLI. The first row is the latest;
the row marked '*' is the locally installed version.

Sources, auto-detected:
  cfgd-managed (.cfgd-managed present + cfgd on PATH) → 'cfgd module list --json'
                                                        with git-tag fallback.
  standalone                                         → local + remote git tags.
EOF
      exit 0
      ;;
    *)
      log_error "unexpected argument: $a"
      exit 2
      ;;
  esac
  ((i++)) || true
done

# --- semver helpers ----------------------------------------------------------

# stdin: one tag/version per line. stdout: only valid semver triples (no v
# prefix, no <name>/ prefix), sorted descending.
_semver_sort_desc() {
  awk -F'.' '
    {
      v = $0
      sub(/^.*\//, "", v)   # strip "<name>/" prefix
      sub(/^v/, "", v)
      if (v !~ /^[0-9]+\.[0-9]+\.[0-9]+$/) next
      print v
    }
  ' | awk -F'.' '{ printf "%010d.%010d.%010d %s\n", $1, $2, $3, $0 }' \
    | sort -r | awk '{ print $2 }'
}

# Compare two semvers. Echoes -1 if a<b, 0 if equal, 1 if a>b.
_semver_cmp() {
  local a="$1" b="$2"
  awk -v a="$a" -v b="$b" -F'.' 'BEGIN {
    na = split(a, ap, ".")
    nb = split(b, bp, ".")
    for (i = 1; i <= 3; i++) {
      ax = (ap[i]+0); bx = (bp[i]+0)
      if (ax < bx) { print -1; exit }
      if (ax > bx) { print  1; exit }
    }
    print 0
  }'
}

# --- read .clift.yaml --------------------------------------------------------

CLIFT_YAML="${CLI_DIR}/.clift.yaml"
[[ -f "$CLIFT_YAML" ]] || die ".clift.yaml not found at ${CLIFT_YAML}"

cli_name="$(yq '.name' "$CLIFT_YAML" 2>/dev/null || echo '')"
[[ -z "$cli_name" || "$cli_name" == "null" ]] && die "could not read .name from ${CLIFT_YAML}"

local_version="$(yq '.version' "$CLIFT_YAML" 2>/dev/null || echo '')"
[[ -z "$local_version" || "$local_version" == "null" ]] && die "could not read .version from ${CLIFT_YAML}"
local_version="${local_version#v}"

# --- collect candidate versions ---------------------------------------------

mode="standalone"
declare -a versions=()
declare -A tag_for=() commit_for=() date_for=()

# Try cfgd first when applicable.
if [[ -f "${CLI_DIR}/.cfgd-managed" ]] && command -v cfgd >/dev/null 2>&1; then
  mode="cfgd"
  if json="$(cfgd module list --json 2>/dev/null)"; then
    # cfgd's JSON surface has shifted; collect everything that looks like a
    # version list under this module.
    while IFS= read -r v; do
      [[ -z "$v" ]] && continue
      versions+=("$v")
    done < <(printf '%s' "$json" | jq -r --arg n "$cli_name" '
      .. | objects | select(.name? == $n)
        | (.versions // .available_versions // .tags // empty)
        | if type == "array" then .[] else . end
    ' 2>/dev/null | sed 's|^.*/||; s|^v||' | _semver_sort_desc)
  fi
fi

# Fall back / supplement with git tags. Always run when cfgd produced nothing.
if (( ${#versions[@]} == 0 )); then
  cd "$CLI_DIR"
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    die "${CLI_DIR} is not a git repository (and not cfgd-managed)"
  fi
  git fetch --tags --quiet 2>/dev/null || true
  while IFS=$'\t' read -r tag sha date; do
    [[ -z "$tag" ]] && continue
    v="$tag"
    v="${v##*/}"
    v="${v#v}"
    [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
    # First sighting wins for tag/commit/date; namespaced refs sort first via
    # the refspec order ("refs/tags/v*" then "refs/tags/<name>/v*") — but we
    # prefer the namespaced form when both exist, so let it overwrite the
    # bare form's metadata only when it carries the cli prefix.
    if [[ -z "${tag_for[$v]:-}" ]]; then
      versions+=("$v")
      tag_for[$v]="$tag"
      commit_for[$v]="${sha:0:7}"
      date_for[$v]="$date"
    elif [[ "$tag" == "${cli_name}/"* ]]; then
      tag_for[$v]="$tag"
      commit_for[$v]="${sha:0:7}"
      date_for[$v]="$date"
    fi
  done < <(
    git for-each-ref --sort='-creatordate' \
      --format='%(refname:short)%09%(objectname)%09%(creatordate:short)' \
      "refs/tags/v*" "refs/tags/${cli_name}/v*" 2>/dev/null
  )
  # sort versions desc by semver
  if (( ${#versions[@]} > 0 )); then
    mapfile -t versions < <(printf '%s\n' "${versions[@]}" | _semver_sort_desc)
  fi
fi

# Backfill tag/commit/date for any version we got from cfgd-only.
if [[ -d "${CLI_DIR}/.git" ]] || git -C "$CLI_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  for v in "${versions[@]}"; do
    [[ -n "${tag_for[$v]:-}" ]] && continue
    for candidate in "${cli_name}/v${v}" "v${v}"; do
      if sha="$(git -C "$CLI_DIR" rev-list -n1 "$candidate" 2>/dev/null)"; then
        [[ -z "$sha" ]] && continue
        tag_for[$v]="$candidate"
        commit_for[$v]="${sha:0:7}"
        date_for[$v]="$(git -C "$CLI_DIR" log -1 --format=%cs "$sha" 2>/dev/null || echo '')"
        break
      fi
    done
  done
fi

# --- filter --since ---------------------------------------------------------

if [[ -n "$SINCE" ]]; then
  floor="${SINCE#v}"
  [[ "$floor" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "--since must be a vX.Y.Z semver"
  filtered=()
  for v in "${versions[@]}"; do
    cmp="$(_semver_cmp "$v" "$floor")"
    (( cmp >= 0 )) && filtered+=("$v")
  done
  versions=("${filtered[@]}")
fi

# --- apply --limit ----------------------------------------------------------

if (( LIMIT > 0 )) && (( ${#versions[@]} > LIMIT )); then
  versions=("${versions[@]:0:LIMIT}")
fi

# --- output -----------------------------------------------------------------

if (( JSON )); then
  rows=()
  for v in "${versions[@]}"; do
    current=false
    [[ "$v" == "$local_version" ]] && current=true
    rows+=("$(jq -nc \
      --arg version "$v" \
      --arg tag "${tag_for[$v]:-}" \
      --arg commit "${commit_for[$v]:-}" \
      --arg date "${date_for[$v]:-}" \
      --argjson current "$current" \
      '{version: $version, tag: $tag, commit: $commit, date: $date, current: $current}')")
  done
  printf '%s\n' "${rows[@]+"${rows[@]}"}" | jq -s --arg name "$cli_name" --arg mode "$mode" '
    {name: $name, mode: $mode, versions: .}'
  exit 0
fi

if (( ${#versions[@]} == 0 )); then
  (( QUIET )) || log_info "No versions published yet."
  exit 0
fi

if (( QUIET )); then
  for v in "${versions[@]}"; do
    printf '%s\n' "$v"
  done
  exit 0
fi

# Pretty table
printf 'CURRENT  VERSION  TAG%-20s  DATE        COMMIT\n' ""
for v in "${versions[@]}"; do
  marker=' '
  [[ "$v" == "$local_version" ]] && marker='*'
  tag="${tag_for[$v]:-}"
  date="${date_for[$v]:-}"
  commit="${commit_for[$v]:-}"
  printf '   %s     %-7s  %-22s  %-10s  %s\n' "$marker" "$v" "$tag" "$date" "$commit"
done
