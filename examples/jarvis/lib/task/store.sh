#!/usr/bin/env bash
# Task record store for jarvis.
# Builds on state/{profile,lock,json}.sh — expects them sourced first.

# shellcheck disable=SC2317
if [[ -n "${_JARVIS_TASK_STORE_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
_JARVIS_TASK_STORE_LOADED=1

task_store_dir() {
  printf '%s/tasks\n' "$(state_profile_dir)"
}

task_store_now_iso() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

task_store_path() {
  printf '%s/%s.json\n' "$(task_store_dir)" "$1"
}

task_store_exists() {
  [[ -f "$(task_store_path "$1")" ]]
}

# Monotonic per-profile sequence. Persisted at tasks/.seq, flock-guarded.
# Initialization is performed inside the lock to avoid a TOCTOU race where
# a late initializer could clobber an already-advanced counter.
task_store_next_seq() {
  local dir seq_file
  dir="$(task_store_dir)"
  mkdir -p "$dir"
  seq_file="$dir/.seq"
  # The leading single-quoted segment ends before $seq_file so the path is
  # embedded as a literal in the eval'd command string; the trailing segment
  # resumes single quoting. SC2016 fires on the literal text in between.
  # shellcheck disable=SC2016
  state_with_lock "$seq_file" '
    sf='"'$seq_file'"'
    [[ -s "$sf" ]] || printf "0\n" > "$sf"
    current=$(< "$sf")
    next=$(( current + 1 ))
    printf "%s\n" "$next" > "$sf"
    printf "%s\n" "$next"
  '
}

# task_store_build <slug> <desc> <priority> <due> <project> <seq> <jira_key>
# Empty due/jira_key → JSON null. Emits one JSON object.
task_store_build() {
  local slug="$1" desc="$2" priority="$3" due="$4" project="$5" seq="$6" jira="$7"
  local now
  now="$(task_store_now_iso)"
  jq -n \
    --arg slug "$slug" \
    --arg desc "$desc" \
    --arg priority "$priority" \
    --arg due "$due" \
    --arg project "$project" \
    --arg now "$now" \
    --argjson seq "$seq" \
    --arg jira "$jira" \
    '{
      slug: $slug,
      desc: $desc,
      status: "open",
      priority: $priority,
      due: (if $due == "" or $due == "null" then null else $due end),
      project: $project,
      created_at: $now,
      updated_at: $now,
      done_at: null,
      seq: $seq,
      jira_key: (if $jira == "" or $jira == "null" then null else $jira end)
    }'
}

task_store_get() {
  state_json_read "$(task_store_path "$1")"
}

task_store_put() {
  local slug="$1" payload="$2"
  state_json_write "$(task_store_path "$slug")" "$payload"
}

task_store_delete() {
  local slug path
  slug="$1"
  path="$(task_store_path "$slug")"
  rm -f "$path" "$path.lock" "$path".tmp.*
}

# task_store_list [status]
# Emits slugs one-per-line in seq order. Filters by status when given.
# Saves/restores nullglob so callers' shell options are untouched.
task_store_list() {
  local status="${1:-}"
  local dir
  dir="$(task_store_dir)"
  [[ -d "$dir" ]] || return 0
  local had_nullglob=0
  shopt -q nullglob && had_nullglob=1
  shopt -s nullglob
  local files=("$dir"/*.json)
  (( had_nullglob )) || shopt -u nullglob
  (( ${#files[@]} )) || return 0
  if [[ -n "$status" ]]; then
    jq -r --arg s "$status" -s 'map(select(.status == $s)) | sort_by(.seq) | .[].slug' "${files[@]}"
  else
    jq -r -s 'sort_by(.seq) | .[].slug' "${files[@]}"
  fi
}

task_store_set_done() {
  local slug="$1"
  local now path payload
  now="$(task_store_now_iso)"
  path="$(task_store_path "$slug")"
  payload="$(state_json_read "$path")" || return $?
  payload="$(jq --arg now "$now" '.status = "done" | .done_at = $now | .updated_at = $now' <<< "$payload")"
  state_json_write "$path" "$payload"
}

# task_store_mutate <slug> <jq-filter>
# Applies filter to existing record, bumps updated_at, rewrites.
task_store_mutate() {
  local slug="$1" filter="$2"
  local now path payload
  now="$(task_store_now_iso)"
  path="$(task_store_path "$slug")"
  payload="$(state_json_read "$path")" || return $?
  payload="$(jq --arg now "$now" "$filter | .updated_at = \$now" <<< "$payload")"
  state_json_write "$path" "$payload"
}
