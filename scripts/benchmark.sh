#!/usr/bin/env bash
# Benchmark clift overhead: measures the time from CLI invocation to script
# execution, comparing a clift-dispatched command vs. running the script directly.
#
# Reports:
#   - End-to-end: direct script vs clift standard mode (warm cache)
#   - Cold-cache vs warm-cache invocation (what first-run users pay)
#   - Per-stage attribution table (isolated stage costs — median, not average)
#
# Per-stage numbers come from invoking each stage in isolation, NOT from
# inline instrumentation of the hot path. Runtime checkpoints in
# wrapper/router/prelude/exec would cost forks even when unused and fight
# the "minimize forks on the hot path" convention. See
# .claude/plans/2026-04-14-cobra-parity-and-overrides.md Task 6.4.
#
# Note: requires GNU date (`date +%s%N` nanosecond resolution). macOS users
# need coreutils (`brew install coreutils`) or this will fall back to
# garbage timings. Most developers here are on Linux.
#
# Usage: scripts/benchmark.sh [iterations]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRAMEWORK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ITERATIONS="${1:-20}"

# compile.sh is an order of magnitude slower than the other stages (jq +
# task --list-all). Running it ITERATIONS times for the cold-cache section
# would dominate wall time for little extra signal, so cap it.
COMPILE_ITERS=$(( ITERATIONS < 5 ? ITERATIONS : 5 ))

echo "clift overhead benchmark (${ITERATIONS} iterations)"
echo "================================================"

# Set up a temporary CLI
BENCH_DIR="$(mktemp -d)"
trap 'rm -rf "$BENCH_DIR"' EXIT
export HOME="$BENCH_DIR"
export PROMPT=false
export CLIFT_RC_FILE="$HOME/.bashrc"
touch "$HOME/.bashrc"

# Bootstrap
bash "$FRAMEWORK_DIR/lib/setup/setup.sh" \
  "$BENCH_DIR/bench" "$FRAMEWORK_DIR" "bench" "0.1.0" "minimal" "standard" \
  > /dev/null 2>&1

# Create a trivial command
mkdir -p "$BENCH_DIR/bench/cmds/noop"
cat > "$BENCH_DIR/bench/cmds/noop/Taskfile.yaml" <<'YAML'
version: '3'
vars:
  FLAGS: []
tasks:
  default:
    vars:
      FLAGS: []
    cmd: "CLI_ARGS='{{.CLI_ARGS}}' '{{.FRAMEWORK_DIR}}/lib/router/router.sh' '{{.TASK}}'"
YAML
cat > "$BENCH_DIR/bench/cmds/noop/noop.sh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
echo "ok"
BASH
chmod +x "$BENCH_DIR/bench/cmds/noop/noop.sh"

# Add include to root Taskfile
_tmp="$(mktemp)"
awk '
  /# User commands/ { print; print "  noop:"; print "    taskfile: ./cmds/noop"; next }
  { print }
' "$BENCH_DIR/bench/Taskfile.yaml" > "$_tmp"
mv "$_tmp" "$BENCH_DIR/bench/Taskfile.yaml"

# Rebuild cache (export FRAMEWORK_DIR so task's dotenv + env both resolve includes)
export FRAMEWORK_DIR
bash "$FRAMEWORK_DIR/lib/flags/compile.sh" "$BENCH_DIR/bench" > /dev/null 2>&1 || true

CLI_DIR="$BENCH_DIR/bench"
WRAPPER="$CLI_DIR/bin/bench"
SCRIPT="$CLI_DIR/cmds/noop/noop.sh"
CACHE_DIR="$CLI_DIR/.clift"

# Snapshot the freshly-compiled cache so we can restore it after each
# cold-cache iteration without re-running setup.
CACHE_SNAPSHOT="$BENCH_DIR/cache-snapshot"
cp -R "$CACHE_DIR" "$CACHE_SNAPSHOT"

# Warmup — also exercises any one-time filesystem costs (dir creation,
# stat-format detection in cache.sh).
"$WRAPPER" noop > /dev/null 2>&1
bash "$SCRIPT" > /dev/null 2>&1

# --- helpers -----------------------------------------------------------------

