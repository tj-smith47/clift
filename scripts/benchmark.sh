#!/usr/bin/env bash
# Benchmark clift overhead: measures the time from CLI invocation to script
# execution, comparing a clift-dispatched command vs. running the script directly.
#
# Usage: scripts/benchmark.sh [iterations]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRAMEWORK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ITERATIONS="${1:-20}"

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

WRAPPER="$BENCH_DIR/bench/bin/bench"
SCRIPT="$BENCH_DIR/bench/cmds/noop/noop.sh"

# Warmup
"$WRAPPER" noop > /dev/null 2>&1
bash "$SCRIPT" > /dev/null 2>&1

# Benchmark: direct script
echo ""
echo "Direct script execution:"
start=$(date +%s%N)
for (( i=0; i<ITERATIONS; i++ )); do
  bash "$SCRIPT" > /dev/null 2>&1
done
end=$(date +%s%N)
direct_ms=$(( (end - start) / 1000000 ))
direct_avg=$(( direct_ms / ITERATIONS ))
echo "  Total: ${direct_ms}ms  Avg: ${direct_avg}ms"

# Benchmark: clift wrapper (standard mode, warm cache)
echo ""
echo "clift standard mode (warm cache):"
start=$(date +%s%N)
for (( i=0; i<ITERATIONS; i++ )); do
  "$WRAPPER" noop > /dev/null 2>&1
done
end=$(date +%s%N)
clift_ms=$(( (end - start) / 1000000 ))
clift_avg=$(( clift_ms / ITERATIONS ))
echo "  Total: ${clift_ms}ms  Avg: ${clift_avg}ms"

overhead=$(( clift_avg - direct_avg ))
echo ""
echo "Overhead: ~${overhead}ms per invocation"
echo "  (wrapper → cache check → task → router → parser → script)"
