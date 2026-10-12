// caveman-kit bench — report. Raw per-arm totals, the gate table computed by
// lib/stats.js, and the docs/research/ summary note.
'use strict';

const fs = require('fs');
const path = require('path');
const { cellId } = require('./cells');

const USAGE_KEYS = [
  ['output_tokens', 'output'],
  ['input_tokens', 'input'],
  ['cache_read_input_tokens', 'cache_read'],
  ['cache_creation_input_tokens', 'cache_write'],
];

// cells: cell records as written by cells.runCell. armOrder: arm names in
// display order (arms with no cells still get a row).
function summarize(cells, armOrder = []) {
  const byArm = new Map(armOrder.map(name => [name, null]));
  for (const cell of cells) {
    if (!byArm.get(cell.arm)) {
      byArm.set(cell.arm, { arm: cell.arm, cells: 0, costUsd: 0, ...Object.fromEntries(USAGE_KEYS.map(([, k]) => [k, 0])) });
    }
    const row = byArm.get(cell.arm);
    row.cells += 1;
    for (const [src, dst] of USAGE_KEYS) row[dst] += Number((cell.usage || {})[src]) || 0;
    row.costUsd += Number(cell.totalCostUsd) || 0;
  }
  return [...byArm.entries()].map(([arm, row]) => row || {
    arm, cells: 0, costUsd: 0, ...Object.fromEntries(USAGE_KEYS.map(([, k]) => [k, 0])),
  });
}

function formatTable(rows) {
  const header = ['arm', 'cells', ...USAGE_KEYS.map(([, k]) => k), 'cost_usd'];
  const body = rows.map(r => [
    r.arm, String(r.cells), ...USAGE_KEYS.map(([, k]) => String(r[k])), r.costUsd.toFixed(4),
  ]);
  const widths = header.map((h, i) => Math.max(h.length, ...body.map(b => b[i].length)));
  const fmt = cols => cols.map((c, i) => (i === 0 ? c.padEnd(widths[i]) : c.padStart(widths[i]))).join('  ');
  return [fmt(header), fmt(widths.map(w => '-'.repeat(w))), ...body.map(fmt)].join('\n');
}

function alignTable(header, body, leftCols = 1) {
  const widths = header.map((h, i) => Math.max(h.length, ...body.map(b => b[i].length)));
  const fmt = cols => cols.map((c, i) => (i < leftCols ? c.padEnd(widths[i]) : c.padStart(widths[i]))).join('  ');
  return [fmt(header), fmt(widths.map(w => '-'.repeat(w))), ...body.map(fmt)].join('\n');
}

const num = x => (Number.isFinite(x) ? x.toFixed(1) : 'n/a');
const signed = x => (Number.isFinite(x) && x > 0 ? `+${x.toFixed(1)}` : num(x));

const GATE_HEADER = [
  'candidate', 'reference', 'pairs',
  'cost_cand', 'cost_ref', 'cost_diff', 'cost_ci95',
  'out_cand', 'out_ref', 'out_diff', 'out_ci95', 'verdict',
];

function gateRow(cmp, verdict) {
  const m = k => {
    const x = cmp.metrics[k];
    return [num(x.candidateMean), num(x.referenceMean), signed(x.ci.mean), `[${signed(x.ci.lo)}, ${signed(x.ci.hi)}]`];
  };
  return [cmp.candidate, cmp.reference, String(cmp.pairs), ...m('cost'), ...m('output'), verdict];
}

// Unpaired cells across the noise baseline and every candidate pair, deduped.
function unpairedIds(gate) {
  const ids = new Set();
  for (const cmp of [gate.noise, ...gate.candidates]) {
    for (const c of cmp.unpaired) ids.add(cellId(c));
  }
  return [...ids].sort();
}

// Why the noise baseline voids every verdict (only meaningful when noisy).
function noiseReason(gate) {
  return gate.noise.pairs < 2
    ? 'bare vs bare-control has fewer than 2 pairs: no noise baseline'
    : 'bare vs bare-control CI excludes zero: harness noise';
}

// The single-turn gate table: one row per candidate (means, paired mean
// difference and its 95% CI per co-primary metric, verdict), then the noise
// baseline row, then any unpaired cells. Costs are cache-weighted input
// tokens; lower is better for both metrics.
function formatGate(gate) {
  const body = gate.candidates.map(cmp => gateRow(cmp, cmp.verdict));
  body.push(gateRow(gate.noise, gate.noisy ? 'NOISY' : 'baseline'));
  const lines = [alignTable(GATE_HEADER, body, 2)];
  if (gate.noisy) {
    lines.push('', `${noiseReason(gate)}, every verdict is inconclusive (counts as no-ship).`);
  }
  const unpaired = unpairedIds(gate);
  if (unpaired.length) lines.push('', `Unpaired cells excluded (${unpaired.length}): ${unpaired.join(', ')}`);
  return lines.join('\n');
}

// Markdown summary note for docs/research/. params: {runId, kind, model,
// seeds, kitDir, kitCommit, runDir, date}.
function summaryNote(params, rows, gate) {
  const md = (header, body) => [
    `| ${header.join(' | ')} |`,
    `| ${header.map(() => '---').join(' | ')} |`,
    ...body.map(r => `| ${r.join(' | ')} |`),
  ].join('\n');
  const gateBody = gate.candidates.map(cmp => gateRow(cmp, `**${cmp.verdict}**`));
  gateBody.push(gateRow(gate.noise, gate.noisy ? 'NOISY' : 'baseline'));
  const rawBody = rows.map(r => [r.arm, String(r.cells), ...USAGE_KEYS.map(([, k]) => String(r[k])), r.costUsd.toFixed(4)]);
  const unpaired = unpairedIds(gate);
  return [
    `# Bench ${params.kind}: ${params.runId}`,
    '',
    `Date: ${params.date}`,
    '',
    '## Run parameters',
    '',
    `- Kind: ${params.kind}`,
    `- Model: ${params.model}`,
    `- Seeds: ${params.seeds}`,
    `- Kit dir: ${params.kitDir}`,
    `- Kit-dir commit: ${params.kitCommit}`,
    `- Raw cells: ${params.runDir}`,
    '',
    '## Gate',
    '',
    'Paired differences are candidate minus reference, paired by task and seed, with 95% t-intervals.',
    'Cost is cache-weighted input tokens (input + 0.1 x cache read + 1.25 x cache write); lower is better for both metrics.',
    '`ship`: one interval excludes zero below and the other does not exclude zero above.',
    '`no-ship`: either interval excludes zero above, or both include zero.',
    '`inconclusive`: bare vs bare-control excludes zero on either metric, or has fewer than 2 pairs; counts as no-ship.',
    '',
    md(GATE_HEADER, gateBody),
    '',
    gate.noisy ? `${noiseReason(gate)}: every verdict in this run is inconclusive.` : 'Noise baseline includes zero on both metrics.',
    '',
    `Unpaired cells excluded: ${unpaired.length ? unpaired.join(', ') : 'none'}`,
    '',
    '## Raw totals',
    '',
    md(['arm', 'cells', ...USAGE_KEYS.map(([, k]) => k), 'cost_usd'], rawBody),
    '',
  ].join('\n');
}

// Writes text atomically (temp + rename) to dir/name; returns the path.
function writeNote(dir, name, text) {
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, name);
  const tmp = path.join(dir, `.${name}.${process.pid}.tmp`);
  fs.writeFileSync(tmp, text);
  fs.renameSync(tmp, file);
  return file;
}

module.exports = { summarize, formatTable, formatGate, summaryNote, writeNote };
