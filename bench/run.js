#!/usr/bin/env node
// caveman-kit bench — live benchmark runner (ADR 0008). Maintainer-only:
// install.sh and update.sh never copy bench/, and CI never runs it.
//
//   node bench/run.js --kind single-turn [--seeds 3] [--model claude-sonnet-5-5]
//                     [--kit-dir <repo root>] [--run-id <id>] [--results-dir <dir>]
//                     [--research-dir <dir>] [--yes]
//
// Order of work: argument checks, auth, skill and `claude` resolution,
// per-arm preflight, cost estimate, confirmation — all before the first paid
// call. Then one headless `claude` call per missing cell, then the raw
// table, the gate table and (on a complete run) the summary note.
'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const isolation = require('./lib/isolation');
const cells = require('./lib/cells');
const estimate = require('./lib/estimate');
const report = require('./lib/report');
const stats = require('./lib/stats');
const nofocus = require('./lib/nofocus');
const { SINGLE_TURN_ARMS } = require('./lib/arms');
const SINGLE_TURN_TASKS = require('./tasks/single-turn');

const BENCH_DIR = __dirname;
const USAGE = `usage: node bench/run.js --kind single-turn|agentic [options]

  --kind <k>          single-turn (agentic: not implemented yet)        required
  --seeds <n>         repeats per arm x task                            default 3
  --model <id>        model passed to claude --model                    default ${cells.DEFAULT_MODEL}
  --kit-dir <path>    kit checkout whose hooks/ are measured            default repo root
  --run-id <id>       results subdir; rerun with the same id to resume
                      default <kind>-<model>-<kit-dir HEAD short SHA>
  --results-dir <dir> parent of run dirs                                default bench/results
  --research-dir <d>  where the summary note goes                     default docs/research
  --yes               start without asking (required when there is no TTY)

Auth: ANTHROPIC_API_KEY, else a readable <config dir>/.credentials.json.
Skill: CAVEMAN_BENCH_SKILL_ROOT, else the kit manifest pluginRoot, else ~/.claude.`;

class UsageError extends Error {}

function parseArgs(argv) {
  const opts = { seeds: 3, model: cells.DEFAULT_MODEL, kitDir: path.resolve(BENCH_DIR, '..'), yes: false };
  const takesValue = { '--kind': 'kind', '--seeds': 'seeds', '--model': 'model', '--kit-dir': 'kitDir', '--run-id': 'runId', '--results-dir': 'resultsDir', '--research-dir': 'researchDir' };
  for (let i = 0; i < argv.length; i++) {
    let arg = argv[i];
    let value;
    const eq = arg.indexOf('=');
    if (arg.startsWith('--') && eq > 0) { value = arg.slice(eq + 1); arg = arg.slice(0, eq); }
    if (arg === '--yes' || arg === '--help' || arg === '-h') {
      if (value !== undefined) throw new UsageError(`${arg} takes no value`);
      if (arg === '--yes') opts.yes = true; else opts.help = true;
      continue;
    }
    const key = takesValue[arg];
    if (!key) throw new UsageError(`unknown option: ${argv[i]}`);
    if (value === undefined) {
      value = argv[++i];
      if (value === undefined || value.startsWith('--')) throw new UsageError(`${arg} needs a value`);
    }
    opts[key] = value;
  }
  if (opts.help) return opts;
  if (!opts.kind) throw new UsageError('--kind is required');
  if (!['single-turn', 'agentic'].includes(opts.kind)) throw new UsageError(`unknown --kind: ${opts.kind}`);
  const seeds = Number(opts.seeds);
  if (!Number.isInteger(seeds) || seeds < 1) throw new UsageError(`--seeds must be a positive integer, got ${opts.seeds}`);
  opts.seeds = seeds;
  if (!opts.model) throw new UsageError('--model needs a value');
  if (opts.runId !== undefined && !/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(opts.runId)) {
    throw new UsageError('--run-id must start with a letter or digit and contain only letters, digits, ".", "_" and "-"');
  }
  opts.kitDir = path.resolve(opts.kitDir);
  opts.resultsDir = path.resolve(opts.resultsDir || path.join(BENCH_DIR, 'results'));
  opts.researchDir = path.resolve(opts.researchDir || path.join(BENCH_DIR, '..', 'docs', 'research'));
  return opts;
}

// Full HEAD SHA of the kit checkout under test, for the summary note.
function kitCommit(kitDir) {
  const res = spawnSync('git', ['-C', kitDir, 'rev-parse', 'HEAD'], { encoding: 'utf8' });
  return res.status === 0 && res.stdout.trim() ? res.stdout.trim() : 'not a git checkout';
}

function installSignalHandlers() {
  for (const [signal, code] of [['SIGHUP', 129], ['SIGINT', 130], ['SIGTERM', 143]]) {
    process.on(signal, async () => {
      process.stderr.write(`\nbench: ${signal}, stopping\n`);
      await cells.stopActive(signal);
      isolation.cleanupTempRoots();
      process.exit(code);
    });
  }
}

