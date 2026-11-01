#!/usr/bin/env node
'use strict';
// node bench/contract.js [--tag vX.Y.Z]
//
// Upstream contract check (ADR 0026 decision 3): installs the real caveman
// and ultracave skills at a release tag into a temporary HOME, runs the real
// SessionStart hook once per mode, and asserts which ruleset each mode gets.
// Maintainer-only (ADR 0008): no API calls, never copied by install.sh or
// update.sh, never run by CI. Needs the network (tag lookup, npx skills add).
//
// Exit 0: every assertion passed. Exit 1: upstream content broke the
// contract. Exit 2: the environment stopped the check before upstream content
// could be judged. Every exit path removes the temporary dir first.

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const rules = require('./lib/rules');

const KIT_DIR = path.resolve(__dirname, '..');
const SKILLS_SH = path.join(KIT_DIR, 'lib', 'skills.sh');
const HOOK = path.join(KIT_DIR, 'hooks', 'caveman-activate.js');
const SKILLS = ['caveman', 'ultracave'];
const MODES = ['lite', 'full', 'ultra'];

class Stop extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

// Scrubbed child environment: HOME is the temp dir, CLAUDE_CONFIG_DIR and
// CLAUDE_PLUGIN_ROOT both <temp>/.claude, every CAVEMAN_* removed. PATH and
// proxy variables pass through untouched.
function buildEnv(base, tempHome) {
  const env = {};
  for (const [k, v] of Object.entries(base)) {
    if (k.startsWith('CAVEMAN_') || k === 'CLAUDE_CONFIG_DIR' || k === 'CLAUDE_PLUGIN_ROOT') continue;
    env[k] = v;
  }
  const claudeDir = path.join(tempHome, '.claude');
  env.HOME = tempHome;
  env.CLAUDE_CONFIG_DIR = claudeDir;
  env.CLAUDE_PLUGIN_ROOT = claudeDir;
  return env;
}

// null when the install target and the plugin root are the same skills dir
// under tempRoot, else the reason.
function checkEnv(env, tempRoot) {
  if (!env.CLAUDE_CONFIG_DIR || !env.CLAUDE_PLUGIN_ROOT) return 'CLAUDE_CONFIG_DIR or CLAUDE_PLUGIN_ROOT unset';
  const target = path.resolve(env.CLAUDE_CONFIG_DIR, 'skills');
  const root = path.resolve(env.CLAUDE_PLUGIN_ROOT, 'skills');
  if (target !== root) return `install target ${target} differs from plugin root ${root}`;
  if (!target.startsWith(path.resolve(tempRoot) + path.sep)) return `install target ${target} is outside ${tempRoot}`;
  return null;
}

function parseArgs(argv) {
  const out = { tag: null };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--tag' && i + 1 < argv.length) out.tag = argv[++i];
    else if (argv[i].startsWith('--tag=')) out.tag = argv[i].slice(6);
    else throw new Stop(2, `unknown argument: ${argv[i]} (usage: node bench/contract.js [--tag vX.Y.Z])`);
  }
  return out;
}

// Runs a lib/skills.sh snippet through bash. The tag-lookup remote override
// (CAVEMAN_KIT_SKILL_REMOTE, for tests) is the one CAVEMAN_* value passed on,
// and only to the bash children that source lib/skills.sh.
function skillsSh(ctx, script, args) {
  const env = Object.assign({}, ctx.env);
  if (ctx.remote) env.CAVEMAN_KIT_SKILL_REMOTE = ctx.remote;
  return spawnSync('bash', ['-c', `. "$0"; ${script}`, SKILLS_SH, ...args], {
    env, cwd: ctx.cwd, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024,
  });
}

// Step 1 lookup. Returns the tag, or throws Stop(2) naming it.
function lookupTag(ctx, tag) {
  if (tag === null) {
    const r = skillsSh(ctx, 'latest_release_tag', []);
    const found = (r.stdout || '').trim();
    if (r.status !== 0 || !found) throw new Stop(2, 'tag lookup failed: upstream unreachable or no vX.Y.Z tags');
    return found;
  }
  const valid = skillsSh(ctx, 'valid_tag "$1"', [tag]);
  if (valid.status !== 0) throw new Stop(2, `--tag ${JSON.stringify(tag)} is not a vX.Y.Z tag`);
  const r = skillsSh(ctx, 'GIT_TERMINAL_PROMPT=0 git ls-remote --tags --refs "$SKILL_REMOTE" "refs/tags/$1"', [tag]);
  if (r.status !== 0) throw new Stop(2, `tag ${tag}: upstream remote unreachable`);
  if (!(r.stdout || '').includes(`refs/tags/${tag}`)) throw new Stop(2, `tag ${tag} not found upstream`);
  return tag;
}

const tail = (text, n = 10) => (text || '').trimEnd().split('\n').slice(-n).join('\n');