# _median_ms <sample_file>
# Reads one integer-ms sample per line, prints the median. Requires at
# least one sample (caller guarantees).
_median_ms() {
  local f="$1" n mid
  n=$(wc -l < "$f")
  if (( n == 0 )); then echo 0; return; fi
  # Even-count: take the lower of the two middles (biases pessimistic —
  # fine for a regression trigger).
  mid=$(( (n + 1) / 2 ))
  sort -n "$f" | awk -v m="$mid" 'NR==m { print; exit }'
}

# _time_ns — prints current time in nanoseconds. GNU date only; macOS
# users need coreutils `gdate` or the result is meaningless (BSD date's
# `%N` literal trips here).
_time_ns() { date +%s%N; }

# _run_stage <label> <iters> <sample_file> -- <cmd...>
# Runs <cmd...> in a loop and appends per-iteration ms to <sample_file>.
# Caller is responsible for warmup and for any per-iteration reset (e.g.,
# wiping the cache before measuring a cold-path stage). <label> is
# informational — useful when the harness grows trace output.
_run_stage() {
  local _label="$1" iters="$2" samples="$3"
  : "${_label:?}"  # silence SC2034; the label is retained for future trace output
  shift 3
  [[ "$1" == "--" ]] && shift
  local i start end
  : > "$samples"
  for (( i=0; i<iters; i++ )); do
    start=$(_time_ns)
    "$@" > /dev/null 2>&1
    end=$(_time_ns)
    echo $(( (end - start) / 1000000 )) >> "$samples"
  done
}

# Restore the cache dir from the snapshot (used between cold-cache iters).
_reset_cache() {
  rm -rf "$CACHE_DIR"
  cp -R "$CACHE_SNAPSHOT" "$CACHE_DIR"
}

_wipe_cache() { rm -rf "$CACHE_DIR"; }

# --- end-to-end measurements (existing sections, preserved) -----------------

# Benchmark: direct script
echo ""
echo "Direct script execution:"
start=$(_time_ns)
for (( i=0; i<ITERATIONS; i++ )); do
  bash "$SCRIPT" > /dev/null 2>&1
done
end=$(_time_ns)
direct_ms=$(( (end - start) / 1000000 ))
direct_avg=$(( direct_ms / ITERATIONS ))
echo "  Total: ${direct_ms}ms  Avg: ${direct_avg}ms"

# Benchmark: clift wrapper (standard mode, warm cache)
echo ""
echo "clift standard mode (warm cache):"
start=$(_time_ns)
for (( i=0; i<ITERATIONS; i++ )); do
  "$WRAPPER" noop > /dev/null 2>&1
done
end=$(_time_ns)
clift_ms=$(( (end - start) / 1000000 ))
clift_avg=$(( clift_ms / ITERATIONS ))
echo "  Total: ${clift_ms}ms  Avg: ${clift_avg}ms"

overhead=$(( clift_avg - direct_avg ))
echo ""
echo "Overhead: ~${overhead}ms per invocation"
echo "  (wrapper → cache check → task → router → parser → script)"

# --- cold-vs-warm cache comparison ------------------------------------------

echo ""
echo "Cold vs warm cache (${COMPILE_ITERS} iterations each):"
# Cold: wipe cache dir before each invocation. Wrapper's clift_ensure_cache
# will trigger compile.sh on-demand.
cold_total=0
for (( i=0; i<COMPILE_ITERS; i++ )); do
  _wipe_cache
  start=$(_time_ns)
  "$WRAPPER" noop > /dev/null 2>&1
  end=$(_time_ns)
  cold_total=$(( cold_total + (end - start) / 1000000 ))
done
# Restore cache for warm measurement + subsequent stages.
_reset_cache
cold_avg=$(( cold_total / COMPILE_ITERS ))

warm_total=0
for (( i=0; i<COMPILE_ITERS; i++ )); do
  start=$(_time_ns)
  "$WRAPPER" noop > /dev/null 2>&1
  end=$(_time_ns)
  warm_total=$(( warm_total + (end - start) / 1000000 ))
done
warm_avg=$(( warm_total / COMPILE_ITERS ))

cold_savings=$(( cold_avg - warm_avg ))
printf "  Cold-cache invocation:  Avg: %dms   (forces compile.sh from wrapper)\n" "$cold_avg"
printf "  Warm-cache invocation:  Avg: %dms\n" "$warm_avg"
printf "  Cache-warm savings:     ~%dms\n" "$cold_savings"

