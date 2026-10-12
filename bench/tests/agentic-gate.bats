#!/usr/bin/env bats
# Agentic gate (ticket 06): pairing, ship rule, guardrail, seed escalation,
# fixture floor. Unit tests drive lib/stats.js; runner tests use canned cell
# files plus the stub `claude` (no network, no API).

load helpers
load helpers_agentic

setup() {
  bench_setup
  make_diet_kit
  export KIT
  make_fixtures fa fb fc
}
teardown() { bench_teardown; }

run_gate() {
  run_bench --kind agentic --fixtures-dir "$FIXTURES" --kit-dir "$KIT" --yes --run-id g "$@"
}

# JS prelude for node_assert: build(fn) makes cells for every arm, fixture and
# seed from fn(arm, fixture, seed) -> {input, pass, capped}.
GATE_JS='
  const FIX = ["fa", "fb", "fc"];
  const build = (fn, fixtures = FIX, seeds = [1, 2, 3]) => ["bare", "full", "full-diet"].flatMap(arm =>
    fixtures.flatMap(task => seeds.map(seed => {
      const d = fn(arm, task, seed);
      return { arm, task, seed, usage: { input_tokens: d.input }, hitMaxTurns: Boolean(d.capped),
        hiddenTest: { pass: d.pass !== false } };
    })));
  const jitter = (task, seed) => ((task.charCodeAt(1) * 7 + seed * 3) % 11) - 5;
  const id = c => `${c.arm}--${c.task}--s${c.seed}`;
'

@test "agentic-pairing: pairs by fixture and seed; a failed cell leaves its pair out and is listed" {
  node_assert "$GATE_JS"'
    const all = build((arm, t, s) => ({ input: (arm === "full-diet" ? 800 : 1000) + jitter(t, s) }));
    const gone = all.filter(c => !(c.arm === "full" && c.task === "fb" && c.seed === 2));
    const gate = stats.agenticGate(gone);
    assert.strictEqual(gate.pairs, 8);
    assert.deepStrictEqual(gate.unpaired.map(id), ["full-diet--fb--s2"]);
    assert.ok(report.formatAgenticGate(gate).includes("Unpaired cells excluded (1): full-diet--fb--s2"));
    // A cell file without a hidden-test result is not a completed cell either.
    const broken = all.map(c => (c.arm === "full-diet" && c.task === "fa" && c.seed === 1 ? { ...c, hiddenTest: undefined } : c));
    const g2 = stats.agenticGate(broken);
    assert.strictEqual(g2.pairs, 8);
    assert.deepStrictEqual(g2.unpaired.map(id).sort(), ["full--fa--s1", "full-diet--fa--s1"]);
  '
}

@test "agentic-pass-rate: computed over paired cells only, so both arms share a denominator" {
  node_assert "$GATE_JS"'
    // full has a failing cell whose full-diet partner is missing: it must not lower full pass rate.
    const all = build((arm, t, s) => ({ input: (arm === "full-diet" ? 800 : 1000) + jitter(t, s), pass: !(arm === "full" && s === 3 && t === "fa") }));
    const gone = all.filter(c => !(c.arm === "full-diet" && c.task === "fa" && c.seed === 3));
    const gate = stats.agenticGate(gone);
    assert.strictEqual(gate.pairs, 8);
    assert.strictEqual(gate.pass.reference, 8);
    assert.strictEqual(gate.pass.candidate, 8);
    assert.strictEqual(gate.verdict, "ship");
  '
}

@test "agentic-bare: the bare arm is reported but feeds no verdict" {
  node_assert "$GATE_JS"'
    const base = build((arm, t, s) => ({ input: (arm === "full-diet" ? 800 : 1000) + jitter(t, s) }));
    const wild = base.map(c => (c.arm === "bare" ? { ...c, usage: { input_tokens: 99999 }, hiddenTest: { pass: false } } : c));
    const a = stats.agenticGate(base);
    const b = stats.agenticGate(wild);
    assert.strictEqual(b.verdict, a.verdict);
    assert.deepStrictEqual(b.cost, a.cost);
    assert.strictEqual(b.arms[0].arm, "bare");
    assert.strictEqual(b.arms[0].cells, 9);
    assert.ok(report.formatAgenticGate(b).includes("Bare arm (reference only, feeds no verdict): 9 cells"));
  '
}

