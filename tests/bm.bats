#!/usr/bin/env bats
# End-to-end tests for examples/bm/ — one test per framework feature, not per command.
#
# Invocation strategy: framework router (preferred).
#   A wrapper is built into examples/bm/bin/bm (gitignored) pointing at the
#   real CLI_DIR so that features mediated by the wrapper — mutex enforcement,
#   choices validation, did-you-mean, persistent flags, aliases — are exercised
#   on the same code path users hit.
#   BM_HOME is redirected to a per-test tmpdir for data isolation; no test
#   reads or writes the developer's real bookmark store.
#
# Tests 9–10 (dynamic completer, rm --force) use direct invocation where the
#   framework path would add no coverage over what the unit-level call proves.

bats_require_minimum_version 1.5.0

load test_helper

BM_CLI_DIR=""

setup() {
  common_setup

  # Point CLI_DIR at the real bm example so the pre-compiled .clift/ cache
  # and all command scripts are reachable without re-scaffolding.
  BM_CLI_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../examples/bm" && pwd)"
  local framework_dir
  framework_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export CLI_DIR="$BM_CLI_DIR"
  export CLI_NAME="bm"
  export CLI_VERSION="0.1.0"
  export FRAMEWORK_DIR="$framework_dir"
  export LOG_THEME="minimal"

  # Per-test data isolation — redirect the bookmark store away from the
  # developer's real $HOME / XDG_DATA_HOME.
  BM_HOME="$(mktemp -d)"
  export BM_HOME

  # Build the wrapper into examples/bm/bin/bm (path is gitignored; rebuilt
  # fresh each test so path expansions are current).
  build_test_wrapper
}

teardown() {
  rm -rf "$BM_HOME"
  # Remove the generated wrapper — it encodes absolute paths and is not a
  # committed artifact. Failure here is non-fatal.
  rm -f "$BM_CLI_DIR/bin/bm"
  common_teardown
}

# Convenience: add one bookmark via the wrapper.
_bm_add() {
  run "$CLI_DIR/bin/bm" add "$@"
}

# ---------------------------------------------------------------------------
# Test 1: add + list — basic persistence and list flag
# ---------------------------------------------------------------------------

@test "add happy path: bookmark appears in list output" {
  _bm_add "https://taskfile.dev" --name task --tag build --tag cli
  [ "$status" -eq 0 ]

  run "$CLI_DIR/bin/bm" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"task"* ]]
  [[ "$output" == *"taskfile.dev"* ]]
}

# ---------------------------------------------------------------------------
# Test 2: choices flag — --format json and --format yaml parse correctly
# ---------------------------------------------------------------------------

@test "list --format json produces valid JSON array with expected shape" {
  _bm_add "https://example.com" --name eg --tag test
  [ "$status" -eq 0 ]

  run "$CLI_DIR/bin/bm" list --format json
  [ "$status" -eq 0 ]
  # Must parse as JSON.
  echo "$output" | jq -e '. | type == "array"'
  # The one entry must have a name field matching what we added.
  name="$(echo "$output" | jq -r '.[0].name')"
  [ "$name" = "eg" ]
}

@test "list --format yaml produces YAML with the bookmark name" {
  _bm_add "https://example.com" --name eg --tag test
  [ "$status" -eq 0 ]

  run "$CLI_DIR/bin/bm" list --format yaml
  [ "$status" -eq 0 ]
  [[ "$output" == *"name: eg"* ]]
  [[ "$output" == *"url: https://example.com"* ]]
}

# ---------------------------------------------------------------------------
# Test 3: choices validation — --format bogus exits non-zero
# ---------------------------------------------------------------------------

@test "list --format bogus: choices validation rejects invalid value" {
  run "$CLI_DIR/bin/bm" list --format bogus
  [ "$status" -ne 0 ]
  # The clift parser emits a choices-violation message.
  [[ "$output" == *"bogus"* ]]
}

# ---------------------------------------------------------------------------
# Test 4: pattern validation — ftp:// URL rejected by add.sh
# ---------------------------------------------------------------------------

@test "add ftp:// URL: pattern check exits non-zero with clear error" {
  run "$CLI_DIR/bin/bm" add "ftp://example.com" --name x
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid url"* ]] || [[ "$output" == *"https?://"* ]]
}

