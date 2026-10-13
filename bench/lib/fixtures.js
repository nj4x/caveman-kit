// caveman-kit bench — agentic fixtures (ADR 0008 decision 5).
//
// A fixture is a directory <fixtures-dir>/<name>/ holding:
//
//   fixture.json   { "source": "<git URL or path>",
//                    "sha": "<pinned commit, 7-40 hex>",
//                    "testCommand": "pytest -x -q"   (run by `sh -c` in the repo root;
//                                                     e.g. "pytest ..." or "uv run pytest ...")
//                    "plantPatch": "plant.patch"     (optional, default shown),
//                    "prompt": "prompt.md"           (optional, default shown) }
//   plant.patch    `git apply` patch that plants the bug
//   prompt.md      the task prompt given to the agent
//   hidden/        hidden test file(s); this tree is copied over the repo root
//                  only after the agent has finished
//
// Work dir lifecycle: clone at the pinned SHA, discard the clone's .git, apply
// the plant patch and record the tree as one fresh root commit (so neither the
// bug nor the upstream history is visible to the agent), run the agent, copy
// hidden/ in, run testCommand. A relative "source" resolves against the fixture
// directory. Tests run with UV_OFFLINE=1 and PIP_NO_INDEX=1.
// Before any paid call checkReliability() runs the hidden test twice on the
// unpatched tree (must pass) and twice on the planted tree (must fail).
'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { BenchError, createTempRoot } = require('./isolation');

const TEST_TIMEOUT_MS = 10 * 60 * 1000;
const RELIABILITY_RUNS = 2;

function loadFixture(fixturesDir, name) {
  const dir = path.join(fixturesDir, name);
  let meta;
  try {
    meta = JSON.parse(fs.readFileSync(path.join(dir, 'fixture.json'), 'utf8'));
  } catch (e) {
    throw new BenchError(`fixture ${name}: cannot read ${path.join(dir, 'fixture.json')}: ${e.message}`);
  }
  const fail = msg => { throw new BenchError(`fixture ${name}: ${msg}`); };
  if (typeof meta.source !== 'string' || !meta.source) fail('fixture.json needs "source"');
  if (typeof meta.sha !== 'string' || !/^[0-9a-f]{7,40}$/.test(meta.sha)) fail('fixture.json needs "sha" (7-40 hex chars)');
  if (typeof meta.testCommand !== 'string' || !meta.testCommand.trim()) fail('fixture.json needs "testCommand"');
  const plantPatch = path.join(dir, meta.plantPatch || 'plant.patch');
  const promptFile = path.join(dir, meta.prompt || 'prompt.md');
  const hiddenDir = path.join(dir, 'hidden');
  if (!fs.existsSync(plantPatch)) fail(`missing plant patch ${plantPatch}`);
  if (!fs.existsSync(promptFile)) fail(`missing prompt ${promptFile}`);
  if (!fs.existsSync(hiddenDir) || fs.readdirSync(hiddenDir).length === 0) fail(`missing hidden test files in ${hiddenDir}`);
  const prompt = fs.readFileSync(promptFile, 'utf8').trim();
  if (!prompt) fail('empty prompt');
  const isUrl = /^([a-z][a-z0-9+.-]*:\/\/|[\w.-]+@[\w.-]+:)/i.test(meta.source);
  const source = isUrl ? meta.source : path.resolve(dir, meta.source);
  return { name, dir, source, sha: meta.sha, testCommand: meta.testCommand, plantPatch, prompt, hiddenDir };
}

function listFixtureNames(fixturesDir) {
  let names = [];
  try { names = fs.readdirSync(fixturesDir, { withFileTypes: true }); } catch (e) { return []; }
  return names
    .filter(d => d.isDirectory() && fs.existsSync(path.join(fixturesDir, d.name, 'fixture.json')))
    .map(d => d.name)
    .sort();
}

