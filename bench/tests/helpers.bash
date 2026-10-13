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
  export RESEARCH="$TEST_ROOT/research"
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
  unset STUB_FAIL STUB_FAIL_ARM STUB_SLEEP STUB_MARK STUB_FLAT STUB_IGNORE_TERM
}

bench_teardown() {
  rm -rf "$TEST_ROOT"
}

# Runs the real runner; stdin is never a TTY.
run_bench() {
  node "$BENCH_DIR/run.js" --results-dir "$RESULTS" --research-dir "$RESEARCH" "$@" < /dev/null
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

# Writes canned cell files for every single-turn task under $RESULTS/<run-id>.
# $2 is JSON: {"seeds": n, "arms": {"<arm>": {"output": o, "input": i, "noise": k}}}.
# $3 is the cells' model (default: the runner's default model); the runner
# reruns cells whose model differs from its --model.
# Per cell: output_tokens = o + shared(task, seed) + k * e1, input_tokens =
# i + shared(task, seed) + k * e2, with e1, e2 deterministic in [-1, 1] per
# (arm, task, seed); shared() is the same for every arm, so pairs cancel it.
write_canned_cells() {
  RUN_ID="$1" SPEC="$2" MODEL="${3:-}" node -e '
    const path = require("path");
    const cells = require(process.env.BENCH_DIR + "/lib/cells");
    const tasks = require(process.env.BENCH_DIR + "/tasks/single-turn");
    const spec = JSON.parse(process.env.SPEC);
    const runDir = path.join(process.env.RESULTS, process.env.RUN_ID);
    const rand = key => {
      let h = 2166136261;
      for (const ch of key) h = Math.imul(h ^ ch.charCodeAt(0), 16777619) >>> 0;
      return (h % 2001) / 1000 - 1;
    };
    for (const [arm, a] of Object.entries(spec.arms)) {
      tasks.forEach((t, ti) => {
        for (let seed = 1; seed <= spec.seeds; seed++) {
          const shared = 40 * ti + 15 * seed;
          const k = a.noise || 0;
          cells.writeJsonAtomic(cells.cellPath(runDir, { arm, task: t.id, seed }), {
            runId: process.env.RUN_ID, kind: "single-turn", model: process.env.MODEL || cells.DEFAULT_MODEL, arm, task: t.id, seed, totalCostUsd: 0.01,
            usage: {
              output_tokens: Math.round(a.output + shared + k * rand(`o|${arm}|${t.id}|${seed}`)),
              input_tokens: Math.round(a.input + shared + k * rand(`i|${arm}|${t.id}|${seed}`)),
              cache_read_input_tokens: 2000,
              cache_creation_input_tokens: 1000,
            },
          });
        }
      });
    }
  '
}

# Evaluates JS with the bench modules loaded as `isolation`, `cells`,
# `stats`, `report`.
node_assert() {
  node -e '
    const fs = require("fs");
    const path = require("path");
    const assert = require("assert");
    const isolation = require(process.env.BENCH_DIR + "/lib/isolation");
    const cells = require(process.env.BENCH_DIR + "/lib/cells");
    const stats = require(process.env.BENCH_DIR + "/lib/stats");
    const report = require(process.env.BENCH_DIR + "/lib/report");
    '"$1"'
  '
}
