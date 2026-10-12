// caveman-kit bench — report. Raw per-arm totals only; statistics and the
// ship gate belong to a separate stats module.
'use strict';

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

module.exports = { summarize, formatTable };
