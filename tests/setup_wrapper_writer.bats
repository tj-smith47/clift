#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

# Tests for lib/setup/wrapper_writer.sh — emits cmds/<name>/<name>.sh
# wrapper scripts and cmds/<name>/Taskfile.yaml for `clift init --from`.
#
# Filesystem isolation: HOME is redirected by common_setup; every
# generated artefact lands under $TEST_DIR.

load test_helper

setup() {
  common_setup
  # shellcheck source=../lib/setup/wrapper_writer.sh
  source "$FRAMEWORK_DIR/lib/setup/wrapper_writer.sh"
  DEST="$TEST_DIR/cmds_dir"
  mkdir -p "$DEST"
}

teardown() {
  common_teardown
}

# --- Wrapper script: passthrough variant -------------------------------

@test "passthrough wrapper: shebang + comment + exec line" {
  entry='{"name":"build","task":"build","desc":"Build it","summary":"","aliases":[],"wildcard":false,"vars":{},"requires_vars":[],"passthrough":true}'
  run -0 write_wrapper_script "$entry" "$DEST"

  [ -f "$DEST/build.sh" ]
  run -0 head -1 "$DEST/build.sh"
  [ "$output" = "#!/usr/bin/env bash" ]

  # Comment line names the original go-task task.
  grep -q '^# Wraps go-task task: build (from Taskfile.user.yaml)$' "$DEST/build.sh"

  # `set -euo pipefail` is mandatory.
  grep -q '^set -euo pipefail$' "$DEST/build.sh"

  # Exec line forwards positional `$@` via `--`. The router's
  # true-passthrough exec passes the user's argv directly to the script,
  # so we forward `$@` without translating through CLIFT_POS_* env vars.
  # `--silent` must precede --taskfile so go-task's own `task: [..] bash`
  # lines never reach the user.
  grep -qF 'exec task --silent --taskfile "${CLI_DIR}/Taskfile.user.yaml" build -- "${@}"' "$DEST/build.sh"
  ! grep -q '\\"' "$DEST/build.sh"
}

@test "passthrough wrapper: invoking forwards positional argv via task ... --" {
  entry='{"name":"build","task":"build","desc":"","summary":"","aliases":[],"wildcard":false,"vars":{},"requires_vars":[],"passthrough":true}'
  run -0 write_wrapper_script "$entry" "$DEST"

  # Stub `task` on PATH that prints argv as one-arg-per-line for assertion.
  cat > "$TEST_DIR/task" <<'STUB'
#!/usr/bin/env bash
for a in "$@"; do printf 'ARG[%s]\n' "$a"; done
STUB
  chmod +x "$TEST_DIR/task"

  PATH="$TEST_DIR:$PATH" CLI_DIR="$TEST_DIR" \
    run -0 bash "$DEST/build.sh" alpha 'beta gamma' delta

  [[ "$output" == *"ARG[--silent]"* ]]
  [[ "$output" == *"ARG[--taskfile]"* ]]
  [[ "$output" == *"ARG[$TEST_DIR/Taskfile.user.yaml]"* ]]
  [[ "$output" == *"ARG[build]"* ]]
  [[ "$output" == *"ARG[--]"* ]]
  [[ "$output" == *"ARG[alpha]"* ]]
  [[ "$output" == *"ARG[beta gamma]"* ]]
  [[ "$output" == *"ARG[delta]"* ]]
}

@test "passthrough wrapper: no positionals → trailing -- with nothing after" {
  entry='{"name":"build","task":"build","desc":"","summary":"","aliases":[],"wildcard":false,"vars":{},"requires_vars":[],"passthrough":true}'
  run -0 write_wrapper_script "$entry" "$DEST"

  cat > "$TEST_DIR/task" <<'STUB'
#!/usr/bin/env bash
for a in "$@"; do printf 'ARG[%s]\n' "$a"; done
STUB
  chmod +x "$TEST_DIR/task"

  PATH="$TEST_DIR:$PATH" CLI_DIR="$TEST_DIR" run -0 bash "$DEST/build.sh"

  # Last ARG line must be the literal `--` — nothing after it.
  last="$(printf '%s\n' "$output" | tail -1)"
  [ "$last" = "ARG[--]" ]
}

# --- Wrapper script: parsed-flag variant -------------------------------

