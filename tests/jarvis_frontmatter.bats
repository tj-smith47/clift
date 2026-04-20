#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load jarvis_helper

setup() {
  jarvis_common_setup
  source "$CLIFT_JARVIS_DIR/lib/frontmatter.sh"
  NOTE="$TEST_DIR/sample.md"
  cat > "$NOTE" <<'EOF'
---
title: sample
slug: sample
kind: inbox
tags: [a, b]
append:
  timestamp: true
  format: "## %Y-%m-%d %H:%M"
---
body line one

body line two
EOF
}
teardown() { jarvis_common_teardown; }

@test "fm_parse returns JSON with top-level and nested keys" {
  run fm_parse "$NOTE"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.title' <<< "$output")" = "sample" ]
  [ "$(jq -r '.tags | length' <<< "$output")" = "2" ]
  [ "$(jq -r '.append.timestamp' <<< "$output")" = "true" ]
}

@test "fm_parse returns {} for file without frontmatter" {
  printf 'no fm here\n' > "$NOTE"
  run fm_parse "$NOTE"
  [ "$output" = "{}" ]
}

@test "fm_body strips frontmatter and preserves body" {
  run fm_body "$NOTE"
  [[ "$output" == *"body line one"* ]]
  [[ "$output" != *"title: sample"* ]]
}

@test "fm_get returns nested key" {
  run fm_get "$NOTE" "append.format" ""
  [[ "$output" == *"%Y-%m-%d"* ]]
}

@test "fm_get returns default for missing key" {
  run fm_get "$NOTE" "nonexistent" "fallback"
  [ "$output" = "fallback" ]
}

@test "fm_set mutates scalar in place preserving body" {
  fm_set "$NOTE" "title" "new-title"
  run fm_get "$NOTE" "title" ""
  [ "$output" = "new-title" ]
  run fm_body "$NOTE"
  [[ "$output" == *"body line one"* ]]
}

@test "fm_emit produces --- fences" {
  run fm_emit '{"title":"x","tags":["a","b"]}'
  [[ "$output" == "---"* ]]
  [[ "$output" == *"title: x"* ]]
}

@test "fm_merge: overrides win on pinned keys" {
  local tmpl='{"title":"tmpl","slug":"tmpl","kind":"meeting"}'
  local ovr='{"slug":"actual","kind":"inbox","created_at":"now","updated_at":"now"}'
  run fm_merge "$tmpl" "$ovr"
  [ "$(jq -r '.slug' <<< "$output")" = "actual" ]
  [ "$(jq -r '.kind' <<< "$output")" = "inbox" ]
  [ "$(jq -r '.created_at' <<< "$output")" = "now" ]
}

@test "fm_merge: template wins on non-pinned keys" {
  local tmpl='{"title":"Template Title","attendees":[]}'
  local ovr='{"slug":"x","kind":"meeting"}'
  run fm_merge "$tmpl" "$ovr"
  [ "$(jq -r '.title' <<< "$output")" = "Template Title" ]
  [ "$(jq '.attendees | type' <<< "$output")" = "\"array\"" ]
}

@test "fm_merge: tags are set-unioned" {
  run fm_merge '{"tags":["a","b"]}' '{"tags":["b","c"]}'
  local tags
  tags="$(jq -r '.tags | sort | join(",")' <<< "$output")"
  [ "$tags" = "a,b,c" ]
}