# --- per-stage attribution (synthetic isolation) ----------------------------

# Each stage runs in isolation with a warmup probe. If the probe fails we
# skip the stage row with a one-line diagnostic rather than silently
# dropping it (invariant: a missing row means "this stage can't be
# measured in isolation," not "this stage is free").
SAMPLE_DIR="$BENCH_DIR/samples"
mkdir -p "$SAMPLE_DIR"

# Stage: direct script (baseline, already measured above — redo with the
# same _run_stage harness so its median is comparable)
_run_stage direct_script "$ITERATIONS" "$SAMPLE_DIR/direct.txt" -- bash "$SCRIPT"
direct_med="$(_median_ms "$SAMPLE_DIR/direct.txt")"
direct_total="$(awk '{s+=$1} END {print s+0}' "$SAMPLE_DIR/direct.txt")"

# Stage A: cache staleness check.
# Invoke `bash -c 'source cache.sh && clift_ensure_cache CLI_DIR FW_DIR'`
# — with a warm cache this exercises the sources-manifest read + mtime
# stat + checksum compare, which is exactly the router's Step 4.
_stage_a_cmd=(
  bash -c "source '${FRAMEWORK_DIR}/lib/cache.sh' && clift_ensure_cache '${CLI_DIR}' '${FRAMEWORK_DIR}'"
)
stage_a_ok=1
if ! "${_stage_a_cmd[@]}" > /dev/null 2>&1; then
  stage_a_ok=0
  echo "  (skip) stage A 'cache staleness': warmup failed" >&2
fi
if (( stage_a_ok )); then
  _run_stage cache_check "$ITERATIONS" "$SAMPLE_DIR/cache.txt" -- "${_stage_a_cmd[@]}"
  cache_med="$(_median_ms "$SAMPLE_DIR/cache.txt")"
  cache_total="$(awk '{s+=$1} END {print s+0}' "$SAMPLE_DIR/cache.txt")"
fi

# Stage B: compile (cold-cache rebuild). Must wipe .clift/ between iters
# or we measure only the "already-fresh" early-return path.
stage_b_ok=1
_wipe_cache
if ! bash "${FRAMEWORK_DIR}/lib/flags/compile.sh" "$CLI_DIR" > /dev/null 2>&1; then
  stage_b_ok=0
  echo "  (skip) stage B 'compile': warmup failed" >&2
fi
_reset_cache
if (( stage_b_ok )); then
  : > "$SAMPLE_DIR/compile.txt"
  for (( i=0; i<COMPILE_ITERS; i++ )); do
    _wipe_cache
    start=$(_time_ns)
    bash "${FRAMEWORK_DIR}/lib/flags/compile.sh" "$CLI_DIR" > /dev/null 2>&1
    end=$(_time_ns)
    echo $(( (end - start) / 1000000 )) >> "$SAMPLE_DIR/compile.txt"
  done
  _reset_cache
  compile_med="$(_median_ms "$SAMPLE_DIR/compile.txt")"
  compile_total="$(awk '{s+=$1} END {print s+0}' "$SAMPLE_DIR/compile.txt")"
fi

# Stage C: router + parse (warm cache). Invoke router.sh directly with the
# env contract it expects. Because router ends with `exec bash exec.sh`,
# this measurement INCLUDES prelude+exec+user-script. Subtract Stage D to
# isolate router+parse alone (reported in the derived row below).
_stage_c_env=(
  env
  FRAMEWORK_DIR="$FRAMEWORK_DIR"
  CLI_DIR="$CLI_DIR"
  CLI_NAME="bench"
  CLI_VERSION="0.1.0"
  CLIFT_ARG_COUNT=0
  HOME="$HOME"
  PATH="$PATH"
)
_stage_c_cmd=( "${_stage_c_env[@]}" bash "${FRAMEWORK_DIR}/lib/router/router.sh" noop )
stage_c_ok=1
if ! "${_stage_c_cmd[@]}" > /dev/null 2>&1; then
  stage_c_ok=0
  echo "  (skip) stage C 'router + parse': warmup failed" >&2