@test "parsed-flag wrapper: required vars + vars-map → conditional _args entries" {
  entry='{"name":"deploy","task":"deploy","desc":"Deploy","summary":"","aliases":[],"wildcard":false,"vars":{"DRY_RUN":false,"NAME":"myapp"},"requires_vars":["ENV"],"passthrough":false}'
  run -0 write_wrapper_script "$entry" "$DEST"

  [ -f "$DEST/deploy.sh" ]

  # _args is built up conditionally so absent bool flags don't override
  # go-task's source defaults (see var_inference.sh header — bool flags
  # carry no clift `default`, so source defaults must survive).
  grep -q '^_args=()$' "$DEST/deploy.sh"

  # Required var entry — fires every run because parser always sets it.
  grep -qF '[[ -n "${CLIFT_FLAG_ENV+x}" ]] && _args+=("ENV=${CLIFT_FLAG_ENV}")' "$DEST/deploy.sh"

  # Vars-map keys preserve declaration order from the JSON, with the
  # required var first.
  grep -qF '[[ -n "${CLIFT_FLAG_DRY_RUN+x}" ]] && _args+=("DRY_RUN=${CLIFT_FLAG_DRY_RUN}")' "$DEST/deploy.sh"
  grep -qF '[[ -n "${CLIFT_FLAG_NAME+x}" ]] && _args+=("NAME=${CLIFT_FLAG_NAME}")' "$DEST/deploy.sh"

  # Exec line uses the empty-safe array expansion idiom.
  grep -qF 'exec task --silent --taskfile "${CLI_DIR}/Taskfile.user.yaml" deploy "${_args[@]+"${_args[@]}"}"' "$DEST/deploy.sh"
}

@test "parsed-flag wrapper: dashed flag names map back to CLIFT_FLAG_<UPPER>_<UNDERSCORE>" {
  # Reader emits original go-task var name (DRY_RUN). Wrapper reads
  # CLIFT_FLAG_DRY_RUN. Names with dashes never appear in go-task vars,
  # so we assert the underscore form survives.
  entry='{"name":"deploy","task":"deploy","desc":"","summary":"","aliases":[],"wildcard":false,"vars":{"FOO_BAR_BAZ":"x"},"requires_vars":[],"passthrough":false}'
  run -0 write_wrapper_script "$entry" "$DEST"

  grep -qF '[[ -n "${CLIFT_FLAG_FOO_BAR_BAZ+x}" ]] && _args+=("FOO_BAR_BAZ=${CLIFT_FLAG_FOO_BAR_BAZ}")' "$DEST/deploy.sh"
}

@test "parsed-flag wrapper: namespaced task name → script filename uses dots" {
  entry='{"name":"db:migrate","task":"db:migrate","desc":"","summary":"","aliases":[],"wildcard":false,"vars":{},"requires_vars":["TARGET"],"passthrough":false}'
  run -0 write_wrapper_script "$entry" "$DEST"

  [ -f "$DEST/db.migrate.sh" ]
  grep -q 'exec task --silent --taskfile "${CLI_DIR}/Taskfile.user.yaml" db:migrate' "$DEST/db.migrate.sh"
}

# --- Wrapper script: wildcard variant ----------------------------------

@test "wildcard wrapper: positional-required check, * substituted with \${target}" {
  entry='{"name":"deploy","task":"deploy:*","desc":"Deploy","summary":"","aliases":[],"wildcard":true,"vars":{},"requires_vars":[],"passthrough":true}'
  run -0 write_wrapper_script "$entry" "$DEST"

  [ -f "$DEST/deploy.sh" ]
  # Wildcard tasks are router-passthrough — argv arrives as $1, not
  # CLIFT_POS_*. The :? guard reads $1 directly.
  grep -q '^target="${1:?Usage: deploy <TARGET>}"$' "$DEST/deploy.sh"
  grep -q '^exec task --silent --taskfile "${CLI_DIR}/Taskfile.user.yaml" "deploy:${target}"$' "$DEST/deploy.sh"
}

@test "wildcard wrapper: multi-segment build:*:release substitutes mid-segment" {
  entry='{"name":"build","task":"build:*:release","desc":"","summary":"","aliases":[],"wildcard":true,"vars":{},"requires_vars":[],"passthrough":true}'
  run -0 write_wrapper_script "$entry" "$DEST"

  grep -q '^exec task --silent --taskfile "${CLI_DIR}/Taskfile.user.yaml" "build:${target}:release"$' "$DEST/build.sh"
}

