#!/usr/bin/env bats
# Stats module, single-turn gate verdicts and the report (ticket 04). Unit
# tests drive lib/stats.js directly; end-to-end tests run the real runner on
# canned cell files, so every cell exists and the stub is never called.

load helpers

setup() { bench_setup; }
teardown() { bench_teardown; }

# Canned spec: arms with given mean output/input tokens and per-cell noise.
canned_spec() {
  # $1..$5: output for bare, bare-control, lite, full, ultra; $6..$10: input.
  # ultra-no-focus copies ultra ($5, $10), so its pair has no effect.
  printf '{"seeds":3,"arms":{"bare":{"output":%s,"input":%s,"noise":20},"bare-control":{"output":%s,"input":%s,"noise":20},"lite":{"output":%s,"input":%s,"noise":20},"full":{"output":%s,"input":%s,"noise":20},"ultra":{"output":%s,"input":%s,"noise":20},"ultra-no-focus":{"output":%s,"input":%s,"noise":20}}}' \
    "$1" "$6" "$2" "$7" "$3" "$8" "$4" "$9" "$5" "${10}" "$5" "${10}"
}

# Verdict column of the gate row for <candidate> <reference>.
verdict_of() {
  echo "$output" | awk -v c="$1" -v r="$2" '$1 == c && $2 == r { print $NF }'
}

@test "stats: cacheWeightedCost = input + 0.1 x cache read + 1.25 x cache write" {
  node_assert '
    assert.strictEqual(stats.cacheWeightedCost({ input_tokens: 100, cache_read_input_tokens: 1000, cache_creation_input_tokens: 200 }), 450);
    assert.strictEqual(stats.cacheWeightedCost({ input_tokens: 7 }), 7);
    assert.strictEqual(stats.cacheWeightedCost(undefined), 0);
  '
}

@test "stats: pairCells pairs by task and seed and lists unpaired cells from both sides" {
  node_assert '
    const c = (arm, task, seed) => ({ arm, task, seed });
    const { pairs, unpaired } = stats.pairCells(
      [c("ultra", "a", 1), c("ultra", "a", 2), c("ultra", "b", 1), c("ultra", "a", 1)],
      [c("bare", "a", 1), c("bare", "b", 1), c("bare", "b", 2)]);
    assert.deepStrictEqual(pairs.map(p => [p.key, p.candidate.arm, p.reference.arm]),
      [["a--s1", "ultra", "bare"], ["b--s1", "ultra", "bare"]]);
    assert.deepStrictEqual(unpaired.map(u => `${u.arm}/${u.task}/${u.seed}`).sort(),
      ["bare/b/2", "ultra/a/1", "ultra/a/2"]);
    const byTask = stats.pairCells([c("x", "a", 1)], [c("y", "a", 9)], cell => cell.task);
    assert.strictEqual(byTask.pairs.length, 1);
    assert.strictEqual(byTask.unpaired.length, 0);
  '
}

@test "stats: confidenceInterval is the 95% t-interval of the mean" {
  node_assert '
    const ci = stats.confidenceInterval([1, 2, 3, 4, 5]);
    assert.strictEqual(ci.n, 5);
    assert.strictEqual(ci.mean, 3);
    // sd 1.5811, se 0.7071, t(4) 2.776
    assert.ok(Math.abs(ci.lo - 1.0371) < 1e-3, String(ci.lo));
    assert.ok(Math.abs(ci.hi - 4.9629) < 1e-3, String(ci.hi));
    const flat = stats.confidenceInterval([-5, -5, -5]);
    assert.deepStrictEqual([flat.lo, flat.hi], [-5, -5]);
    const one = stats.confidenceInterval([3]);
    assert.deepStrictEqual([one.lo, one.hi], [-Infinity, Infinity]);
    assert.ok(Math.abs(stats.tCritical95(17) - 2.110) < 1e-9);
    assert.ok(Math.abs(stats.tCritical95(40) - 2.021) < 1e-3, String(stats.tCritical95(40)));
    assert.ok(Math.abs(stats.tCritical95(120) - 1.980) < 1e-3, String(stats.tCritical95(120)));
  '
}