function git(cwd, args) {
  const res = spawnSync('git', args, { cwd, encoding: 'utf8', timeout: 5 * 60 * 1000 });
  if (res.error || res.status !== 0) {
    const why = res.error ? res.error.message : (res.stderr || res.stdout || '').trim();
    throw new BenchError(`git ${args.join(' ')}: ${why.slice(-400)}`);
  }
  return res.stdout;
}

// Clones fixture.source into workDir (an existing empty dir) at fixture.sha.
// The result is a single root commit; with plant, the patch is applied first.
function prepareWorkDir(fixture, workDir, { plant = true } = {}) {
  git(path.dirname(workDir), ['clone', '--quiet', '--no-checkout', '--', fixture.source, workDir]);
  git(workDir, ['checkout', '--quiet', '--detach', fixture.sha]);
  const head = git(workDir, ['rev-parse', 'HEAD']).trim();
  if (!head.startsWith(fixture.sha)) throw new BenchError(`fixture ${fixture.name}: checked out ${head}, not ${fixture.sha}`);
  fs.rmSync(path.join(workDir, '.git'), { recursive: true, force: true });
  git(workDir, ['init', '--quiet']);
  if (plant) git(workDir, ['apply', '--whitespace=nowarn', fixture.plantPatch]);
  git(workDir, ['add', '-A']);
  // Ignore the user's global hooks and signing config: the commit must not fail.
  git(workDir, ['-c', 'user.name=bench', '-c', 'user.email=bench@localhost', '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', 'commit', '--quiet', '--no-verify', '-m', 'initial']);
}

function offlineEnv(base = process.env) {
  const env = { ...base, UV_OFFLINE: '1', PIP_NO_INDEX: '1' };
  delete env.ANTHROPIC_API_KEY;
  return env;
}

// Copies the hidden test in and runs testCommand. pass = exit 0. redact is
// applied to the full output before it is cut to the tail.
function runHiddenTest(fixture, workDir, env = process.env, redact = text => text) {
  try {
    fs.cpSync(fixture.hiddenDir, workDir, { recursive: true, force: true });
  } catch (e) {
    return { pass: false, exitCode: null, timedOut: false, tail: `could not copy hidden test: ${e.message}` };
  }
  const res = spawnSync('/bin/sh', ['-c', fixture.testCommand], {
    cwd: workDir, env: offlineEnv(env), encoding: 'utf8', timeout: TEST_TIMEOUT_MS, maxBuffer: 64 * 1024 * 1024,
  });
  const timedOut = Boolean(res.error && res.error.code === 'ETIMEDOUT');
  return {
    pass: res.status === 0 && !res.error,
    exitCode: res.status,
    timedOut,
    tail: redact(`${res.stdout || ''}${res.stderr || ''}`).slice(-1000),
  };
}

// { ok: true } or { ok: false, reason }. Never throws for a bad fixture, so
// the caller can drop it and carry on.
function checkReliability(fixture, env = process.env) {
  const scratch = createTempRoot();
  try {
    for (const [plant, label, expectPass] of [[false, 'unpatched', true], [true, 'planted', false]]) {
      for (let i = 1; i <= RELIABILITY_RUNS; i++) {
        const workDir = path.join(scratch, `${label}-${i}`);
        fs.mkdirSync(workDir);
        prepareWorkDir(fixture, workDir, { plant });
        const res = runHiddenTest(fixture, workDir, env);
        if (res.pass !== expectPass) {
          return {
            ok: false,
            reason: `hidden test ${expectPass ? 'fails' : 'passes'} on the ${label} tree (run ${i}/${RELIABILITY_RUNS}, exit ${res.exitCode}${res.timedOut ? ', timed out' : ''})`,
          };
        }
      }
    }
    return { ok: true };
  } catch (e) {
    return { ok: false, reason: e.message };
  } finally {
    fs.rmSync(scratch, { recursive: true, force: true });
  }
}

module.exports = {
  RELIABILITY_RUNS,
  loadFixture,
  listFixtureNames,
  prepareWorkDir,
  runHiddenTest,
  checkReliability,
};
