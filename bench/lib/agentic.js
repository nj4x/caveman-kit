// caveman-kit bench — agentic cell runner (ADR 0008, ADR 0009).
//
// One cell = one (arm, fixture, seed): clone the fixture into the arm's work
// dir, run `claude` there with streaming JSON output, then — only after the
// agent has exited — copy the hidden test in and run it. A cell file records
// the hidden-test result and the diagnostics parsed from the stream; the raw
// stream goes to a sibling .stream.jsonl. No statistics here.
'use strict';

const fs = require('fs');
const path = require('path');
const cells = require('./cells');
const fixtures = require('./fixtures');
const stream = require('./stream');
const { BenchError } = require('./isolation');

const DIET_FILE = 'caveman-context-diet.md';
// Cap on agent turns per run, so a looping agent cannot burn unbounded quota.
// A run that hits it is a completed cell (subtype error_max_turns): the hidden
// test still runs and the record carries hitMaxTurns, so the arm that loops
// most is not silently dropped and re-paid on every rerun.
const MAX_TURNS = 40;
const MAX_TURNS_SUBTYPE = 'error_max_turns';
// An agentic run takes many turns: its default --cell-timeout is longer than
// the single-turn one.
const DEFAULT_CELL_TIMEOUT_MS = 30 * 60 * 1000;

// The injected form of the diet file: HTML comments stripped, trimmed. This
// is what preflight requires in `full-diet` and forbids in `full`.
function dietText(kitDir) {
  const file = path.join(kitDir, 'hooks', DIET_FILE);
  let raw;
  try {
    raw = fs.readFileSync(file, 'utf8');
  } catch (e) {
    throw new BenchError(`Context Diet file missing or unreadable: ${file}`);
  }
  const text = raw.replace(/<!--[\s\S]*?-->/g, '').trim();
  if (!text) throw new BenchError(`Context Diet file has no text after stripping comments: ${file}`);
  return text;
}

function streamPath(runDir, cell) {
  return path.join(runDir, `${cells.cellId(cell)}.stream.jsonl`);
}

function writeTextAtomic(file, text) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = path.join(path.dirname(file), `.${path.basename(file)}.${process.pid}.tmp`);
  fs.writeFileSync(tmp, text);
  fs.renameSync(tmp, file);
}

// Returns { ok: true, record } after writing the cell file, or
// { ok: false, error } and writes nothing (a hidden-test failure is a result,
// not a cell failure).
async function runAgenticCell({ claudePath, armConfig, cell, fixture, model, runId, runDir, testEnv, timeoutMs = DEFAULT_CELL_TIMEOUT_MS }) {
  try {
    fixtures.prepareWorkDir(fixture, armConfig.workDir);
  } catch (e) {
    return { ok: false, error: `fixture setup: ${e.message}` };
  }
  const args = [
    '-p', fixture.prompt,
    '--output-format', 'stream-json', '--verbose',
    '--model', model,
    '--permission-mode', 'bypassPermissions',
    '--max-turns', String(MAX_TURNS),
  ];
  const started = Date.now();
  const res = await cells.invoke(claudePath, args, armConfig, timeoutMs);
  const durationMs = Date.now() - started;
  // Cell files, raw streams and printed errors must never hold the API key.
  // Diagnostics are parsed from the unredacted stream. Redact before any
  // truncation, so a cut never leaves a key fragment split() cannot match.
  const secret = armConfig.env.ANTHROPIC_API_KEY;
  const redact = text => (secret && typeof text === 'string' ? text.split(secret).join('[redacted]') : text);
  if (res.timedOut) {
    return { ok: false, error: `timed out after ${timeoutMs / 1000}s (${res.signal ? `killed by ${res.signal}` : `exit ${res.status}`})` };
  }
  if (res.signal || res.status === null) {
    return { ok: false, error: `${res.signal ? `killed by ${res.signal}` : 'did not run'}: ${redact(res.stderr).trim().slice(-500)}` };
  }
  // Parsed before the exit check: the CLI exits non-zero when --max-turns
  // stops the run, and that run is still a completed cell.
  const { result, diagnostics } = stream.analyze(res.stdout);
  const hitMaxTurns = Boolean(result && result.subtype === MAX_TURNS_SUBTYPE && result.usage);
  if (res.status !== 0 && !hitMaxTurns) {
    return { ok: false, error: `exit ${res.status}: ${redact(res.stderr).trim().slice(-500)}` };
  }
  if (!result || !result.usage || (result.is_error && !hitMaxTurns)) {
    return { ok: false, error: `no usable result event: ${redact(JSON.stringify(result) || 'none').slice(0, 300)}` };
  }

  // The agent is done: only now does the hidden test enter the work dir.
  const hidden = fixtures.runHiddenTest(fixture, armConfig.workDir, testEnv, redact);

  const record = {
    runId, kind: 'agentic', model,
    arm: cell.arm, mode: armConfig.mode, task: cell.task, seed: cell.seed,
    finishedAt: new Date().toISOString(),
    durationMs,
    usage: result.usage,
    totalCostUsd: typeof result.total_cost_usd === 'number' ? result.total_cost_usd : null,
    result: redact(result.result),
    hitMaxTurns,
    hiddenTest: { pass: hidden.pass, exitCode: hidden.exitCode, timedOut: hidden.timedOut, tail: hidden.tail },
    diagnostics,
  };
  writeTextAtomic(streamPath(runDir, cell), redact(res.stdout));
  cells.writeJsonAtomic(cells.cellPath(runDir, cell), record);
  return { ok: true, record };
}

module.exports = { DEFAULT_CELL_TIMEOUT_MS, DIET_FILE, MAX_TURNS, dietText, runAgenticCell };
