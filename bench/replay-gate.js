#!/usr/bin/env node
// caveman-kit bench — offline replay of the hidden-test guardrail (issue #18,
// ADR 0016). Reads committed cells under bench/results/, re-judges every
// full-diet/full pairing under the old strict rule (any fewer passes is a
// regression) and the margin rule (stats.passGuardrail), and prints how
// often the two disagree. No API calls. Usage:
//
//   node bench/replay-gate.js [--results <dir>] [--subset <k>]
//
// --subset k (default 3) also replays every k-seed subset of each run, the
// seed count a first pass sees before escalation. The exact table that
// follows the replay needs no cells: it is the false-alarm and power rate of
// both rules for independent per-arm pass counts at the replayed pair sizes.
'use strict';

const fs = require('fs');
const path = require('path');
const stats = require('./lib/stats');

const args = process.argv.slice(2);
const flag = (name, fallback) => {
  const i = args.indexOf(name);
  return i === -1 ? fallback : args[i + 1];
};
const usage = 'Usage: node bench/replay-gate.js [--results <dir>] [--subset <k>]';
if (args.includes('--help') || args.includes('-h')) {
  console.log(usage);
  process.exit(0);
}
const resultsArg = flag('--results', path.join(__dirname, 'results'));
const subsetSize = Number(flag('--subset', 3));
if (typeof resultsArg !== 'string' || !Number.isInteger(subsetSize) || subsetSize < 1) {
  console.error(`${usage}\n--results needs a directory and --subset a positive integer`);
  process.exit(2);
}
const resultsDir = path.resolve(resultsArg);

function loadRun(dir) {
  return fs.readdirSync(dir).filter(f => f.endsWith('.json')).map(f => JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8')));
}

// Pairs the completed full-diet and full cells of one run.
function pairRun(cells) {
  const usable = arm => cells.filter(c => c.arm === arm && stats.isCompleted(c));
  return stats.pairCells(usable(stats.AGENTIC_PAIR.candidate), usable(stats.AGENTIC_PAIR.reference)).pairs;
}

function judge(pairs) {
  const cand = pairs.map(p => p.candidate.hiddenTest.pass);
  const ref = pairs.map(p => p.reference.hiddenTest.pass);
  const g = stats.passGuardrail(cand, ref);
  return { strict: g.candidate < g.reference, margin: g.lower, g };
}

function combinations(items, k) {
  if (k === 0) return [[]];
  if (items.length < k) return [];
  const [head, ...rest] = items;
  return [...combinations(rest, k - 1).map(c => [head, ...c]), ...combinations(rest, k)];
}

// Replay one run: the full pairing, then every k-seed subset.
function replayRun(runId, pairs) {
  const seeds = [...new Set(pairs.map(p => p.candidate.seed))].sort((a, b) => a - b);
  const full = judge(pairs);
  const subsets = combinations(seeds, Math.min(subsetSize, seeds.length)).map(sub => judge(pairs.filter(p => sub.includes(p.candidate.seed))));
  const count = (list, key) => list.filter(j => j[key]).length;
  return {
    runId,
    pairs: pairs.length,
    fixtures: [...new Set(pairs.map(p => p.candidate.task))].sort(),
    seeds,
    full,
    subsets: subsets.length,
    strictFires: count(subsets, 'strict'),
    marginFires: count(subsets, 'margin'),
    flips: subsets.filter(j => j.strict !== j.margin).length,
  };
}

// ---- Exact rates for independent per-arm pass counts -----------------------
// Both arms pass each paired cell independently: candidate Bin(n, pc),
// reference Bin(n, pr). D = reference passes - candidate passes. The strict
// rule fires when D >= 1, the margin rule when D > ceil(0.1 n). With pc = pr
// a fire is a false alarm; with pc < pr it is power. Independence ignores any
// within-pair correlation, so the false-alarm rates are upper bounds.
function binomial(n, p) {
  const pmf = new Array(n + 1).fill(0);
  let c = 1;
  for (let k = 0; k <= n; k++) {
    pmf[k] = c * p ** k * (1 - p) ** (n - k);
    c = (c * (n - k)) / (k + 1);
  }
  return pmf;
}

function fireRates(n, pc, pr) {
  const cand = binomial(n, pc);
  const ref = binomial(n, pr);
  const margin = stats.passMargin(n);
  let strict = 0;
  let within = 0;
  for (let r = 0; r <= n; r++) {
    for (let c = 0; c <= n; c++) {
      const d = r - c;
      const pr_ = ref[r] * cand[c];
      if (d >= 1) strict += pr_;
      if (d > margin) within += pr_;
    }
  }
  return { n, margin, strict, margin_: within };
}

const pct = x => `${(x * 100).toFixed(1)}%`;

function main() {
  const runs = fs.readdirSync(resultsDir).filter(d => d.startsWith('agentic-')).sort();
  const replays = [];
  for (const runId of runs) {
    const pairs = pairRun(loadRun(path.join(resultsDir, runId)));
    if (pairs.length === 0) continue;
    replays.push(replayRun(runId, pairs));
  }
  console.log(`Replay of committed cells under ${resultsDir}`);
  console.log(`Rules: strict = full-diet passes < full passes; margin = net drop > ceil(10% of pairs) (stats.passGuardrail)`);
  console.log('');
  for (const r of replays) {
    const g = r.full.g;
    console.log(`${r.runId}: ${r.pairs} pairs over ${r.fixtures.join(', ')} (seeds ${r.seeds.join(',')})`);
    console.log(`  all seeds: full-diet ${g.candidate}/${r.pairs}, full ${g.reference}/${r.pairs}, net drop ${g.net}, margin ${g.margin}; `
      + `strict ${r.full.strict ? 'FIRES' : 'quiet'}, margin ${r.full.margin ? 'FIRES' : 'quiet'}`);
    console.log(`  ${r.subsets} ${subsetSize}-seed subsets: strict fires ${r.strictFires}, margin fires ${r.marginFires}, verdict flips ${r.flips}`);
  }
  const totalSubsets = replays.reduce((a, r) => a + r.subsets, 0);
  const totalFlips = replays.reduce((a, r) => a + r.flips, 0);
  console.log('');
  console.log(`Total: ${replays.length} run(s), ${totalSubsets} subset(s), ${totalFlips} flip(s)`);

  const sizes = [...new Set(replays.flatMap(r => [r.pairs, Math.round((r.pairs * Math.min(subsetSize, r.seeds.length)) / r.seeds.length)]))].sort((a, b) => a - b);
  console.log('');
  console.log('Exact rates for independent per-arm pass counts at the replayed pair sizes (upper bounds, see source):');
  console.log('n    margin  p(both)  strict-FA  margin-FA  | p(full)  p(diet)  strict-power  margin-power');
  for (const n of sizes) {
    for (const p of [0.95, 0.8, 0.65, 0.5]) {
      const fa = fireRates(n, p, p);
      const pw = fireRates(n, Math.max(0, p - 0.25), p);
      console.log(`${String(n).padEnd(4)} ${String(fa.margin).padEnd(7)} ${p.toFixed(2).padEnd(8)} ${pct(fa.strict).padEnd(10)} ${pct(fa.margin_).padEnd(10)} | `
        + `${p.toFixed(2).padEnd(8)} ${Math.max(0, p - 0.25).toFixed(2).padEnd(8)} ${pct(pw.strict).padEnd(13)} ${pct(pw.margin_)}`);
    }
  }
}

main();
