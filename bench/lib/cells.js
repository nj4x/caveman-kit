// caveman-kit bench — cell runner.
//
// A cell is one (arm, task, seed) call to a headless `claude`. The seed is a
// repeat index only and is never passed to claude. Each successful call
// writes one JSON file, atomically (temp + rename), under
// <resultsDir>/<runId>/. A failed call writes nothing, so a rerun with the
// same run id retries it and skips every cell that already has a file.
'use strict';

const fs = require('fs');
const path = require('path');
const { spawn, spawnSync } = require('child_process');

const DEFAULT_MODEL = 'claude-sonnet-5-5';

// <kind>-<model>-<kit-dir HEAD short SHA>; 'nogit' when kitDir is not a git
// checkout. Uncommitted hook edits do not change the id: pass --run-id.
function defaultRunId(kind, model, kitDir) {
  let sha = 'nogit';
  const res = spawnSync('git', ['-C', kitDir, 'rev-parse', '--short', 'HEAD'], { encoding: 'utf8' });
  if (res.status === 0 && res.stdout.trim()) sha = res.stdout.trim();
  return `${kind}-${model}-${sha}`.replace(/[^A-Za-z0-9._-]/g, '_');
}

function cellId(cell) {
  return `${cell.arm}--${cell.task}--s${cell.seed}`;
}

function cellPath(runDir, cell) {
  return path.join(runDir, `${cellId(cell)}.json`);
}

function writeJsonAtomic(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = path.join(path.dirname(file), `.${path.basename(file)}.${process.pid}.tmp`);
  fs.writeFileSync(tmp, JSON.stringify(data, null, 2) + '\n');
  fs.renameSync(tmp, file);
}

// One cell's record, or null when its file is missing or unreadable.
function readCell(runDir, cell) {
  try { return JSON.parse(fs.readFileSync(cellPath(runDir, cell), 'utf8')); } catch (e) { return null; }
}

// Every completed cell file in a run dir (temp files are skipped).
function readCells(runDir) {
  let names = [];
  try { names = fs.readdirSync(runDir); } catch (e) { return []; }
  const cells = [];
  for (const name of names.sort()) {
    if (!name.endsWith('.json') || name.startsWith('.')) continue;
    try { cells.push(JSON.parse(fs.readFileSync(path.join(runDir, name), 'utf8'))); } catch (e) { /* skip */ }
  }
  return cells;
}

// The `claude` executable from env's PATH (the test seam). Arm envs inherit
// PATH unchanged, so resolving once from the base env is enough.
function resolveClaude(env) {
  for (const dir of (env.PATH || '').split(path.delimiter)) {
    if (!dir) continue;
    const candidate = path.join(dir, 'claude');
    try {
      fs.accessSync(candidate, fs.constants.X_OK);
      if (fs.statSync(candidate).isFile()) return candidate;
    } catch (e) { /* next */ }
  }
  return null;
}

const KILL_GRACE_MS = 5000;
const DEFAULT_CELL_TIMEOUT_MS = 10 * 60 * 1000;

let activeChild = null;

// Sends signal to child, escalates to SIGKILL after KILL_GRACE_MS, and
// resolves once it exits (or 1s after the SIGKILL, whichever comes first).
function terminate(child, signal) {
  if (child.exitCode !== null || child.signalCode !== null) return Promise.resolve();
  return new Promise(resolve => {
    let giveUp = null;
    const killTimer = setTimeout(() => {
      try { child.kill('SIGKILL'); } catch (e) { /* already gone */ }
      giveUp = setTimeout(done, 1000);
    }, KILL_GRACE_MS);
    function done() { clearTimeout(killTimer); clearTimeout(giveUp); resolve(); }
    child.once('exit', done);
    try { child.kill(signal); } catch (e) { done(); }
  });
}

// Stops an in-flight claude call (signal path) and waits for it to exit, so
// the caller can remove the temp dir without the child re-creating files in it.
function stopActive(signal) {
  return activeChild ? terminate(activeChild, signal) : Promise.resolve();
}

// Runs claude once; after timeoutMs it is terminated and timedOut is set.
function invoke(claudePath, args, armConfig, timeoutMs) {
  return new Promise(resolve => {
    const child = spawn(claudePath, args, {
      cwd: armConfig.workDir, env: armConfig.env, stdio: ['ignore', 'pipe', 'pipe'],
    });
    activeChild = child;
    let stdout = '';
    let stderr = '';
    let timedOut = false;
    const timer = setTimeout(() => { timedOut = true; terminate(child, 'SIGTERM'); }, timeoutMs);
    child.stdout.on('data', d => { stdout += d; });
    child.stderr.on('data', d => { stderr += d; });
    child.on('error', err => { clearTimeout(timer); activeChild = null; resolve({ status: null, stdout, stderr: String(err.message), timedOut }); });
    child.on('close', (status, signal) => { clearTimeout(timer); activeChild = null; resolve({ status, signal, stdout, stderr, timedOut }); });
  });
}

// Runs one cell. Returns { ok: true, record } after writing the file, or
// { ok: false, error } and writes nothing.
async function runCell({ claudePath, armConfig, cell, prompt, model, runId, kind, runDir, timeoutMs = DEFAULT_CELL_TIMEOUT_MS }) {
  const args = ['-p', prompt, '--output-format', 'json', '--model', model];
  const started = Date.now();
  const res = await invoke(claudePath, args, armConfig, timeoutMs);
  const durationMs = Date.now() - started;
  if (res.timedOut) {
    return { ok: false, error: `timed out after ${timeoutMs / 1000}s (${res.signal ? `killed by ${res.signal}` : `exit ${res.status}`})` };
  }
  if (res.status !== 0) {
    const why = res.signal ? `killed by ${res.signal}` : `exit ${res.status}`;
    return { ok: false, error: `${why}: ${res.stderr.trim().slice(-500)}` };
  }
  let output;
  try {
    output = JSON.parse(res.stdout);
  } catch (e) {
    return { ok: false, error: `non-JSON output: ${res.stdout.trim().slice(0, 200)}` };
  }
  if (!output || output.is_error || !output.usage) {
    return { ok: false, error: `error result: ${JSON.stringify(output).slice(0, 300)}` };
  }
  const record = {
    runId, kind, model,
    arm: cell.arm, mode: armConfig.mode, task: cell.task, seed: cell.seed,
    finishedAt: new Date().toISOString(),
    durationMs,
    usage: output.usage,
    totalCostUsd: typeof output.total_cost_usd === 'number' ? output.total_cost_usd : null,
    result: output.result,
    output,
  };
  writeJsonAtomic(cellPath(runDir, cell), record);
  return { ok: true, record };
}

module.exports = {
  DEFAULT_CELL_TIMEOUT_MS,
  DEFAULT_MODEL,
  defaultRunId,
  cellId,
  cellPath,
  readCell,
  readCells,
  resolveClaude,
  invoke,
  runCell,
  stopActive,
  writeJsonAtomic,
};
