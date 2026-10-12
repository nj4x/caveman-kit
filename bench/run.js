#!/usr/bin/env node
// caveman-kit bench — live benchmark runner (ADR 0008). Maintainer-only:
// install.sh and update.sh never copy bench/, and CI never runs it.
//
//   node bench/run.js --kind single-turn [--seeds 3] [--model claude-sonnet-5-5]
//                     [--kit-dir <repo root>] [--run-id <id>] [--results-dir <dir>]
//                     [--research-dir <dir>] [--cell-timeout <s>] [--yes]
//   node bench/run.js --kind agentic [--fixtures a,b] [--fixtures-dir <dir>] [same options]
//
// Order of work: argument checks, auth, skill and `claude` resolution,
// per-arm preflight, (agentic) fixture reliability check, cost estimate,
// confirmation — all before the first paid call. Then one headless `claude`
// call per missing cell (agentic: clone, agent run, hidden test), then the raw
// table, then the gate (agentic: paired full-diet vs full, with seed escalation)
// and (on a complete run) the summary
// note.
'use strict';

const path = require('path');
const { spawnSync } = require('child_process');
const isolation = require('./lib/isolation');
const cells = require('./lib/cells');
const estimate = require('./lib/estimate');
const report = require('./lib/report');
const stats = require('./lib/stats');
const nofocus = require('./lib/nofocus');
const agentic = require('./lib/agentic');
const fixtures = require('./lib/fixtures');
const { SINGLE_TURN_ARMS, AGENTIC_ARMS } = require('./lib/arms');
const SINGLE_TURN_TASKS = require('./tasks/single-turn');

const BENCH_DIR = __dirname;
const USAGE = `usage: node bench/run.js --kind single-turn|agentic [options]

  --kind <k>          single-turn | agentic                             required
  --seeds <n>         repeats per arm x task (or x fixture)             default 3
  --fixtures <names>  agentic: comma list of fixture names              default all
  --fixtures-dir <d>  agentic: dir holding <name>/fixture.json          default bench/fixtures
  --model <id>        model passed to claude --model                    default ${cells.DEFAULT_MODEL}
  --kit-dir <path>    kit checkout whose hooks/ are measured            default repo root
  --run-id <id>       results subdir; rerun with the same id to resume
                      default <kind>-<model>-<kit-dir HEAD short SHA>
  --results-dir <dir> parent of run dirs                                default bench/results
  --research-dir <d>  where the summary note goes                     default docs/research
  --cell-timeout <s>  seconds before one claude call is killed
                      default ${cells.DEFAULT_CELL_TIMEOUT_MS / 1000} (single-turn), ${agentic.DEFAULT_CELL_TIMEOUT_MS / 1000} (agentic)
  --min-fixtures <n>  agentic: fixture floor below which the gate is
                      inconclusive; lowering it voids the gate      default 3
  --no-escalate       agentic: never add seeds N+1..2N; a cost interval
                      that includes zero is then no-ship
  --yes               start without asking (required when there is no TTY)

Auth: ANTHROPIC_API_KEY, else a readable <config dir>/.credentials.json.
Skill: CAVEMAN_BENCH_SKILL_ROOT, else the kit manifest pluginRoot, else ~/.claude.`;

class UsageError extends Error {}

