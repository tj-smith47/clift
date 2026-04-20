#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load jarvis_helper

setup() {
  jarvis_common_setup
  source "$CLIFT_JARVIS_DIR/lib/state/profile.sh"
  source "$CLIFT_JARVIS_DIR/lib/note/resolve.sh"
  state_ensure_tree
  NOTES="$(note_root)"
  mkdir -p "$NOTES/inbox" "$NOTES/ref" "$NOTES/projects/clift" "$NOTES/meetings"
  : > "$NOTES/inbox/audit-the-flock.md"
  : > "$NOTES/ref/etcd-restore-runbook.md"
  : > "$NOTES/projects/clift/perf-investigation.md"
  : > "$NOTES/meetings/1on1-alice-2026-04-18.md"

  cat > "$(note_index_file)" <<'EOF'
{
  "inbox/audit-the-flock": {"title":"Audit the flock path","kind":"inbox","tags":[]},
  "ref/etcd-restore-runbook": {"title":"Etcd Restore Runbook","kind":"ref","tags":["k3s"]},
  "projects/clift/perf-investigation": {"title":"Perf Investigation","kind":"project","tags":["clift","perf"]},
  "meetings/1on1-alice-2026-04-18": {"title":"1on1 Alice","kind":"meeting","tags":[]}
}
EOF
}
teardown() { jarvis_common_teardown; }

@test "note_resolve: explicit kind/slug short-circuits" {
  run note_resolve "ref/etcd-restore-runbook"
  [ "$status" -eq 0 ]
  [ "$output" = "ref/etcd-restore-runbook" ]
}

@test "note_resolve: unique slug across kinds" {
  run note_resolve "perf-investigation"
  [ "$status" -eq 0 ]
  [ "$output" = "projects/clift/perf-investigation" ]
}

@test "note_resolve: title exact (case-insensitive)" {
  run note_resolve "perf investigation"
  [ "$status" -eq 0 ]
  [ "$output" = "projects/clift/perf-investigation" ]
}

@test "note_resolve: title prefix" {
  run note_resolve "etcd restore"
  [ "$status" -eq 0 ]
  [ "$output" = "ref/etcd-restore-runbook" ]
}

@test "note_resolve: slug prefix" {
  run note_resolve "audit-the"
  [ "$status" -eq 0 ]
  [ "$output" = "inbox/audit-the-flock" ]
}

@test "note_resolve: unknown → exit 1" {
  run note_resolve "nonexistent"
  [ "$status" -eq 1 ]
}

@test "note_resolve: ambiguous prefix lists candidates on stderr" {
  mkdir -p "$NOTES/inbox"
  : > "$NOTES/inbox/foo-a.md"
  : > "$NOTES/inbox/foo-b.md"
  cat > "$(note_index_file)" <<'EOF'
{
  "inbox/foo-a": {"title":"Foo A","kind":"inbox","tags":[]},
  "inbox/foo-b": {"title":"Foo B","kind":"inbox","tags":[]}
}
EOF
  run note_resolve "foo"
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"inbox/foo-a"* ]]
  [[ "$output$stderr" == *"inbox/foo-b"* ]]
}

@test "note_path resolves to full .md path" {
  run note_path "ref/etcd-restore-runbook"
  [ "$output" = "$NOTES/ref/etcd-restore-runbook.md" ]
}

@test "note_kind_of + note_slug_of split on first slash only" {
  run note_kind_of "projects/clift/perf-investigation"
  [ "$output" = "projects" ]
  run note_slug_of "projects/clift/perf-investigation"
  [ "$output" = "clift/perf-investigation" ]
}
