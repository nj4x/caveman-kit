// caveman-kit bench — cost estimate and run confirmation.
//
// The estimate is deliberately rough: a fixed per-call token assumption times
// list price. It exists so a maintainer can abort an expensive run, not to
// predict the bill. Edit the constants when prices or prompt sizes change.
'use strict';

const readline = require('readline');

// USD per million tokens. Unknown models fall back to the Sonnet row.
const PRICES = {
  'claude-sonnet-5-5': { input: 3, output: 15 },
  'claude-opus-5-5': { input: 5, output: 25 },
};
const FALLBACK_MODEL = 'claude-sonnet-5-5';

// Per single-turn call: Claude Code's system prompt plus injected ruleset,
// billed as uncached input (upper bound), and a medium-length answer.
const ASSUMED_TOKENS = { input: 25000, output: 1000 };

// Per agentic run: a multi-turn tool loop. Rough upper bound, uncached input.
const ASSUMED_AGENTIC_TOKENS = { input: 300000, output: 12000 };

function assumed(kind) {
  return kind === 'agentic' ? ASSUMED_AGENTIC_TOKENS : ASSUMED_TOKENS;
}

function estimateCost({ model, pendingCalls, kind = 'single-turn' }) {
  const known = Object.prototype.hasOwnProperty.call(PRICES, model);
  const price = PRICES[known ? model : FALLBACK_MODEL];
  const perCall = (assumed(kind).input * price.input + assumed(kind).output * price.output) / 1e6;
  return { perCall, total: perCall * pendingCalls, knownModel: known };
}

// warmupCalls (agentic, ADR 0010): one-turn calls priced as single-turn calls.
function formatEstimate({ model, pendingCalls, doneCalls, kind = 'single-turn', warmupCalls = 0 }) {
  const e = estimateCost({ model, pendingCalls, kind });
  const lines = [
    `Estimated cost: ${pendingCalls} call(s) x ~$${e.perCall.toFixed(3)} = ~$${e.total.toFixed(2)} ` +
    `(${doneCalls} cell(s) already done, skipped)`,
    `  assumes ~${assumed(kind).input} uncached input + ~${assumed(kind).output} output tokens per call at ` +
    `${e.knownModel ? model : `${FALLBACK_MODEL} prices (unknown model ${model})`} list price`,
  ];
  if (warmupCalls > 0) {
    const w = estimateCost({ model, pendingCalls: warmupCalls, kind: 'single-turn' });
    lines.push(`  plus ${warmupCalls} warmup call(s) x ~$${w.perCall.toFixed(3)} = ~$${w.total.toFixed(2)} ` +
      `(total ~$${(e.total + w.total).toFixed(2)})`);
  }
  return lines.join('\n');
}

// --yes: proceed. TTY: ask. No TTY: refuse. Resolves { proceed, reason? }.
function confirm({ yes, stdin = process.stdin, stderr = process.stderr }) {
  if (yes) return Promise.resolve({ proceed: true });
  if (!stdin.isTTY) {
    return Promise.resolve({ proceed: false, reason: 'refusing to start: no TTY to confirm; pass --yes to run unattended' });
  }
  return new Promise(resolve => {
    const rl = readline.createInterface({ input: stdin, output: stderr });
    let answered = false;
    // End of input (Ctrl-D) before an answer counts as "no".
    rl.on('close', () => { if (!answered) resolve({ proceed: false, reason: 'aborted by user' }); });
    rl.question('Proceed? [y/N] ', answer => {
      answered = true;
      rl.close();
      const ok = /^y(es)?$/i.test(answer.trim());
      resolve(ok ? { proceed: true } : { proceed: false, reason: 'aborted by user' });
    });
  });
}

module.exports = { PRICES, ASSUMED_TOKENS, ASSUMED_AGENTIC_TOKENS, estimateCost, formatEstimate, confirm };