@test "verdict: ship needs one good interval and no bad one; else no-ship" {
  node_assert '
    const good = { lo: -9, hi: -1 }, zero = { lo: -1, hi: 1 }, bad = { lo: 1, hi: 9 };
    const v = stats.singleTurnVerdict;
    assert.strictEqual(v(good, zero), "ship");
    assert.strictEqual(v(zero, good), "ship");
    assert.strictEqual(v(good, good), "ship");
    assert.strictEqual(v(zero, zero), "no-ship");
    assert.strictEqual(v(good, bad), "no-ship");
    assert.strictEqual(v(bad, good), "no-ship");
    assert.strictEqual(v(bad, zero), "no-ship");
  '
}

@test "gate: ultra-no-focus is judged against ultra only when its cells exist; unpaired cells are listed" {
  node_assert '
    const tasks = ["a", "b", "c", "d"];
    const mk = (arm, out, missing = []) => tasks.flatMap((task, i) => [1, 2].map(seed => ({
      arm, task, seed, usage: { input_tokens: 1000, output_tokens: out + 10 * i + seed + (arm.length % 3) * (seed === 1 ? 1 : -1) },
    }))).filter(c => !missing.includes(`${c.task}${c.seed}`));
    const base = [...mk("bare", 500, ["b2"]), ...mk("bare-control", 500), ...mk("ultra", 300)];
    let gate = stats.singleTurnGate(base);
    assert.deepStrictEqual(gate.candidates.map(c => c.candidate), ["ultra"]);
    assert.strictEqual(gate.candidates[0].pairs, 7);
    gate = stats.singleTurnGate([...base, ...mk("ultra-no-focus", 400)]);
    const nf = gate.candidates.find(c => c.candidate === "ultra-no-focus");
    assert.strictEqual(nf.reference, "ultra");
    assert.strictEqual(nf.pairs, 8);
    assert.strictEqual(nf.verdict, "no-ship");
    assert.ok(nf.metrics.output.ci.lo > 0, "output regression vs ultra");
    const text = report.formatGate(gate);
    assert.ok(text.includes("Unpaired cells excluded (2): bare-control--b--s2, ultra--b--s2"), text);
  '
}

@test "gate-ship: canned data with a known cost and output reduction yields ship" {
  write_canned_cells canned "$(canned_spec 500 500 450 400 300  1000 1000 900 800 600)"

  run run_bench --kind single-turn --run-id canned

  [ "$status" -eq 0 ]
  [ "$(stub_calls)" -eq 0 ]
  [ "$(verdict_of lite bare)" = ship ]
  [ "$(verdict_of full bare)" = ship ]
  [ "$(verdict_of ultra bare)" = ship ]
  [ "$(verdict_of bare bare-control)" = baseline ]
  [[ "$output" == *"cost_ci95"*"out_ci95"*"verdict"* ]]
  echo "$output" | grep -E '^ultra +bare +18 +'
}

@test "gate-ship: a cost reduction alone ships when output does not regress" {
  write_canned_cells canned "$(canned_spec 500 500 500 500 500  1000 1000 900 900 900)"

  run run_bench --kind single-turn --run-id canned

  [ "$status" -eq 0 ]
  [ "$(verdict_of ultra bare)" = ship ]
}

@test "gate-no-ship: canned data with no effect yields no-ship for every candidate" {
  write_canned_cells canned "$(canned_spec 500 500 500 500 500  1000 1000 1000 1000 1000)"

  run run_bench --kind single-turn --run-id canned

  [ "$status" -eq 0 ]
  [ "$(verdict_of bare bare-control)" = baseline ]
  [ "$(verdict_of lite bare)" = no-ship ]
  [ "$(verdict_of full bare)" = no-ship ]
  [ "$(verdict_of ultra bare)" = no-ship ]
}