@test "agentic-capped: hitMaxTurns cells are counted and reported per arm" {
  node_assert "$GATE_JS"'
    const all = build((arm, t, s) => ({ input: (arm === "full-diet" ? 800 : 1000) + jitter(t, s), capped: (arm === "full" && s === 1) || (arm === "full-diet" && t === "fa" && s === 1) }));
    const gate = stats.agenticGate(all);
    assert.deepStrictEqual(gate.arms.map(a => [a.arm, a.capped, a.cells]), [["bare", 0, 9], ["full", 3, 9], ["full-diet", 1, 9]]);
    assert.ok(report.formatAgenticGate(gate).includes("Turn-capped cells (hitMaxTurns): bare 0/9, full 3/9, full-diet 1/9"));
  '
}

@test "agentic-floor: fewer than 3 paired fixtures is inconclusive even with a big effect" {
  node_assert "$GATE_JS"'
    const two = build((arm, t, s) => ({ input: (arm === "full-diet" ? 500 : 1000) + jitter(t, s) }), ["fa", "fb"]);
    const gate = stats.agenticGate(two);
    assert.strictEqual(gate.verdict, "inconclusive");
    assert.strictEqual(gate.escalate, false);
    assert.ok(report.formatAgenticGate(gate).includes("counts as no-ship"));
    // Three fixtures offered, but one loses all its full-diet cells: only 2 remain paired.
    const dropped = build((arm, t, s) => ({ input: (arm === "full-diet" ? 500 : 1000) + jitter(t, s) }))
      .filter(c => !(c.arm === "full-diet" && c.task === "fc"));
    const g2 = stats.agenticGate(dropped);
    assert.strictEqual(g2.verdict, "inconclusive");
    assert.deepStrictEqual(g2.fixtures, ["fa", "fb"]);
    assert.strictEqual(stats.agenticGate(dropped, { minFixtures: 2 }).verdict, "ship");
  '
}

@test "agentic-floor: the runner stops with inconclusive before any paid call when fewer than 3 fixtures remain" {
  rm -rf "$FIXTURES/fc"

  run run_gate

  [ "$status" -eq 1 ]
  [ "$(stub_calls)" -eq 0 ]
  [[ "$output" == *"Verdict: inconclusive (2 fixture(s) usable after drops, need 3)"* ]] || false
  [[ "$output" != *"Estimated cost"* ]] || false
}

@test "agentic-ship: known cost reduction with equal pass rate yields ship; no escalation" {
  write_agentic_cells g "$(printf '{"fixtures":["fa","fb","fc"],"seeds":[1,2,3],"arms":%s}' "$(canned_arms 1500 1000 800 true true)")"

  run run_gate

  [ "$status" -eq 0 ]
  [ "$(stub_calls)" -eq 0 ]
  [[ "$output" == *"Verdict: ship"* ]] || false
  [[ "$output" != *"escalating"* ]] || false
  [ "$(find "$RESULTS/g" -name '*--s4.json' | wc -l | tr -d ' ')" -eq 0 ]
  note="$(ls "$RESEARCH"/*-bench-g.md)"
  grep -q 'Verdict: ship' "$note"
  grep -q 'Diagnostics per arm' "$note"
  grep -q 'Turn-capped cells' "$note"
}

@test "agentic-guardrail: lower pass rate yields no-ship despite cost reduction, without escalation" {
  write_agentic_cells g "$(printf '{"fixtures":["fa","fb","fc"],"seeds":[1,2,3],"arms":%s}' "$(canned_arms 1500 1000 800 true false)")"

  run run_gate

  [ "$status" -eq 0 ]
  [ "$(stub_calls)" -eq 0 ]
  [[ "$output" == *"Verdict: no-ship (hidden-test pass rate is lower than full)"* ]] || false
  [[ "$output" != *"escalating"* ]] || false
}