@test "wildcard wrapper: missing positional → :? message on stderr, nonzero exit" {
  entry='{"name":"deploy","task":"deploy:*","desc":"","summary":"","aliases":[],"wildcard":true,"vars":{},"requires_vars":[],"passthrough":true}'
  run -0 write_wrapper_script "$entry" "$DEST"

  # No `task` on PATH needed — the :? guard fires before exec.
  CLI_DIR="$TEST_DIR" run bash "$DEST/deploy.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage: deploy <TARGET>"* ]]
}

# --- Wrapper script: file mode -----------------------------------------

@test "wrapper script is chmod +x" {
  entry='{"name":"build","task":"build","desc":"","summary":"","aliases":[],"wildcard":false,"vars":{},"requires_vars":[],"passthrough":true}'
  run -0 write_wrapper_script "$entry" "$DEST"

  [ -x "$DEST/build.sh" ]
}

# --- cmds Taskfile.yaml: parsed-flag -----------------------------------

@test "cmds Taskfile parsed-flag: FLAGS list built from requires_vars + vars" {
  entry='{"name":"deploy","task":"deploy","desc":"Deploy","summary":"","aliases":[],"wildcard":false,"vars":{"DRY_RUN":false,"REPLICAS":3,"NAME":"myapp"},"requires_vars":["ENV"],"passthrough":false}'
  run -0 write_cmd_taskfile "$entry" "$DEST"

  [ -f "$DEST/Taskfile.yaml" ]

  # yq round-trip — the file must parse cleanly.
  run -0 yq -e '.tasks.default.desc' "$DEST/Taskfile.yaml"
  [ "$output" = "Deploy" ]

  # Each FLAG entry surfaces with the right type.
  run -0 yq -r '.tasks.default.vars.FLAGS | map(.name) | join(",")' "$DEST/Taskfile.yaml"
  [ "$output" = "env,dry-run,replicas,name" ]

  run -0 yq -r '.tasks.default.vars.FLAGS[] | select(.name == "env") | .required' "$DEST/Taskfile.yaml"
  [ "$output" = "true" ]

  run -0 yq -r '.tasks.default.vars.FLAGS[] | select(.name == "dry-run") | .type' "$DEST/Taskfile.yaml"
  [ "$output" = "bool" ]

  run -0 yq -r '.tasks.default.vars.FLAGS[] | select(.name == "replicas") | .type' "$DEST/Taskfile.yaml"
  [ "$output" = "int" ]

  run -0 yq -r '.tasks.default.vars.FLAGS[] | select(.name == "name") | .default' "$DEST/Taskfile.yaml"
  [ "$output" = "myapp" ]
}

@test "cmds Taskfile parsed-flag: quoted-bool string \"true\" resolves to bool type with no default" {
  # Reader serializes JSON-string "true" → tojson → '"true"' (yaml-quoted)
  # which var_inference recognizes as a bool literal. validate.sh rule 6
  # forbids bool flags with `default`, so the FLAG entry must not carry one.
  entry='{"name":"build","task":"build","desc":"","summary":"","aliases":[],"wildcard":false,"vars":{"RELEASE":"true"},"requires_vars":[],"passthrough":false}'
  run -0 write_cmd_taskfile "$entry" "$DEST"

  run -0 yq -r '.tasks.default.vars.FLAGS[0].type' "$DEST/Taskfile.yaml"
  [ "$output" = "bool" ]
  run -0 yq -r '.tasks.default.vars.FLAGS[0] | has("default")' "$DEST/Taskfile.yaml"
  [ "$output" = "false" ]
}

# --- cmds Taskfile.yaml: passthrough -----------------------------------

@test "cmds Taskfile passthrough: vars.FLAGS omitted entirely" {
  entry='{"name":"build","task":"build","desc":"Build it","summary":"","aliases":[],"wildcard":false,"vars":{},"requires_vars":[],"passthrough":true}'
  run -0 write_cmd_taskfile "$entry" "$DEST"

  # No `vars:` block at all.
  run yq -e '.tasks.default.vars' "$DEST/Taskfile.yaml"
  [ "$status" -ne 0 ]

  # Cmd line is still present and dispatches to router.
  run -0 yq -r '.tasks.default.cmd' "$DEST/Taskfile.yaml"
  [[ "$output" == *"router.sh"* ]]
}

# --- cmds Taskfile.yaml: wildcard --------------------------------------