@test "gate-no-ship: an output-token regression yields no-ship despite lower cost" {
  write_canned_cells canned "$(canned_spec 500 500 450 400 700  1000 1000 900 800 600)"

  run run_bench --kind single-turn --run-id canned

  [ "$status" -eq 0 ]
  [ "$(verdict_of lite bare)" = ship ]
  [ "$(verdict_of ultra bare)" = no-ship ]
}

@test "gate-inconclusive: bare vs bare-control excluding zero makes every verdict inconclusive" {
  write_canned_cells canned "$(canned_spec 500 440 450 400 300  1000 1000 900 800 600)"

  run run_bench --kind single-turn --run-id canned

  [ "$status" -eq 0 ]
  [ "$(verdict_of bare bare-control)" = NOISY ]
  [ "$(verdict_of lite bare)" = inconclusive ]
  [ "$(verdict_of full bare)" = inconclusive ]
  [ "$(verdict_of ultra bare)" = inconclusive ]
  [[ "$output" == *"every verdict is inconclusive"* ]]
}

@test "gate-inconclusive: noise on input cost alone also makes every verdict inconclusive" {
  write_canned_cells canned "$(canned_spec 500 500 450 400 300  1000 1100 900 800 600)"

  run run_bench --kind single-turn --run-id canned

  [ "$status" -eq 0 ]
  [ "$(verdict_of bare bare-control)" = NOISY ]
  [ "$(verdict_of ultra bare)" = inconclusive ]
}

@test "no-escalation: a single-turn run never requests more than --seeds seeds" {
  export STUB_FLAT=1
  run run_bench --kind single-turn --seeds 2 --yes --run-id flat

  [ "$status" -eq 0 ]
  # 6 arms x 6 tasks x 2 seeds; every interval includes zero, still no rerun.
  [ "$(stub_calls)" -eq 72 ]
  [ "$(verdict_of ultra bare)" = no-ship ]
  [ "$(find "$RESULTS/flat" -name '*.json' | wc -l | tr -d ' ')" -eq 72 ]
  [ "$(find "$RESULTS/flat" -name '*--s3.json' | wc -l | tr -d ' ')" -eq 0 ]

  run run_bench --kind single-turn --seeds 2 --yes --run-id flat
  [ "$status" -eq 0 ]
  [ "$(stub_calls)" -eq 72 ]
}

@test "summary-note: a complete run writes a dated note under the research dir with run parameters" {
  write_canned_cells canned "$(canned_spec 500 500 450 400 300  1000 1000 900 800 600)"

  run run_bench --kind single-turn --run-id canned --model claude-opus-5-5

  [ "$status" -eq 0 ]
  note="$(find "$RESEARCH" -name '*-bench-canned.md')"
  [ -n "$note" ]
  [[ "$(basename "$note")" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-bench-canned\.md$ ]]
  [[ "$output" == *"Summary note: $note"* ]]
  grep -F -- '- Model: claude-opus-5-5' "$note"
  grep -F -- '- Seeds: 3' "$note"
  grep -F -- "- Kit-dir commit: $(git -C "$KIT_DIR" rev-parse HEAD)" "$note"
  grep -F -- "- Raw cells: $RESULTS/canned" "$note"
  grep -E '^\| ultra \| bare \| 18 \| .* \| \*\*ship\*\* \|$' "$note"
  grep -E '^\| bare \| bare-control \| 18 \| .* \| baseline \|$' "$note"
  grep -F 'Unpaired cells excluded: none' "$note"
}

@test "summary-note: an incomplete run skips the note and lists unpaired cells" {
  write_canned_cells partial "$(canned_spec 500 500 450 400 300  1000 1000 900 800 600)"
  rm "$RESULTS/partial/lite--explain-race--s2.json"
  export STUB_FAIL_ARM=lite
  run run_bench --kind single-turn --yes --run-id partial

  [ "$status" -ne 0 ]
  [ "$(stub_calls)" -eq 1 ]
  [[ "$output" == *"Summary note skipped: 107/108 cells complete"* ]]
  [[ "$output" == *"Unpaired cells excluded (1): bare--explain-race--s2"* ]]
  echo "$output" | grep -E '^lite +bare +17 +'
  [ ! -d "$RESEARCH" ]
}
