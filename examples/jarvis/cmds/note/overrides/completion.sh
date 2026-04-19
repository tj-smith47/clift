#!/usr/bin/env bash
# Dynamic completer for `jarvis note --tag`.
# The hidden _complete subcommand sources this file and calls
# clift_complete_note_tag with the current prefix.

clift_complete_note_tag() {
  local prefix="${1:-}"
  local tags=(arch queue bug 1:1 idea retro release infra oncall onboarding)
  for t in "${tags[@]}"; do
    [[ "$t" == "$prefix"* ]] && printf '%s\n' "$t"
  done
}