async function main() {
  let opts;
  try {
    opts = parseArgs(process.argv.slice(2));
  } catch (e) {
    if (!(e instanceof UsageError)) throw e;
    process.stderr.write(`bench: ${e.message}\n${USAGE}\n`);
    return 2;
  }
  if (opts.help) { process.stdout.write(`${USAGE}\n`); return 0; }
  if (opts.kind === 'agentic') {
    process.stderr.write('bench: --kind agentic is not implemented yet\n');
    return 2;
  }

  const env = process.env;
  const auth = isolation.resolveAuth(env);
  const skillRoot = isolation.resolveSkillRoot(env);
  const claudePath = cells.resolveClaude(env);
  if (!claudePath) throw new isolation.BenchError('`claude` not found on PATH');

  const arms = SINGLE_TURN_ARMS;
  const tasks = SINGLE_TURN_TASKS;
  const runId = opts.runId || cells.defaultRunId(opts.kind, opts.model, opts.kitDir);
  const runDir = path.join(opts.resultsDir, runId);
  const armOptions = { kitDir: opts.kitDir, env, auth, skillRoot };

  // ultra-no-focus: patch a temp copy of the hooks before any paid call; a
  // missing focus clause throws here, before the estimate. The copy lives in
  // the arms' own 0700 temp root, removed on every exit path.
  let noFocus = null;
  if (arms.some(a => a.patch === 'no-focus')) {
    noFocus = nofocus.patchNoFocus(path.join(opts.kitDir, 'hooks'), isolation.getDefaultRoot());
  }
  const optionsFor = arm => (arm.patch === 'no-focus' ? { ...armOptions, hooksDir: noFocus.hooksDir } : armOptions);

  for (const arm of arms) {
    const armConfig = isolation.buildArmConfig(arm, optionsFor(arm));
    try {
      isolation.preflight(armConfig);
      if (arm.patch === 'no-focus') nofocus.checkReminder(armConfig, noFocus.clause);
    } finally {
      isolation.disposeArmConfig(armConfig);
    }
  }

  const plan = [];
  for (const arm of arms) {
    for (const task of tasks) {
      for (let seed = 1; seed <= opts.seeds; seed++) plan.push({ arm, task, cell: { arm: arm.name, task: task.id, seed } });
    }
  }
  const pending = plan.filter(p => !fs.existsSync(cells.cellPath(runDir, p.cell)));

  process.stdout.write(`Run ${runId} -> ${runDir}\n`);
  process.stdout.write(`${arms.length} arms x ${tasks.length} tasks x ${opts.seeds} seeds, model ${opts.model}, auth ${auth.kind}\n`);
  process.stdout.write(`${estimate.formatEstimate({ model: opts.model, pendingCalls: pending.length, doneCalls: plan.length - pending.length })}\n`);

  let failed = 0;
  if (pending.length > 0) {
    const answer = await estimate.confirm({ yes: opts.yes });
    if (!answer.proceed) {
      process.stderr.write(`bench: ${answer.reason}\n`);
      return 1;
    }
    for (const p of pending) {
      const armConfig = isolation.buildArmConfig(p.arm, optionsFor(p.arm));
      try {
        const res = await cells.runCell({
          claudePath, armConfig, cell: p.cell, prompt: p.task.prompt,
          model: opts.model, runId, kind: opts.kind, runDir,
        });
        if (res.ok) {
          process.stdout.write(`ok   ${cells.cellId(p.cell)}\n`);
        } else {
          failed += 1;
          process.stderr.write(`FAIL ${cells.cellId(p.cell)}: ${res.error}\n`);
        }
      } finally {
        isolation.disposeArmConfig(armConfig);
      }
    }
  }

  // Only this plan's cells: a reused run id may hold cells from a larger --seeds.
  const planned = new Set(plan.map(p => cells.cellId(p.cell)));
  const done = cells.readCells(runDir).filter(c => planned.has(cells.cellId(c)));
  const rows = report.summarize(done, arms.map(a => a.name));
  process.stdout.write(`\n${report.formatTable(rows)}\n`);
  // Seeds never escalate in the single-turn harness: the gate judges exactly
  // the --seeds cells planned above.
  const gate = stats.singleTurnGate(done);
  process.stdout.write(`\n${report.formatGate(gate)}\n`);
  if (done.length === plan.length) {
    const date = new Date().toISOString().slice(0, 10);
    const note = report.summaryNote({
      runId, kind: opts.kind, model: opts.model, seeds: opts.seeds,
      kitDir: opts.kitDir, kitCommit: kitCommit(opts.kitDir), runDir, date,
    }, rows, gate);
    const file = report.writeNote(opts.researchDir, `${date}-bench-${runId}.md`, note);
    process.stdout.write(`\nSummary note: ${file}\n`);
  } else {
    process.stdout.write(`\nSummary note skipped: ${done.length}/${plan.length} cells complete\n`);
  }
  if (failed > 0) {
    process.stderr.write(`bench: ${failed} cell(s) failed; rerun with --run-id ${runId} to retry them\n`);
    return 1;
  }
  return 0;
}

installSignalHandlers();
main().then(
  code => { isolation.cleanupTempRoots(); process.exit(code); },
  err => {
    isolation.cleanupTempRoots();
    process.stderr.write(`bench: ${err instanceof isolation.BenchError ? err.message : err.stack}\n`);
    process.exit(1);
  }
);