function install(ctx, tag) {
  const r = skillsSh(ctx, 'install_skills "$@"', [tag, ...SKILLS]);
  // Killed by a signal (Ctrl-C reaches the child while spawnSync blocks):
  // the environment stopped the check, not upstream.
  if (r.status === null) throw new Stop(2, `install_skills stopped by ${r.signal || r.error}`);
  const status = r.status;
  const skillsDir = path.join(ctx.env.CLAUDE_CONFIG_DIR, 'skills');
  const state = {};
  for (const s of SKILLS) {
    const file = path.join(skillsDir, s, 'SKILL.md');
    state[s] = { present: fs.existsSync(file), body: rules.readSkillBody(file) };
  }
  if (SKILLS.every(s => state[s].body !== null)) {
    if (r.status !== 0) console.error(`warning: install_skills exited ${status}; both skills usable, continuing`);
    return { caveman: state.caveman.body, ultracave: state.ultracave.body };
  }
  if (SKILLS.some(s => state[s].present)) {
    const bad = SKILLS.filter(s => state[s].body === null).map(s => `${s} (${state[s].present ? 'unusable' : 'missing'})`);
    throw new Stop(1, `after install_skills (exit ${status}) at ${tag}: ${bad.join(', ')}`);
  }
  if (r.status === 0) throw new Stop(1, `install_skills exited 0 at ${tag} but installed neither skill`);
  const errTail = tail(r.stderr);
  try {
    lookupTag(ctx, tag);
  } catch (e) {
    if (e instanceof Stop) throw new Stop(2, `install_skills exited ${status}, neither skill present, and the repeat tag lookup failed (network lost?)\n${errTail}`);
    throw e;
  }
  throw new Stop(1, `install_skills exited ${status} at ${tag}, neither skill present, upstream reachable\n${errTail}`);
}

// Step 4: real hook per mode with a fresh global flag. Returns { mode: context|null }.
function runHook(ctx, mode) {
  const flag = path.join(ctx.env.CLAUDE_CONFIG_DIR, '.caveman-active');
  fs.rmSync(flag, { force: true });
  fs.writeFileSync(flag, mode);
  const r = spawnSync(process.execPath, [HOOK], {
    input: JSON.stringify({ source: 'startup', cwd: ctx.cwd }),
    env: ctx.env, cwd: ctx.cwd, encoding: 'utf8', timeout: 30000,
  });
  try {
    const ctxText = JSON.parse(r.stdout).hookSpecificOutput.additionalContext;
    return typeof ctxText === 'string' && ctxText ? ctxText : null;
  } catch (e) {
    return null;
  }
}

function assertContexts(contexts, bodies) {
  const failures = [];
  for (const m of MODES) if (contexts[m] === null) failures.push(`${m}: hook produced no context`);
  let lines = null;
  try {
    lines = rules.distinguishingLines(bodies.caveman, bodies.ultracave);
  } catch (e) {
    failures.push(e.message);
  }
  if (lines) {
    for (const m of MODES) {
      const text = contexts[m];
      if (text === null) continue;
      const [want, other] = m === 'ultra' ? ['ultracave', 'caveman'] : ['caveman', 'ultracave'];
      const header = `CAVEMAN MODE ACTIVE — level: ${m} (rules: ${want})`;
      if (text.split('\n')[0] !== header) failures.push(`${m}: header is ${JSON.stringify(text.split('\n')[0])}, want ${JSON.stringify(header)}`);
      // Whole trimmed lines, as distinguishingLine compares them.
      const has = new Set(text.split(/\r?\n/).map(l => l.trim()));
      if (!has.has(lines[want])) failures.push(`${m}: missing ${want} line ${JSON.stringify(lines[want])}`);
      if (has.has(lines[other])) failures.push(`${m}: contains ${other} line ${JSON.stringify(lines[other])}`);
    }
  }
  return failures;
}

function main(argv, tempRoot) {
  const args = parseArgs(argv);
  const tempHome = path.join(tempRoot, 'home');
  const cwd = path.join(tempRoot, 'cwd');
  fs.mkdirSync(path.join(tempHome, '.claude'), { recursive: true });
  fs.mkdirSync(cwd);
  const ctx = { env: buildEnv(process.env, tempHome), cwd, remote: process.env.CAVEMAN_KIT_SKILL_REMOTE || null };
  const bad = checkEnv(ctx.env, tempRoot);
  if (bad) throw new Stop(2, bad);

  const tag = lookupTag(ctx, args.tag);
  console.log(`tag: ${tag}`);

  const probe = spawnSync('npx', ['skills', '--version'], { env: ctx.env, cwd, encoding: 'utf8' });
  if (probe.error || probe.status !== 0) {
    throw new Stop(2, `npx skills --version failed: ${probe.error ? probe.error.message : `exit ${probe.status}`}`);
  }

  const bodies = install(ctx, tag);
  const contexts = {};
  for (const m of MODES) contexts[m] = runHook(ctx, m);
  const failures = assertContexts(contexts, bodies);
  if (failures.length) throw new Stop(1, failures.join('\n'));
  console.log(`contract ok at ${tag}: ultra gets ultracave, lite and full get caveman`);
  return 0;
}

if (require.main === module) {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'caveman-contract-'));
  const cleanup = () => fs.rmSync(tempRoot, { recursive: true, force: true });
  for (const sig of ['SIGINT', 'SIGTERM', 'SIGHUP']) {
    process.on(sig, () => { cleanup(); process.exit(2); });
  }
  let code;
  try {
    code = main(process.argv.slice(2), tempRoot);
  } catch (e) {
    if (e instanceof Stop) {
      console.error(`contract ${e.code === 1 ? 'broken' : 'check stopped'}: ${e.message}`);
      code = e.code;
    } else {
      console.error(`contract check stopped: ${e && e.stack ? e.stack : e}`);
      code = 2;
    }
  } finally {
    cleanup();
  }
  process.exit(code);
}

module.exports = { buildEnv, checkEnv, parseArgs };