@test "cmds Taskfile wildcard: vars.FLAGS omitted; desc gains <TARGET> hint" {
  entry='{"name":"deploy","task":"deploy:*","desc":"Deploy","summary":"","aliases":[],"wildcard":true,"vars":{},"requires_vars":[],"passthrough":true}'
  run -0 write_cmd_taskfile "$entry" "$DEST"

  run yq -e '.tasks.default.vars' "$DEST/Taskfile.yaml"
  [ "$status" -ne 0 ]

  run -0 yq -r '.tasks.default.desc' "$DEST/Taskfile.yaml"
  [ "$output" = "Deploy <TARGET>" ]
}

@test "cmds Taskfile wildcard: empty desc → synthetic 'Wraps go-task wildcard ...' " {
  entry='{"name":"deploy","task":"deploy:*","desc":"","summary":"","aliases":[],"wildcard":true,"vars":{},"requires_vars":[],"passthrough":true}'
  run -0 write_cmd_taskfile "$entry" "$DEST"

  run -0 yq -r '.tasks.default.desc' "$DEST/Taskfile.yaml"
  [ "$output" = "Wraps go-task wildcard deploy:*" ]
}

# --- cmds Taskfile.yaml: optional fields -------------------------------

@test "cmds Taskfile: empty aliases array → field absent from YAML" {
  entry='{"name":"build","task":"build","desc":"Build","summary":"","aliases":[],"wildcard":false,"vars":{},"requires_vars":[],"passthrough":true}'
  run -0 write_cmd_taskfile "$entry" "$DEST"

  run yq -e '.tasks.default.aliases' "$DEST/Taskfile.yaml"
  [ "$status" -ne 0 ]
}

@test "cmds Taskfile: empty summary → field absent from YAML" {
  entry='{"name":"build","task":"build","desc":"Build","summary":"","aliases":[],"wildcard":false,"vars":{},"requires_vars":[],"passthrough":true}'
  run -0 write_cmd_taskfile "$entry" "$DEST"

  run yq -e '.tasks.default.summary' "$DEST/Taskfile.yaml"
  [ "$status" -ne 0 ]
}

@test "cmds Taskfile: aliases populated → flow-style list rendered" {
  entry='{"name":"deploy","task":"deploy","desc":"Deploy","summary":"","aliases":["d","dep"],"wildcard":false,"vars":{},"requires_vars":[],"passthrough":true}'
  run -0 write_cmd_taskfile "$entry" "$DEST"

  run -0 yq -r '.tasks.default.aliases | join(",")' "$DEST/Taskfile.yaml"
  [ "$output" = "d,dep" ]
}

@test "cmds Taskfile: summary populated → block-literal rendered" {
  entry='{"name":"deploy","task":"deploy","desc":"Deploy","summary":"Line 1\nLine 2","aliases":[],"wildcard":false,"vars":{},"requires_vars":[],"passthrough":true}'
  run -0 write_cmd_taskfile "$entry" "$DEST"

  run -0 yq -r '.tasks.default.summary' "$DEST/Taskfile.yaml"
  [[ "$output" == *"Line 1"* ]]
  [[ "$output" == *"Line 2"* ]]
}

# --- cmds Taskfile.yaml: yq round-trip on every variant ----------------

@test "generated Taskfile.yaml is parseable by yq (passthrough)" {
  entry='{"name":"build","task":"build","desc":"Build","summary":"","aliases":[],"wildcard":false,"vars":{},"requires_vars":[],"passthrough":true}'
  run -0 write_cmd_taskfile "$entry" "$DEST"
  run -0 yq -e '.version, .tasks.default.cmd' "$DEST/Taskfile.yaml"
}

@test "generated Taskfile.yaml is parseable by yq (parsed-flag)" {
  entry='{"name":"deploy","task":"deploy","desc":"","summary":"","aliases":["d"],"wildcard":false,"vars":{"DRY_RUN":false},"requires_vars":["ENV"],"passthrough":false}'
  run -0 write_cmd_taskfile "$entry" "$DEST"
  run -0 yq -e '.tasks.default.vars.FLAGS' "$DEST/Taskfile.yaml"
}

@test "generated Taskfile.yaml is parseable by yq (wildcard)" {
  entry='{"name":"deploy","task":"deploy:*","desc":"","summary":"","aliases":[],"wildcard":true,"vars":{},"requires_vars":[],"passthrough":true}'
  run -0 write_cmd_taskfile "$entry" "$DEST"
  run -0 yq -e '.tasks.default.cmd' "$DEST/Taskfile.yaml"
}

