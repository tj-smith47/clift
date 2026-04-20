#!/usr/bin/env bash
# YAML frontmatter parse/emit/mutate/merge for jarvis notes.
# Reuses dasel (P0 dep) for YAML<->JSON. Body operations stay in pure bash.

# shellcheck disable=SC2317
if [[ -n "${_JARVIS_FRONTMATTER_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
_JARVIS_FRONTMATTER_LOADED=1

# fm_split <file> <body-var> <fm-var>
# Populates body-var and fm-var. fm is empty if no frontmatter present.
fm_split() {
  # Local names are underscore-prefixed to avoid shadowing caller-supplied
  # variable names (e.g. callers typically pass "body" and "fm").
  local _fm_file="$1" _fm_body_var="$2" _fm_fm_var="$3"
  local _fm_content _fm_out_fm="" _fm_out_body=""
  _fm_content="$(<"$_fm_file")"
  if [[ "$_fm_content" == "---"$'\n'* ]]; then
    local _fm_rest="${_fm_content#---$'\n'}"
    if [[ "$_fm_rest" == *$'\n'---$'\n'* ]]; then
      _fm_out_fm="${_fm_rest%%$'\n'---$'\n'*}"
      _fm_out_body="${_fm_rest#*$'\n'---$'\n'}"
    elif [[ "$_fm_rest" == *$'\n'--- ]]; then
      _fm_out_fm="${_fm_rest%$'\n'---}"
      _fm_out_body=""
    else
      _fm_out_fm=""
      _fm_out_body="$_fm_content"
    fi
  else
    _fm_out_body="$_fm_content"
  fi
  printf -v "$_fm_body_var" '%s' "$_fm_out_body"
  printf -v "$_fm_fm_var" '%s' "$_fm_out_fm"
}

fm_parse() {
  local file="$1"
  local body="" fm=""
  fm_split "$file" body fm
  if [[ -z "$fm" ]]; then
    printf '{}\n'
    return 0
  fi
  dasel -i yaml -o json <<< "$fm"
}

fm_body() {
  local file="$1"
  local body="" fm=""
  fm_split "$file" body fm
  printf '%s' "$body"
}

fm_emit() {
  local json="$1"
  local yaml
  yaml="$(dasel -i json -o yaml <<< "$json")"
  printf -- '---\n%s\n---\n' "$yaml"
}

fm_get() {
  local file="$1" key="$2" default="${3:-}"
  local json val
  json="$(fm_parse "$file")"
  val="$(jq -r --arg k "$key" '
    ($k | split(".")) as $p |
    (getpath($p) // empty)
  ' <<< "$json" 2>/dev/null)"
  if [[ -z "$val" || "$val" == "null" ]]; then
    printf '%s\n' "$default"
  else
    printf '%s\n' "$val"
  fi
}

fm_set() {
  local file="$1" key="$2" value="$3"
  local body="" fm="" fm_json="" updated="" yaml="" tmp=""
  fm_split "$file" body fm
  fm_json="$(fm_parse "$file")"
  updated="$(jq --arg k "$key" --arg v "$value" '
    ($k | split(".")) as $p | setpath($p; $v)
  ' <<< "$fm_json")"
  yaml="$(dasel -i json -o yaml <<< "$updated")"
  tmp="${file}.tmp.$$.$BASHPID.$RANDOM"
  {
    printf -- '---\n%s\n---\n' "$yaml"
    printf '%s' "$body"
  } > "$tmp"
  mv -f "$tmp" "$file"
}

# fm_merge <template-json> <overrides-json>
# overrides win on pinned keys; template wins on other declared keys; tags union.
fm_merge() {
  local template="$1" overrides="$2"
  jq -n --argjson t "$template" --argjson o "$overrides" '
    def pinned: ["slug","kind","created_at","updated_at"];
    def uniq_tags($a; $b): (($a // []) + ($b // [])) | unique;
    ($t // {}) as $T |
    ($o // {}) as $O |
    ($T + ($O | with_entries(select(.key as $k | pinned | index($k))))) as $base |
    $base
      | (if ($T.tags or $O.tags) then .tags = uniq_tags($T.tags; $O.tags) else . end)
  '
}