function parseArgs(argv) {
  const opts = { seeds: 3, model: cells.DEFAULT_MODEL, kitDir: path.resolve(BENCH_DIR, '..'), yes: false };
  const takesValue = {
    '--kind': 'kind', '--seeds': 'seeds', '--model': 'model', '--kit-dir': 'kitDir', '--run-id': 'runId',
    '--results-dir': 'resultsDir', '--research-dir': 'researchDir', '--cell-timeout': 'cellTimeout',
    '--fixtures': 'fixtures', '--fixtures-dir': 'fixturesDir', '--min-fixtures': 'minFixtures',
  };
  for (let i = 0; i < argv.length; i++) {
    let arg = argv[i];
    let value;
    const eq = arg.indexOf('=');
    if (arg.startsWith('--') && eq > 0) { value = arg.slice(eq + 1); arg = arg.slice(0, eq); }
    if (arg === '--yes' || arg === '--help' || arg === '-h' || arg === '--no-escalate') {
      if (value !== undefined) throw new UsageError(`${arg} takes no value`);
      if (arg === '--yes') opts.yes = true; else if (arg === '--no-escalate') opts.noEscalate = true; else opts.help = true;
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
  if (opts.cellTimeout === undefined) {
    opts.cellTimeout = (opts.kind === 'agentic' ? agentic.DEFAULT_CELL_TIMEOUT_MS : cells.DEFAULT_CELL_TIMEOUT_MS) / 1000;
  }
  const cellTimeout = Number(opts.cellTimeout);
  if (!Number.isFinite(cellTimeout) || cellTimeout <= 0) throw new UsageError(`--cell-timeout must be a positive number of seconds, got ${opts.cellTimeout}`);
  opts.cellTimeout = cellTimeout;
  if (!opts.model) throw new UsageError('--model needs a value');
  if (opts.runId !== undefined && !/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(opts.runId)) {
    throw new UsageError('--run-id must start with a letter or digit and contain only letters, digits, ".", "_" and "-"');
  }
  if (opts.fixtures !== undefined) {
    if (opts.kind !== 'agentic') throw new UsageError('--fixtures only applies to --kind agentic');
    opts.fixtures = [...new Set(opts.fixtures.split(',').map(n => n.trim()).filter(Boolean))];
    if (opts.fixtures.length === 0) throw new UsageError('--fixtures needs at least one name');
    for (const name of opts.fixtures) {
      if (!/^[A-Za-z0-9][A-Za-z0-9_]*(-[A-Za-z0-9_]+)*$/.test(name)) throw new UsageError(`invalid fixture name: ${name}`);
    }
  }
  if (opts.noEscalate && opts.kind !== 'agentic') throw new UsageError('--no-escalate only applies to --kind agentic');
  if (opts.minFixtures !== undefined) {
    if (opts.kind !== 'agentic') throw new UsageError('--min-fixtures only applies to --kind agentic');
    const min = Number(opts.minFixtures);
    if (!Number.isInteger(min) || min < 1) throw new UsageError(`--min-fixtures must be a positive integer, got ${opts.minFixtures}`);
    opts.minFixtures = min;
  } else {
    opts.minFixtures = stats.MIN_FIXTURES;
  }
  opts.kitDir = path.resolve(opts.kitDir);
  opts.fixturesDir = path.resolve(opts.fixturesDir || path.join(BENCH_DIR, 'fixtures'));
  opts.resultsDir = path.resolve(opts.resultsDir || path.join(BENCH_DIR, 'results'));
  opts.researchDir = path.resolve(opts.researchDir || path.join(BENCH_DIR, '..', 'docs', 'research'));
  return opts;
}

// Full HEAD SHA of the kit checkout under test, for the summary note, with
// "-dirty" appended when hooks/ has uncommitted changes (what was measured
// is then not exactly that commit).
function kitCommit(kitDir) {
  const res = spawnSync('git', ['-C', kitDir, 'rev-parse', 'HEAD'], { encoding: 'utf8' });
  if (res.status !== 0 || !res.stdout.trim()) return 'not a git checkout';
  const status = spawnSync('git', ['-C', kitDir, 'status', '--porcelain', '--', 'hooks'], { encoding: 'utf8' });
  const dirty = status.status !== 0 || status.stdout.trim() !== '';
  return `${res.stdout.trim()}${dirty ? '-dirty' : ''}`;
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

  const env = process.env;
  const auth = isolation.resolveAuth(env);
  const skillRoot = isolation.resolveSkillRoot(env);
  const claudePath = cells.resolveClaude(env);
  if (!claudePath) throw new isolation.BenchError('`claude` not found on PATH');

  const isAgentic = opts.kind === 'agentic';
  const arms = isAgentic ? AGENTIC_ARMS : SINGLE_TURN_ARMS;
  const runId = opts.runId || cells.defaultRunId(opts.kind, opts.model, opts.kitDir);
  const runDir = path.join(opts.resultsDir, runId);
  const armOptions = { kitDir: opts.kitDir, env, auth, skillRoot };

  // Work items: single-turn tasks, or agentic fixtures (loaded now so a bad
  // fixture or a missing diet file aborts before preflight spends anything).
  let items;
  let diet = null;
  if (isAgentic) {
    diet = agentic.dietText(opts.kitDir);
    const names = opts.fixtures || fixtures.listFixtureNames(opts.fixturesDir);
    if (names.length === 0) throw new isolation.BenchError(`no fixtures found in ${opts.fixturesDir}`);
    items = names.map(name => fixtures.loadFixture(opts.fixturesDir, name));
  } else {
    items = SINGLE_TURN_TASKS;
  }
  const itemId = item => (isAgentic ? item.name : item.id);

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
      // Context Diet text must reach full-diet and must not reach full.
      isolation.preflight(armConfig, isAgentic
        ? { requireText: arm.name === 'full-diet' ? diet : [], forbidText: arm.name === 'full' ? diet : [] }
        : {});
      if (arm.patch === 'no-focus') nofocus.checkReminder(armConfig, noFocus.clause);
    } finally {
      isolation.disposeArmConfig(armConfig);
    }
  }

  // Agentic escalation raises seedMax from N to 2N (at most once).
  let seedMax = opts.seeds;
  const buildPlan = () => {
    const plan = [];
    for (const arm of arms) {
      for (const item of items) {
        for (let seed = 1; seed <= seedMax; seed++) plan.push({ arm, item, cell: { arm: arm.name, task: itemId(item), seed } });
      }
    }
    return plan;
  };
  // A cell file from another model or kind under the same run id is stale:
  // it is rerun (and overwritten), never reused or reported.
  const current = c => Boolean(c) && c.model === opts.model && c.kind === opts.kind;
  const isPending = p => !current(cells.readCell(runDir, p.cell));
  let plan = buildPlan();
  let droppedNames = [];

  if (isAgentic) {
    // Free (offline) reliability check, only for fixtures that still have
    // cells to run. A flaky fixture is dropped and reported, never kept.
    // Includes escalation seeds N+1..2N (unless disabled), so a resumed run
    // never pays for escalation cells on an unchecked fixture.
    const checkSeedMax = opts.noEscalate ? seedMax : opts.seeds * 2;
    const needsCheck = new Set();
    for (const arm of arms) {
      for (const item of items) {
        for (let seed = 1; seed <= checkSeedMax; seed++) {
          if (isPending({ cell: { arm: arm.name, task: itemId(item), seed } })) needsCheck.add(itemId(item));
        }
      }
    }
    const dropped = [];
    const allItems = items;
    items = items.filter(item => {
      if (!needsCheck.has(itemId(item))) return true;
      const check = fixtures.checkReliability(item, env);
      if (!check.ok) dropped.push({ name: item.name, reason: check.reason });
      return check.ok;
    });
    for (const d of dropped) process.stdout.write(`DROPPED fixture ${d.name}: ${d.reason}\n`);
    if (items.length === 0) throw new isolation.BenchError('no usable fixtures left after the offline reliability check');
    droppedNames = allItems.filter(i => !items.includes(i)).map(itemId);
    // Fixture floor, checked before any paid call: below it the gate is void.
    if (items.length < opts.minFixtures) {
      process.stdout.write(`Verdict: inconclusive (${items.length} fixture(s) usable after drops, need ${opts.minFixtures}), counts as no-ship\n`);
      return 1;
    }
    plan = buildPlan();
  }
  const pending = plan.filter(isPending);

  process.stdout.write(`Run ${runId} -> ${runDir}\n`);
  process.stdout.write(`${arms.length} arms x ${items.length} ${isAgentic ? 'fixtures' : 'tasks'} x ${opts.seeds} seeds, model ${opts.model}, auth ${auth.kind}\n`);
  process.stdout.write(`${estimate.formatEstimate({ model: opts.model, pendingCalls: pending.length, doneCalls: plan.length - pending.length, kind: opts.kind })}\n`);

  const timeoutMs = opts.cellTimeout * 1000;
  // Runs the given pending plan items; returns the number of failed cells.
  const execute = async list => {
    let failures = 0;
    for (const p of list) {
      const armConfig = isolation.buildArmConfig(p.arm, optionsFor(p.arm));
      try {
        const res = isAgentic
          ? await agentic.runAgenticCell({
            claudePath, armConfig, cell: p.cell, fixture: p.item, model: opts.model, runId, runDir, testEnv: env, timeoutMs,
          })
          : await cells.runCell({
            claudePath, armConfig, cell: p.cell, prompt: p.item.prompt,
            model: opts.model, runId, kind: opts.kind, runDir, timeoutMs,
          });
        if (res.ok) {
          const verdict = isAgentic ? ` hidden-test ${res.record.hiddenTest.pass ? 'pass' : 'fail'}` : '';
          process.stdout.write(`ok   ${cells.cellId(p.cell)}${verdict}\n`);
        } else {
          failures += 1;
          process.stderr.write(`FAIL ${cells.cellId(p.cell)}: ${res.error}\n`);
        }
      } finally {
        isolation.disposeArmConfig(armConfig);
      }
    }
    return failures;
  };

  let failed = 0;
  if (pending.length > 0) {
    const answer = await estimate.confirm({ yes: opts.yes });
    if (!answer.proceed) {
      process.stderr.write(`bench: ${answer.reason}\n`);
      return 1;
    }
    failed = await execute(pending);
  }

  // Only this plan's cells: a reused run id may hold cells from a larger
  // --seeds, or stale cells from another model or kind.
  const collect = () => {
    const planned = new Set(plan.map(p => cells.cellId(p.cell)));
    return cells.readCells(runDir).filter(c => planned.has(cells.cellId(c)) && current(c));
  };
  let done = collect();
  const names = arms.map(a => a.name);
  let agenticGate = null;
  let escalated = false;
  if (isAgentic) {
    // Cells of fixtures dropped after some were paid for are excluded from the
    // pairing and listed.
    const dropSet = new Set(droppedNames);
    const excluded = () => cells.readCells(runDir)
      .filter(c => current(c) && dropSet.has(c.task) && c.seed <= seedMax).map(cells.cellId);
    const gateOpts = { minFixtures: opts.minFixtures, final: Boolean(opts.noEscalate) && failed === 0, noEscalate: Boolean(opts.noEscalate) };
    agenticGate = stats.agenticGate(done, gateOpts);
    // Escalation: only when the first interval includes zero, only once, and
    // only for seeds N+1..2N (existing cells are skipped, so resume is safe).
    if (agenticGate.escalate && failed === 0) {
      escalated = true;
      seedMax = opts.seeds * 2;
      plan = buildPlan();
      const more = plan.filter(isPending);
      process.stdout.write(`\nCost interval includes zero after ${opts.seeds} seeds: escalating to seeds ${opts.seeds + 1}-${seedMax}\n`);
      process.stdout.write(`${estimate.formatEstimate({ model: opts.model, pendingCalls: more.length, doneCalls: plan.length - more.length, kind: opts.kind })}\n`);
      if (more.length > 0) {
        const answer = await estimate.confirm({ yes: opts.yes });
        if (!answer.proceed) {
          process.stderr.write(`bench: ${answer.reason}\n`);
          return 1;
        }
        failed += await execute(more);
      }
      done = collect();
      agenticGate = stats.agenticGate(done, { ...gateOpts, final: failed === 0 });
    }
    process.stdout.write(`\n${report.formatAgenticTable(report.summarizeAgentic(done, names))}\n`);
    process.stdout.write(`\n${report.formatAgenticGate(agenticGate, excluded())}\n`);
    if (agenticGate.verdict === 'pending') {
      process.stdout.write(`\nSummary note skipped: ${failed} cell(s) failed, verdict pending; rerun with --run-id ${runId}\n`);
    } else if (done.length === plan.length) {
      const date = new Date().toISOString().slice(0, 10);
      const note = report.agenticSummaryNote({
        runId, kind: opts.kind, model: opts.model, seeds: opts.seeds, escalated,
        kitDir: opts.kitDir, kitCommit: kitCommit(opts.kitDir), runDir, date,
      }, done, agenticGate, excluded());
      const file = report.writeNote(opts.researchDir, `${date}-bench-${runId}.md`, note);
      process.stdout.write(`\nSummary note: ${file}\n`);
    } else {
      process.stdout.write(`\nSummary note skipped: ${done.length}/${plan.length} cells complete\n`);
    }
  } else {
    const rows = report.summarize(done, names);
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
