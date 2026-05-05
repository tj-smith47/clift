#!/usr/bin/env bash
# Tag a new release of the CLI.
# Usage: bump.sh <CLI_DIR> <FRAMEWORK_DIR>
#
# Reads argv from CLIFT_ARG_* (standard mode, set by wrapper.sh) or from "$@"
# beyond positions 1-2 (task mode / direct invocation).
#
# Sequence:
#   1. Resolve current version from .clift.yaml (source of truth).
#   2. Compute next version per [patch|minor|major] level (default: patch).
#   3. Atomically write .clift.yaml + .env (CLI_VERSION=) + module.yaml (synced
#      from .clift.yaml). Roll back any landed writes on failure so a partial
#      bump never persists.
#   4. git add + git commit + git tag (`vX.Y.Z`, or `<cli-name>/vX.Y.Z` when
#      the CLI lives inside a parent cfgd config repo).
#   5. Optional --push.
#
# Failure modes:
#   - Working tree dirty (without --allow-dirty)  → exit 2
#   - Tag already exists                          → exit 2
#   - Detached HEAD                               → exit 2
#   - Partial 3-file write                        → roll back, exit 1

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

# Reconstruct argv: prefer CLIFT_ARG_* (standard mode) over "$@" (task / direct).
args=()
if [[ -n "${CLIFT_ARG_COUNT:-}" ]]; then
  for ((i=1; i<=CLIFT_ARG_COUNT; i++)); do
    var="CLIFT_ARG_$i"
    args+=("${!var}")
  done
elif (( $# > 0 )); then
  args=("$@")
fi

PUSH=0
DRY_RUN=0
ALLOW_DIRTY=0
MESSAGE=""
LEVEL=""

_usage() {
  local cli="${CLI_NAME:-clift}"
  cat <<EOF
Usage: ${cli} version:bump [LEVEL] [flags]

Cut a new release of the CLI: write the next version into .clift.yaml/.env
(and module.yaml when present), commit, and tag.

LEVEL          one of: patch (default), minor, major

Flags:
  --push           push commit + tag to origin (default off)
  --dry-run        print the plan; change nothing
  --message MSG    override commit message (default: "release: <tag>")
  --allow-dirty    allow bump despite uncommitted changes

Examples:
  ${cli} version:bump                # patch bump
  ${cli} version:bump minor --push   # minor bump, then publish
  ${cli} version:bump major --dry-run
EOF
}

while (( ${#args[@]} > 0 )); do
  a="${args[0]}"
  case "$a" in
    --push)         PUSH=1 ;;
    --dry-run)      DRY_RUN=1 ;;
    --allow-dirty)  ALLOW_DIRTY=1 ;;
    --message)
      MESSAGE="${args[1]:-}"
      if [[ -z "$MESSAGE" ]]; then
        log_error "--message requires a value"; exit 2
      fi
      args=("${args[@]:1}")
      ;;
    --message=*)    MESSAGE="${a#--message=}" ;;
    -h|--help)      _usage; exit 0 ;;
    patch|minor|major)
      [[ -n "$LEVEL" ]] && { log_error "level specified twice ('$LEVEL' then '$a')"; exit 2; }
      LEVEL="$a"
      ;;
    *)
      log_error "unexpected argument: $a"
      _usage >&2
      exit 2
      ;;
  esac
  args=("${args[@]:1}")
done

LEVEL="${LEVEL:-patch}"

CLIFT_YAML="${CLI_DIR}/.clift.yaml"
ENV_FILE="${CLI_DIR}/.env"
MODULE_YAML="${CLI_DIR}/module.yaml"

[[ -f "$CLIFT_YAML" ]] || die ".clift.yaml not found at ${CLIFT_YAML}"

current="$(yq '.version' "$CLIFT_YAML" 2>/dev/null || echo '')"
[[ -z "$current" || "$current" == "null" ]] && die "could not read .version from ${CLIFT_YAML}"
current="${current#v}"

if [[ ! "$current" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  die "current version is not semver (got '${current}')"
fi
maj="${BASH_REMATCH[1]}"
min="${BASH_REMATCH[2]}"
pat="${BASH_REMATCH[3]}"

case "$LEVEL" in
  patch) pat=$((pat + 1)) ;;
  minor) min=$((min + 1)); pat=0 ;;
  major) maj=$((maj + 1)); min=0; pat=0 ;;
esac
next="${maj}.${min}.${pat}"

cli_name="$(yq '.name' "$CLIFT_YAML" 2>/dev/null || echo '')"
[[ -z "$cli_name" || "$cli_name" == "null" ]] && die "could not read .name from ${CLIFT_YAML}"

# Nested-module detection: cfgd's tag convention is `<cli-name>/vX.Y.Z` when
# the CLI lives inside a parent cfgd config repo. Walk ancestors looking for
# a cfgd.yaml (the parent-config marker); standalone repos use a bare `vX.Y.Z`.
nested=0
ancestor="$(cd "$CLI_DIR" && pwd)"
while [[ "$ancestor" != "/" ]]; do
  ancestor="$(dirname "$ancestor")"
  if [[ -f "${ancestor}/cfgd.yaml" ]]; then
    nested=1
    break
  fi
done
if (( nested )); then
  next_tag="${cli_name}/v${next}"
else
  next_tag="v${next}"
fi

# --- Pre-flight git checks ---------------------------------------------------

cd "$CLI_DIR"

git rev-parse --git-dir >/dev/null 2>&1 || die "${CLI_DIR} is not a git repository"

