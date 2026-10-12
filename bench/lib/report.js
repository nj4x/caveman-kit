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

// Agentic raw totals per arm: hidden-test passes, turn-cap hits and the
// stream diagnostics. No statistics: the agentic gate is judged by lib/stats.js.
function summarizeAgentic(cells, armOrder = []) {
  const blank = arm => ({ arm, cells: 0, passed: 0, hitMaxTurns: 0, readChars: 0, reReads: 0, turns: 0, outputTokens: 0 });
  const byArm = new Map(armOrder.map(name => [name, blank(name)]));
  for (const cell of cells) {
    if (!byArm.has(cell.arm)) byArm.set(cell.arm, blank(cell.arm));
    const row = byArm.get(cell.arm);
    const d = cell.diagnostics || {};
    row.cells += 1;
    if (cell.hiddenTest && cell.hiddenTest.pass) row.passed += 1;
    if (cell.hitMaxTurns) row.hitMaxTurns += 1;
    for (const k of ['readChars', 'reReads', 'turns', 'outputTokens']) row[k] += Number(d[k]) || 0;
  }
  return [...byArm.values()];
}

function formatAgenticTable(rows) {
  const header = ['arm', 'cells', 'hidden_pass', 'max_turns', 'read_chars', 're_reads', 'turns', 'output'];
  const body = rows.map(r => [
    r.arm, String(r.cells), `${r.passed}/${r.cells}`, String(r.hitMaxTurns), String(r.readChars), String(r.reReads), String(r.turns), String(r.outputTokens),
  ]);
  return alignTable(header, body);
}

const pct = x => (Number.isFinite(x) ? `${(x * 100).toFixed(0)}%` : 'n/a');

function agenticUnpairedIds(gate, excluded = []) {
  return [...new Set([...gate.unpaired.map(cellId), ...excluded])].sort();
}

// Plain-text lines shared by the console report and the summary note.
function agenticGateLines(gate, excluded = []) {
  const c = gate.cost;
  const bare = gate.arms.find(a => a.arm === 'bare');
  const lines = [
    `Pairs: ${gate.pairs} across ${gate.fixtures.length} fixture(s) (${gate.fixtures.join(', ') || 'none'}); floor ${gate.minFixtures} fixtures`,
    `Cost (cache-weighted input): ${gate.candidate} ${num(c.candidateMean)}, ${gate.reference} ${num(c.referenceMean)}, `
      + `paired diff ${signed(c.ci.mean)}, 95% CI [${signed(c.ci.lo)}, ${signed(c.ci.hi)}]`,
    `Pass rate over paired cells: ${gate.candidate} ${gate.pass.candidate}/${gate.pairs} (${pct(gate.pass.candidateRate)}), `
      + `${gate.reference} ${gate.pass.reference}/${gate.pairs} (${pct(gate.pass.referenceRate)})`,
    `Turn-capped cells (hitMaxTurns): ${gate.arms.map(a => `${a.arm} ${a.capped}/${a.cells}`).join(', ')}`,
    `Bare arm (reference only, feeds no verdict): ${bare.cells} cells, ${bare.passed} hidden-test passes, mean cost ${num(bare.costMean)}`,
  ];
  const unpaired = agenticUnpairedIds(gate, excluded);
  lines.push(`Unpaired cells excluded (${unpaired.length}): ${unpaired.length ? unpaired.join(', ') : 'none'}`);
  if (gate.minFixtures < 3) lines.push(`WARNING: fixture floor lowered to ${gate.minFixtures} (default 3): this verdict is not a valid gate`);
  lines.push(`Verdict: ${gate.verdict} (${gate.reason})${gate.verdict === 'inconclusive' ? ', counts as no-ship' : ''}`);
  return lines;
}

function formatAgenticGate(gate, excluded = []) {
  return agenticGateLines(gate, excluded).join('\n');
}

// Markdown summary note for the agentic gate. params as summaryNote plus
// escalated (bool). cells: the cells the gate judged (for diagnostics).
function agenticSummaryNote(params, cells, gate, excluded = []) {
  const arms = summarizeAgentic(cells, gate.arms.map(a => a.arm));
  const header = ['arm', 'cells', 'hidden_pass', 'max_turns', 'read_chars', 're_reads', 'turns', 'output'];
  const body = arms.map(r => [r.arm, String(r.cells), `${r.passed}/${r.cells}`, String(r.hitMaxTurns), String(r.readChars), String(r.reReads), String(r.turns), String(r.outputTokens)]);
  return [
    `# Bench agentic: ${params.runId}`,
    '',
    `Date: ${params.date}`,
    '',
    '## Run parameters',
    '',
    `- Kind: ${params.kind}`,
    `- Model: ${params.model}`,
    `- Seeds: ${params.seeds}${params.escalated ? ` (escalated to ${params.seeds * 2})` : ''}`,
    `- Kit dir: ${params.kitDir}`,
    `- Kit-dir commit: ${params.kitCommit}`,
    `- Raw cells: ${params.runDir}`,
    '',
    '## Gate',
    '',
    'Paired difference is full-diet minus full, paired by fixture and seed; both cells must have completed.',
    '`ship`: the 95% cost interval excludes zero below and full-diet pass rate is not lower than full.',
    `\`no-ship\`: the interval excludes zero above, or the pass rate is lower, or the interval still includes zero after escalation (${params.seeds} to ${params.seeds * 2} seeds, once).`,
    `\`inconclusive\`: fewer than ${gate.minFixtures} fixtures remain; counts as no-ship.`,
    '',
    ...agenticGateLines(gate, excluded).map(l => `- ${l}`),
    '',
    '## Diagnostics per arm',
    '',
    `| ${header.join(' | ')} |`,
    `| ${header.map(() => '---').join(' | ')} |`,
    ...body.map(r => `| ${r.join(' | ')} |`),
    '',
  ].join('\n');
}

module.exports = { agenticSummaryNote, formatAgenticGate, summarize, formatTable, formatGate, summaryNote, writeNote, summarizeAgentic, formatAgenticTable };
