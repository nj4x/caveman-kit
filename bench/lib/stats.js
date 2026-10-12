// caveman-kit bench — statistics and the single-turn ship gate (ADR 0008
// decisions 7 and 8; spec #1 "Gate"). Pure functions, no I/O: the agentic
// gate (ticket 06) reuses cacheWeightedCost, pairCells and confidenceInterval.
'use strict';

// Cache-weighted input cost of one cell, in input-token units:
// base input + 0.1 x cache read + 1.25 x cache write (CLI JSON usage keys).
function cacheWeightedCost(usage) {
  const u = usage || {};
  const n = key => Number(u[key]) || 0;
  return n('input_tokens') + 0.1 * n('cache_read_input_tokens') + 1.25 * n('cache_creation_input_tokens');
}

function outputTokens(usage) {
  return Number((usage || {}).output_tokens) || 0;
}

// Pairs candidate and reference cells by keyFn (default: task + seed).
// Returns {pairs: [{key, candidate, reference}], unpaired: [cell]}; a cell
// whose key has no partner on the other side, or repeats a key already seen
// on its own side, is unpaired. Pairs keep the candidate cells' order.
function pairCells(candidateCells, referenceCells, keyFn = c => `${c.task}--s${c.seed}`) {
  const unpaired = [];
  const index = cellList => {
    const byKey = new Map();
    for (const cell of cellList) {
      const key = keyFn(cell);
      if (byKey.has(key)) unpaired.push(cell);
      else byKey.set(key, cell);
    }
    return byKey;
  };
  const cand = index(candidateCells);
  const ref = index(referenceCells);
  const pairs = [];
  for (const [key, candidate] of cand) {
    if (ref.has(key)) pairs.push({ key, candidate, reference: ref.get(key) });
    else unpaired.push(candidate);
  }
  for (const [key, reference] of ref) if (!cand.has(key)) unpaired.push(reference);
  return { pairs, unpaired };
}

// Two-sided 95% Student t critical values, df 1..30.
const T95 = [
  12.706, 4.303, 3.182, 2.776, 2.571, 2.447, 2.365, 2.306, 2.262, 2.228,
  2.201, 2.179, 2.160, 2.145, 2.131, 2.120, 2.110, 2.101, 2.093, 2.086,
  2.080, 2.074, 2.069, 2.064, 2.060, 2.056, 2.052, 2.048, 2.045, 2.042,
];

// Above df 30: Cornish-Fisher expansion around z = 1.959964 (error < 1e-3).
function tCritical95(df) {
  if (df <= 30) return T95[df - 1];
  const z = 1.959964;
  return z + (z ** 3 + z) / (4 * df) + (5 * z ** 5 + 16 * z ** 3 + 3 * z) / (96 * df ** 2);
}

// 95% t-interval of the mean of diffs. Fewer than 2 values give infinite
// bounds: no interval, so it includes zero.
function confidenceInterval(diffs) {
  const n = diffs.length;
  if (n === 0) return { n, mean: NaN, lo: -Infinity, hi: Infinity };
  const mean = diffs.reduce((a, b) => a + b, 0) / n;
  if (n < 2) return { n, mean, lo: -Infinity, hi: Infinity };
  const variance = diffs.reduce((a, d) => a + (d - mean) ** 2, 0) / (n - 1);
  const half = tCritical95(n - 1) * Math.sqrt(variance / n);
  return { n, mean, lo: mean - half, hi: mean + half };
}

// Direction of an interval for a lower-is-better metric (candidate minus
// reference): 'good' when it excludes zero below, 'bad' above, else 'zero'.
function direction(ci) {
  if (ci.hi < 0) return 'good';
  if (ci.lo > 0) return 'bad';
  return 'zero';
}

const METRICS = [
  { key: 'cost', label: 'cache-weighted input', value: cacheWeightedCost },
  { key: 'output', label: 'billed output', value: outputTokens },
];

// Single-turn verdict from the two co-primary intervals (both lower is better).
// ship: one excludes zero in the good direction and none in the bad one.
// no-ship: either excludes zero in the bad direction, or both include zero.
function singleTurnVerdict(costCi, outputCi) {
  const dirs = [direction(costCi), direction(outputCi)];
  if (dirs.includes('bad')) return 'no-ship';
  if (dirs.includes('good')) return 'ship';
  return 'no-ship';
}

const SINGLE_TURN_PAIRS = [
  { candidate: 'lite', reference: 'bare' },
  { candidate: 'full', reference: 'bare' },
  { candidate: 'ultra', reference: 'bare' },
  { candidate: 'ultra-no-focus', reference: 'ultra' },
];
const NOISE_PAIR = { candidate: 'bare', reference: 'bare-control' };

function comparePair(cells, { candidate, reference }) {
  const of = arm => cells.filter(c => c.arm === arm);
  const { pairs, unpaired } = pairCells(of(candidate), of(reference));
  const metrics = {};
  for (const m of METRICS) {
    const mean = xs => (xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : NaN);
    const cand = pairs.map(p => m.value(p.candidate.usage));
    const ref = pairs.map(p => m.value(p.reference.usage));
    const ci = confidenceInterval(cand.map((v, i) => v - ref[i]));
    metrics[m.key] = { candidateMean: mean(cand), referenceMean: mean(ref), ci, direction: direction(ci) };
  }
  return { candidate, reference, pairs: pairs.length, unpaired, metrics };
}

// The single-turn gate over one run's cells. Each reference pair is judged
// on its paired task+seed differences; a pair whose candidate arm has no
// cells is left out (ultra-no-focus before its arm exists). When the noise
// baseline (bare vs bare-control) excludes zero on either co-primary metric,
// every verdict is 'inconclusive'. Seeds never escalate here.
function singleTurnGate(cells) {
  const noise = comparePair(cells, NOISE_PAIR);
  const noisy = METRICS.some(m => noise.metrics[m.key].direction !== 'zero');
  const candidates = SINGLE_TURN_PAIRS
    .filter(p => cells.some(c => c.arm === p.candidate))
    .map(p => {
      const cmp = comparePair(cells, p);
      cmp.verdict = noisy ? 'inconclusive' : singleTurnVerdict(cmp.metrics.cost.ci, cmp.metrics.output.ci);
      return cmp;
    });
  return { noise, noisy, candidates };
}

module.exports = {
  METRICS,
  NOISE_PAIR,
  SINGLE_TURN_PAIRS,
  cacheWeightedCost,
  confidenceInterval,
  direction,
  outputTokens,
  pairCells,
  singleTurnGate,
  singleTurnVerdict,
  tCritical95,
};