fi
if (( stage_c_ok )); then
  _run_stage router_full "$ITERATIONS" "$SAMPLE_DIR/router.txt" -- "${_stage_c_cmd[@]}"
  router_full_med="$(_median_ms "$SAMPLE_DIR/router.txt")"
  router_full_total="$(awk '{s+=$1} END {print s+0}' "$SAMPLE_DIR/router.txt")"
fi

# Stage D: prelude + exec (+ the user script itself). Invokes exec.sh
# directly. Subtracting the direct-script number isolates the prelude
# source cost.
_stage_d_env=(
  env
  FRAMEWORK_DIR="$FRAMEWORK_DIR"
  CLI_DIR="$CLI_DIR"
  HOME="$HOME"
  PATH="$PATH"
)
_stage_d_cmd=( "${_stage_d_env[@]}" bash "${FRAMEWORK_DIR}/lib/runtime/exec.sh" "$SCRIPT" )
stage_d_ok=1
if ! "${_stage_d_cmd[@]}" > /dev/null 2>&1; then
  stage_d_ok=0
  echo "  (skip) stage D 'prelude + exec': warmup failed" >&2
fi
if (( stage_d_ok )); then
  _run_stage prelude_exec "$ITERATIONS" "$SAMPLE_DIR/prelude.txt" -- "${_stage_d_cmd[@]}"
  prelude_med="$(_median_ms "$SAMPLE_DIR/prelude.txt")"
  prelude_total="$(awk '{s+=$1} END {print s+0}' "$SAMPLE_DIR/prelude.txt")"
fi

# Full wrapper — same harness for an apples-to-apples median.
_run_stage full_wrapper "$ITERATIONS" "$SAMPLE_DIR/wrapper.txt" -- "$WRAPPER" noop
full_med="$(_median_ms "$SAMPLE_DIR/wrapper.txt")"
full_total="$(awk '{s+=$1} END {print s+0}' "$SAMPLE_DIR/wrapper.txt")"

# Derived rows — router+parse alone, prelude alone. Only print if both
# underlying samples exist.
if (( stage_c_ok && stage_d_ok )); then
  router_only_med=$(( router_full_med - prelude_med ))
  (( router_only_med < 0 )) && router_only_med=0
fi
if (( stage_d_ok )); then
  prelude_only_med=$(( prelude_med - direct_med ))
  (( prelude_only_med < 0 )) && prelude_only_med=0
fi

echo ""
echo "Stage attribution (median across samples; per-stage iters in parens):"
printf "  %-24s %8s %8s\n" "stage" "median" "total"
printf "  %-24s %8s %8s\n" "------------------------" "--------" "--------"
printf "  %-24s %6dms %6dms   (n=%d)\n" "direct script"       "$direct_med"  "$direct_total"  "$ITERATIONS"
if (( stage_a_ok )); then
  printf "  %-24s %6dms %6dms   (n=%d)\n" "cache staleness"     "$cache_med"   "$cache_total"   "$ITERATIONS"
fi
if (( stage_b_ok )); then
  printf "  %-24s %6dms %6dms   (n=%d)\n" "compile (cold)"      "$compile_med" "$compile_total" "$COMPILE_ITERS"
fi
if (( stage_d_ok )); then
  printf "  %-24s %6dms %6dms   (n=%d)\n" "prelude + exec"      "$prelude_med" "$prelude_total" "$ITERATIONS"
  printf "  %-24s %6dms %8s   (derived: prelude+exec - direct)\n" "  prelude alone (derived)" "$prelude_only_med" "-"
fi
if (( stage_c_ok )); then
  printf "  %-24s %6dms %6dms   (n=%d)\n" "router + prelude+exec" "$router_full_med" "$router_full_total" "$ITERATIONS"
  if (( stage_d_ok )); then
    printf "  %-24s %6dms %8s   (derived: router_full - prelude+exec)\n" "  router+parse (derived)" "$router_only_med" "-"
  fi
fi
printf "  %-24s %6dms %6dms   (n=%d)\n" "full wrapper"        "$full_med"    "$full_total"    "$ITERATIONS"
printf "  %-24s %8s %8s\n" "------------------------" "--------" "--------"
full_overhead=$(( full_med - direct_med ))
printf "  %-24s %6dms              (full wrapper - direct script)\n" "overhead (median)" "$full_overhead"
