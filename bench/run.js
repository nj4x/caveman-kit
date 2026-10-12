#!/usr/bin/env node
// caveman-kit bench — live benchmark runner (ADR 0008). Maintainer-only:
// install.sh and update.sh never copy bench/, and CI never runs it.
//
//   node bench/run.js --kind single-turn [--seeds 3] [--model claude-sonnet-5-5]
//                     [--kit-dir <repo root>] [--run-id <id>] [--results-dir <dir>] [--yes]
//   node bench/run.js --kind agentic [--fixtures a,b] [--fixtures-dir <dir>] [same options]
//
// Order of work: argument checks, auth, skill and `claude` resolution,
// per-arm preflight, (agentic) fixture reliability check, cost estimate,
// confirmation — all before the first paid call. Then one headless `claude`
// call per missing cell (agentic: clone, agent run, hidden test), then the table.
'use strict';

const fs = require('fs');
const path = require('path');
const isolation = require('./lib/isolation');
const cells = require('./lib/cells');
const estimate = require('./lib/estimate');
const report = require('./lib/report');
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
  --yes               start without asking (required when there is no TTY)

Auth: ANTHROPIC_API_KEY, else a readable <config dir>/.credentials.json.
Skill: CAVEMAN_BENCH_SKILL_ROOT, else the kit manifest pluginRoot, else ~/.claude.`;

class UsageError extends Error {}

function parseArgs(argv) {
  const opts = { seeds: 3, model: cells.DEFAULT_MODEL, kitDir: path.resolve(BENCH_DIR, '..'), yes: false };
  const takesValue = { '--kind': 'kind', '--seeds': 'seeds', '--model': 'model', '--kit-dir': 'kitDir', '--run-id': 'runId', '--results-dir': 'resultsDir', '--fixtures': 'fixtures', '--fixtures-dir': 'fixturesDir' };
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
  opts.fixturesDir = path.resolve(opts.fixturesDir || path.join(BENCH_DIR, 'fixtures'));
  if (opts.fixtures !== undefined) {
    opts.fixtures = [...new Set(opts.fixtures.split(',').map(n => n.trim()).filter(Boolean))];
    for (const name of opts.fixtures) {
      if (!/^[A-Za-z0-9][A-Za-z0-9_]*(-[A-Za-z0-9_]+)*$/.test(name)) throw new UsageError(`invalid fixture name: ${name}`);
    }
    if (opts.fixtures.length === 0) throw new UsageError('--fixtures needs at least one name');
    if (opts.kind !== 'agentic') throw new UsageError('--fixtures only applies to --kind agentic');
  }
  opts.resultsDir = path.resolve(opts.resultsDir || path.join(BENCH_DIR, 'results'));
  return opts;
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

  for (const arm of arms) {
    const armConfig = isolation.buildArmConfig(arm, armOptions);
    try {
      // Context Diet text must reach full-diet and must not reach full.
      isolation.preflight(armConfig, isAgentic
        ? { requireText: arm.name === 'full-diet' ? diet : [], forbidText: arm.name === 'full' ? diet : [] }
        : {});
    } finally {
      isolation.disposeArmConfig(armConfig);
    }
  }

  const buildPlan = () => {
    const plan = [];
    for (const arm of arms) {
      for (const item of items) {
        for (let seed = 1; seed <= opts.seeds; seed++) plan.push({ arm, item, cell: { arm: arm.name, task: itemId(item), seed } });
      }
    }
    return plan;
  };
  let plan = buildPlan();

  if (isAgentic) {
    // Free (offline) reliability check, only for fixtures that still have
    // cells to run. A flaky fixture is dropped and reported, never kept.
    const dropped = [];
    const needsCheck = new Set(plan.filter(p => !fs.existsSync(cells.cellPath(runDir, p.cell))).map(p => itemId(p.item)));
    for (const item of [...items]) {
      if (!needsCheck.has(itemId(item))) continue;
      const check = fixtures.checkReliability(item, env);
      if (!check.ok) {
        dropped.push({ name: item.name, reason: check.reason });
        items = items.filter(i => i !== item);
      }
    }
    for (const d of dropped) process.stdout.write(`DROPPED fixture ${d.name}: ${d.reason}\n`);
    if (items.length === 0) throw new isolation.BenchError('no usable fixtures left after the offline reliability check');
    plan = buildPlan();
  }
  const pending = plan.filter(p => !fs.existsSync(cells.cellPath(runDir, p.cell)));

  process.stdout.write(`Run ${runId} -> ${runDir}\n`);
  process.stdout.write(`${arms.length} arms x ${items.length} ${isAgentic ? 'fixtures' : 'tasks'} x ${opts.seeds} seeds, model ${opts.model}, auth ${auth.kind}\n`);
  process.stdout.write(`${estimate.formatEstimate({ model: opts.model, pendingCalls: pending.length, doneCalls: plan.length - pending.length, kind: opts.kind })}\n`);

  let failed = 0;
  if (pending.length > 0) {
    const answer = await estimate.confirm({ yes: opts.yes });
    if (!answer.proceed) {
      process.stderr.write(`bench: ${answer.reason}\n`);
      return 1;
    }
    for (const p of pending) {
      const armConfig = isolation.buildArmConfig(p.arm, armOptions);
      try {
        const res = isAgentic
          ? await agentic.runAgenticCell({
            claudePath, armConfig, cell: p.cell, fixture: p.item, model: opts.model, runId, runDir, testEnv: env,
          })
          : await cells.runCell({
            claudePath, armConfig, cell: p.cell, prompt: p.item.prompt,
            model: opts.model, runId, kind: opts.kind, runDir,
          });
        if (res.ok) {
          const verdict = isAgentic ? ` hidden-test ${res.record.hiddenTest.pass ? 'pass' : 'fail'}` : '';
          process.stdout.write(`ok   ${cells.cellId(p.cell)}${verdict}\n`);
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
  const names = arms.map(a => a.name);
  const table = isAgentic
    ? report.formatAgenticTable(report.summarizeAgentic(done, names))
    : report.formatTable(report.summarize(done, names));
  process.stdout.write(`\n${table}\n`);
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