# --- cmds Taskfile.yaml: multi-task (array input) ----------------------

@test "cmds Taskfile array: lint:default + lint:eslint → default + eslint blocks" {
  arr='[
    {"name":"lint","task":"lint:default","desc":"Lint everything","summary":"","aliases":[],"wildcard":false,"vars":{},"requires_vars":[],"passthrough":true},
    {"name":"lint:eslint","task":"lint:eslint","desc":"Lint with ESLint","summary":"","aliases":[],"wildcard":false,"vars":{},"requires_vars":[],"passthrough":true}
  ]'
  run -0 write_cmd_taskfile "$arr" "$DEST"

  [ -f "$DEST/Taskfile.yaml" ]

  # Both task keys exist under tasks:
  has_default="$(yq '.tasks | has("default")' "$DEST/Taskfile.yaml")"
  [ "$has_default" = "true" ]
  has_eslint="$(yq '.tasks | has("eslint")' "$DEST/Taskfile.yaml")"
  [ "$has_eslint" = "true" ]

  # Each block carries its own desc.
  d="$(yq -r '.tasks.default.desc' "$DEST/Taskfile.yaml")"
  [ "$d" = "Lint everything" ]
  e="$(yq -r '.tasks.eslint.desc' "$DEST/Taskfile.yaml")"
  [ "$e" = "Lint with ESLint" ]

  # Each block dispatches via the router (cmd line preserved).
  cd_line="$(yq -r '.tasks.default.cmd' "$DEST/Taskfile.yaml")"
  [[ "$cd_line" == *"router.sh"* ]]
  ce_line="$(yq -r '.tasks.eslint.cmd' "$DEST/Taskfile.yaml")"
  [[ "$ce_line" == *"router.sh"* ]]
}

@test "cmds Taskfile array: parsed-flag sub-task carries vars.FLAGS only on that block" {
  arr='[
    {"name":"db","task":"db:default","desc":"DB top-level","summary":"","aliases":[],"wildcard":false,"vars":{},"requires_vars":[],"passthrough":true},
    {"name":"db:migrate","task":"db:migrate","desc":"Migrate","summary":"","aliases":[],"wildcard":false,"vars":{},"requires_vars":["TARGET"],"passthrough":false}
  ]'
  run -0 write_cmd_taskfile "$arr" "$DEST"

  # default → passthrough, no FLAGS.
  run yq -e '.tasks.default.vars.FLAGS' "$DEST/Taskfile.yaml"
  [ "$status" -ne 0 ]

  # migrate → parsed-flag, FLAGS present with `target` (lowercased).
  run -0 yq -r '.tasks.migrate.vars.FLAGS | map(.name) | join(",")' "$DEST/Taskfile.yaml"
  [ "$output" = "target" ]
}

@test "cmds Taskfile array: single-element array → still keys correctly" {
  arr='[
    {"name":"build","task":"build","desc":"Build","summary":"","aliases":[],"wildcard":false,"vars":{},"requires_vars":[],"passthrough":true}
  ]'
  run -0 write_cmd_taskfile "$arr" "$DEST"

  has_default="$(yq '.tasks | has("default")' "$DEST/Taskfile.yaml")"
  [ "$has_default" = "true" ]
}

# --- Error handling ----------------------------------------------------

@test "write_wrapper_script: missing args rejected" {
  run write_wrapper_script
  [ "$status" -ne 0 ]
  [[ "$output" == *"requires"* ]]
}

@test "write_cmd_taskfile: missing args rejected" {
  run write_cmd_taskfile
  [ "$status" -ne 0 ]
  [[ "$output" == *"requires"* ]]
}

@test "write_wrapper_script: missing dest dir rejected" {
  entry='{"name":"build","task":"build","desc":"","summary":"","aliases":[],"wildcard":false,"vars":{},"requires_vars":[],"passthrough":true}'
  run write_wrapper_script "$entry" "$TEST_DIR/does-not-exist"
  [ "$status" -ne 0 ]
  [[ "$output" == *"dest dir not found"* ]]
}

@test "write_cmd_taskfile: missing dest dir rejected" {
  entry='{"name":"build","task":"build","desc":"","summary":"","aliases":[],"wildcard":false,"vars":{},"requires_vars":[],"passthrough":true}'
  run write_cmd_taskfile "$entry" "$TEST_DIR/does-not-exist"
  [ "$status" -ne 0 ]
  [[ "$output" == *"dest dir not found"* ]]
}
