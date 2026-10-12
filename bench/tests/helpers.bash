# Shared setup for bench/tests/*.bats. Every test runs the real bench runner
# (or its modules) with the stub `claude` first on PATH, a temp HOME holding a
# fake real config dir, and a private TMPDIR so leftover temp dirs are visible.

bench_setup() {
  export KIT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
  export BENCH_DIR="$KIT_DIR/bench"
  TEST_ROOT="$(mktemp -d)"
  export TEST_ROOT
  export HOME="$TEST_ROOT/home"
  export TMPDIR="$TEST_ROOT/tmp"
  export RESULTS="$TEST_ROOT/results"
  export STUB_LOG="$TEST_ROOT/stub/log.jsonl"
  mkdir -p "$HOME/.claude/skills/caveman" "$TMPDIR" "$TEST_ROOT/stub"

  # The user's real config dir: a skill, a CLAUDE.md and settings that must
  # never reach an arm.
  cat > "$HOME/.claude/skills/caveman/SKILL.md" <<'SKILL'
---
name: caveman
disable-model-invocation: true
---

Respond terse like smart caveman.

## Intensity

| Level | What change |
|-------|------------|
| **lite** | No filler/hedging |
| **full** | Drop articles |
| **ultra** | Strip conjunctions |
SKILL
  echo "REAL USER CLAUDE.md" > "$HOME/.claude/CLAUDE.md"
  echo '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"echo real-user-hook"}]}]}}' > "$HOME/.claude/settings.json"

  export PATH="$BENCH_DIR/tests/stub:$PATH"
  export ANTHROPIC_API_KEY="test-key"
  unset CLAUDE_CONFIG_DIR CLAUDE_PLUGIN_ROOT CAVEMAN_DEFAULT_MODE CAVEMAN_CONTEXT_DIET CAVEMAN_BENCH_SKILL_ROOT
  unset STUB_FAIL STUB_FAIL_ARM STUB_SLEEP STUB_MARK
}

bench_teardown() {
  rm -rf "$TEST_ROOT"
}

# Runs the real runner; stdin is never a TTY.
run_bench() {
  node "$BENCH_DIR/run.js" --results-dir "$RESULTS" "$@" < /dev/null
}

stub_calls() {
  if [ -f "$STUB_LOG" ]; then wc -l < "$STUB_LOG" | tr -d ' '; else echo 0; fi
}

# Leftover bench temp roots under TMPDIR.
leftover_temp_dirs() {
  find "$TMPDIR" -maxdepth 1 -name 'caveman-bench-*' | wc -l | tr -d ' '
}

# Evaluates JS with `entries` = parsed stub log lines; a throw fails the test.
log_assert() {
  STUB_LOG="$STUB_LOG" node -e '
    const fs = require("fs");
    const assert = require("assert");
    const entries = fs.readFileSync(process.env.STUB_LOG, "utf8").trim().split("\n").map(l => JSON.parse(l));
    '"$1"'
  '
}

# Evaluates JS with the bench modules loaded as `isolation`, `cells`.
node_assert() {
  node -e '
    const fs = require("fs");
    const path = require("path");
    const assert = require("assert");
    const isolation = require(process.env.BENCH_DIR + "/lib/isolation");
    const cells = require(process.env.BENCH_DIR + "/lib/cells");
    '"$1"'
  '
}