# ---------------------------------------------------------------------------
# Test 5: mutex group — --add and --remove together are rejected
# ---------------------------------------------------------------------------

@test "tag --add and --remove together: mutually exclusive group error" {
  # Need an existing bookmark for the tag command to reach the mutex check.
  _bm_add "https://example.com" --name eg
  [ "$status" -eq 0 ]

  run "$CLI_DIR/bin/bm" tag eg --add foo --remove bar
  [ "$status" -ne 0 ]
  [[ "$output" == *"mutually exclusive"* ]]
}

# ---------------------------------------------------------------------------
# Test 6: persistent flag — --profile isolates stores
# ---------------------------------------------------------------------------

@test "--profile work and --profile home are isolated stores" {
  # Add to the 'work' profile.
  run "$CLI_DIR/bin/bm" --profile work add "https://work.example.com" --name work-bm
  [ "$status" -eq 0 ]

  # The 'home' profile should be empty — the work bookmark must not appear.
  run "$CLI_DIR/bin/bm" --profile home list --format json
  [ "$status" -eq 0 ]
  count="$(echo "$output" | jq '. | length')"
  [ "$count" -eq 0 ]

  # The work profile must contain the added bookmark.
  run "$CLI_DIR/bin/bm" --profile work list --format json
  [ "$status" -eq 0 ]
  name="$(echo "$output" | jq -r '.[0].name')"
  [ "$name" = "work-bm" ]
}

# ---------------------------------------------------------------------------
# Test 7: command alias — `bm ls` is identical to `bm list`
# ---------------------------------------------------------------------------

@test "ls alias: output matches canonical list command" {
  _bm_add "https://example.com" --name eg
  [ "$status" -eq 0 ]

  run "$CLI_DIR/bin/bm" list --format json
  [ "$status" -eq 0 ]
  list_out="$output"

  run "$CLI_DIR/bin/bm" ls --format json
  [ "$status" -eq 0 ]

  # Both must parse and return the same bookmark name.
  name_list="$(echo "$list_out" | jq -r '.[0].name')"
  name_ls="$(echo "$output"    | jq -r '.[0].name')"
  [ "$name_list" = "$name_ls" ]
}

# ---------------------------------------------------------------------------
# Test 8: did-you-mean — typo exits non-zero and suggests the real command
# ---------------------------------------------------------------------------

@test "typo 'lstt' exits non-zero and suggests list via did-you-mean" {
  run "$CLI_DIR/bin/bm" lstt
  [ "$status" -ne 0 ]
  # The wrapper emits a did-you-mean suggestion for the nearest command.
  [[ "$output" == *"list"* ]]
}

# ---------------------------------------------------------------------------
# Test 9: dynamic completer — unit test (sources completion.sh directly)
# ---------------------------------------------------------------------------

@test "dynamic completer: clift_complete_open_pos1 returns stored bookmark names" {
  # Populate the store directly via store.sh (no wrapper needed).
  run bash -c "
    export BM_HOME='$BM_HOME'
    export BM_PROFILE='default'
    source '$BM_CLI_DIR/lib/store.sh'
    bm_store_add 'https://taskfile.dev' 'task' '' build cli
    bm_store_add 'https://example.com'  'eg'   ''
  "
  [ "$status" -eq 0 ]

  run bash -c "
    export BM_HOME='$BM_HOME'
    export HOME='$BM_HOME'
    source '$BM_CLI_DIR/.clift/overrides/completion.sh'
    clift_complete_open_pos1
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"task"* ]]
  [[ "$output" == *"eg"* ]]
}

# ---------------------------------------------------------------------------
# Test 10: rm --force — bool flag; store is empty afterwards
# ---------------------------------------------------------------------------

@test "rm --force removes bookmark; subsequent list is empty" {
  _bm_add "https://example.com" --name eg
  [ "$status" -eq 0 ]

  run "$CLI_DIR/bin/bm" rm eg --force
  [ "$status" -eq 0 ]

  run "$CLI_DIR/bin/bm" list --format json
  [ "$status" -eq 0 ]
  count="$(echo "$output" | jq '. | length')"
  [ "$count" -eq 0 ]
}
