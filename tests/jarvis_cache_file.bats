#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load jarvis_helper

setup() {
  jarvis_common_setup
  # shellcheck source=/dev/null
  source "${CLIFT_JARVIS_DIR}/lib/cache/file.sh"
}
teardown() { jarvis_common_teardown; }

@test "cache_get on missing key -> exit 1" {
  run cache_get test calendar 300
  [ "$status" -eq 1 ]
}

@test "cache_put then cache_get within TTL -> returns content" {
  cache_put test calendar '{"events":[]}'
  run cache_get test calendar 300
  [ "$status" -eq 0 ]
  [ "$output" = '{"events":[]}' ]
}

@test "cache_get past TTL -> exit 1" {
  cache_put test calendar '{"events":[]}'
  # Backdate the file 600s
  touch -d "@$(($(date +%s) - 600))" "$JARVIS_HOME/test/cache/calendar.json"
  run cache_get test calendar 300
  [ "$status" -eq 1 ]
}

@test "cache_put is atomic -- no partial files visible" {
  cache_put test foo '{"a":1}'
  [ ! -f "$JARVIS_HOME/test/cache/foo.json.tmp" ]
  [ -f "$JARVIS_HOME/test/cache/foo.json" ]
}

@test "cache_get TTL=0 always stale" {
  cache_put test calendar '{"events":[]}'
  run cache_get test calendar 0
  [ "$status" -eq 1 ]
}

@test "JARVIS_FAKE_NOW shifts TTL evaluation" {
  cache_put test calendar '{"events":[]}'
  # mtime ~ real now; fake-now 600s in future -> past TTL
  future=$(( $(date +%s) + 600 ))
  if date -u -d "@$future" +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
    JARVIS_FAKE_NOW="$(date -u -d "@$future" +%Y-%m-%dT%H:%M:%SZ)"
  else
    JARVIS_FAKE_NOW="$(date -u -j -f %s "$future" +%Y-%m-%dT%H:%M:%SZ)"
  fi
  export JARVIS_FAKE_NOW
  run cache_get test calendar 300
  [ "$status" -eq 1 ]
}