@test "agentic-bad-direction: cost CI excluding zero in the bad direction is no-ship with no escalation" {
  write_agentic_cells g "$(printf '{"fixtures":["fa","fb","fc"],"seeds":[1,2,3],"arms":%s}' "$(canned_arms 1500 1000 1200 true true)")"

  run run_gate

  [ "$status" -eq 0 ]
  [ "$(stub_calls)" -eq 0 ]
  [[ "$output" == *"Verdict: no-ship (cost interval excludes zero in the bad direction)"* ]] || false
  [ "$(find "$RESULTS/g" -name '*--s[4-6].json' | wc -l | tr -d ' ')" -eq 0 ]
}

@test "agentic-escalation: no effect at 3 seeds runs seeds 4-6 only, then no-ship; escalates once; rerun is free" {
  write_agentic_cells g "$(printf '{"fixtures":["fa","fb","fc"],"seeds":[1,2,3],"arms":%s}' "$(canned_arms 1500 1000 1000 true true)")"
  export STUB_FLAT=1

  run run_gate

  [ "$status" -eq 0 ]
  [[ "$output" == *"escalating to seeds 4-6"* ]] || false
  # 3 arms x 3 fixtures x seeds 4..6 = 27 new calls; seeds 1-3 are skipped.
  [ "$(stub_calls)" -eq 27 ]
  [ "$(find "$RESULTS/g" -name '*--s[4-6].json' | wc -l | tr -d ' ')" -eq 27 ]
  [ "$(find "$RESULTS/g" -name '*--s7.json' | wc -l | tr -d ' ')" -eq 0 ]
  [[ "$output" == *"Verdict: no-ship (cost interval includes zero after escalation)"* ]] || false
  grep -q 'escalated to 6' "$RESEARCH"/*-bench-g.md

  run run_gate
  [ "$status" -eq 0 ]
  [ "$(stub_calls)" -eq 27 ]
  [[ "$output" == *"Verdict: no-ship (cost interval includes zero after escalation)"* ]] || false
}

@test "agentic-escalation: an effect that only the extra seeds show ships after escalation" {
  write_agentic_cells g "$(printf '{"fixtures":["fa","fb","fc"],"seeds":[1,2,3],"arms":%s}' "$(canned_arms 1500 1000 1000 true true)")"
  # Seeds 1-3 are canned without effect; the stub's full-diet reads less cache
  # on seeds 4-6, so only the pooled 6 seeds exclude zero.

  run run_gate

  [ "$status" -eq 0 ]
  [ "$(stub_calls)" -eq 27 ]
  [[ "$output" == *"escalating to seeds 4-6"* ]] || false
  [[ "$output" == *"Verdict: ship"* ]] || false
}

@test "agentic-unpaired: a failed cell is excluded from the interval and listed in the report" {
  write_agentic_cells g "$(printf '{"fixtures":["fa","fb","fc"],"seeds":[1,2,3],"arms":%s}' "$(canned_arms 1500 1000 800 true true)")"
  rm "$RESULTS/g/full--fb--s2.json"
  export STUB_FAIL_ARM=full

  run run_gate

  [ "$status" -eq 1 ]
  [ "$(stub_calls)" -eq 1 ]
  [[ "$output" == *"Pairs: 8 across 3 fixture(s)"* ]] || false
  [[ "$output" == *"Unpaired cells excluded (1): full-diet--fb--s2"* ]] || false
}

@test "agentic-no-escalate: --no-escalate makes a zero-including interval no-ship at once" {
  write_agentic_cells g "$(printf '{"fixtures":["fa","fb","fc"],"seeds":[1,2,3],"arms":%s}' "$(canned_arms 1500 1000 1000 true true)")"

  run run_gate --no-escalate

  [ "$status" -eq 0 ]
  [ "$(stub_calls)" -eq 0 ]
  [[ "$output" == *"Verdict: no-ship (cost interval includes zero (escalation disabled))"* ]] || false
}