if ! branch="$(git symbolic-ref --short HEAD 2>/dev/null)"; then
  log_error "detached HEAD; switch to a branch before bumping"
  exit 2
fi

if git rev-parse "refs/tags/${next_tag}" >/dev/null 2>&1; then
  log_error "tag '${next_tag}' already exists"
  log_suggest "use '${cli_name} version:set ${next}' to pin to it"
  exit 2
fi

if (( ! ALLOW_DIRTY )); then
  if [[ -n "$(git status --porcelain)" ]]; then
    log_error "working tree dirty:"
    git status --porcelain >&2
    log_suggest "commit changes first or pass --allow-dirty"
    exit 2
  fi
fi

COMMIT_MSG="${MESSAGE:-release: ${next_tag}}"

if (( DRY_RUN )); then
  log_info "(dry-run) bump ${cli_name}: ${current} → ${next}"
  log_info "(dry-run) update: .clift.yaml, .env$( [[ -f "$MODULE_YAML" ]] && printf ', module.yaml' )"
  log_info "(dry-run) commit on '${branch}': \"${COMMIT_MSG}\""
  log_info "(dry-run) tag: ${next_tag}"
  (( PUSH )) && log_info "(dry-run) push commit + tag"
  exit 0
fi

# --- Atomic 3-file write with rollback --------------------------------------
#
# Stage each new content into a tmp file, snapshot originals into .bak files,
# then move tmps into place. On any failure between the first move and the
# git commit, restore from .bak so the working tree is exactly as we found it.

_tmp_clift="$(mktemp)"
_tmp_env=""
_tmp_module=""
_bak_clift=""
_bak_env=""
_bak_module=""
_landed_clift=0
_landed_env=0
_landed_module=0

cleanup() {
  rc=$?
  trap '' EXIT
  # Always remove tmps.
  rm -f "$_tmp_clift" "$_tmp_env" "$_tmp_module"
  if (( rc != 0 )); then
    # Roll back any landed writes from their backups.
    (( _landed_clift )) && [[ -f "$_bak_clift" ]] && mv -f "$_bak_clift" "$CLIFT_YAML"
    (( _landed_env ))   && [[ -f "$_bak_env"   ]] && mv -f "$_bak_env"   "$ENV_FILE"
    (( _landed_module )) && [[ -f "$_bak_module" ]] && mv -f "$_bak_module" "$MODULE_YAML"
  fi
  rm -f "$_bak_clift" "$_bak_env" "$_bak_module"
  exit "$rc"
}
trap cleanup EXIT

# Stage new .clift.yaml
yq ".version = \"${next}\"" "$CLIFT_YAML" > "$_tmp_clift"

# Stage new .env (only if it exists — frameworks-with-no-.env are valid).
if [[ -f "$ENV_FILE" ]]; then
  _tmp_env="$(mktemp)"
  awk -v ver="$next" '
    BEGIN { found = 0 }
    /^CLI_VERSION=/ { print "CLI_VERSION=" ver; found = 1; next }
    { print }
    END { if (!found) print "CLI_VERSION=" ver }
  ' "$ENV_FILE" > "$_tmp_env"
fi

# Stage new module.yaml — keep metadata.name + metadata.description in sync
# with .clift.yaml. cfgd uses git tags for versions, so module.yaml has no
# version field of its own; this is an idempotent metadata refresh.
if [[ -f "$MODULE_YAML" ]]; then
  _tmp_module="$(mktemp)"
  desc="$(yq '.description' "$CLIFT_YAML" 2>/dev/null || echo '')"
  if [[ -z "$desc" || "$desc" == "null" ]]; then
    desc="${cli_name} CLI"
  fi
  _YQ_NAME="$cli_name" _YQ_DESC="$desc" \
    yq '.metadata.name = strenv(_YQ_NAME) | .metadata.description = strenv(_YQ_DESC)' \
    "$MODULE_YAML" > "$_tmp_module"
fi

# Snapshot originals to .bak.
_bak_clift="$(mktemp)"; cp "$CLIFT_YAML" "$_bak_clift"
if [[ -n "$_tmp_env" ]]; then
  _bak_env="$(mktemp)"; cp "$ENV_FILE" "$_bak_env"
fi
if [[ -n "$_tmp_module" ]]; then
  _bak_module="$(mktemp)"; cp "$MODULE_YAML" "$_bak_module"
fi

# Land tmps. Each successful mv flips the _landed_* flag so cleanup knows
# which originals to restore on later failure.
mv "$_tmp_clift" "$CLIFT_YAML"; _landed_clift=1
if [[ -n "$_tmp_env" ]]; then
  mv "$_tmp_env" "$ENV_FILE"; _landed_env=1
fi
if [[ -n "$_tmp_module" ]]; then
  mv "$_tmp_module" "$MODULE_YAML"; _landed_module=1
fi

# --- Git commit + tag --------------------------------------------------------

git add -- "$CLIFT_YAML"
[[ -f "$ENV_FILE"     ]] && git add -- "$ENV_FILE"
[[ -f "$MODULE_YAML"  ]] && git add -- "$MODULE_YAML"

git commit -m "$COMMIT_MSG" >/dev/null
git tag "$next_tag"

log_success "bumped ${cli_name}: ${current} → ${next}"
log_info "tag: ${next_tag}"

if (( PUSH )); then
  log_info "pushing commit + tag…"
  git push
  git push --tags
  log_success "pushed"
else
  log_suggest "publish with: git push && git push --tags  (or re-run with --push)"
fi

# Success — disable rollback before EXIT trap fires.
trap '' EXIT
rm -f "$_bak_clift" "$_bak_env" "$_bak_module"
