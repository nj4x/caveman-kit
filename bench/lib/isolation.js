// caveman-kit bench — config isolation (ADR 0008 decisions 3 and 4).
//
// Builds one throwaway Claude Code config dir per arm: a settings.json that
// registers only the kit's three hooks, a seeded mode flag, a private copy of
// the caveman SKILL.md the hooks read through CLAUDE_PLUGIN_ROOT, and auth.
// Nothing from the user's real config dir (CLAUDE.md, plugins, settings,
// other hooks) reaches the arm; the real dir path is never handed to claude.
//
// Every dir lives under one temp root (mode 0700) that is removed on exit.
// Callers that handle signals call cleanupTempRoots() before exiting.
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const VALID_MODES = ['off', 'lite', 'full', 'ultra'];
const ACTIVATE = 'caveman-activate.js';
const TRACKER = 'caveman-mode-tracker.js';
const CREDENTIALS_FILE = '.credentials.json';

class BenchError extends Error {}

// --- temp root lifecycle -------------------------------------------------

const tempRoots = new Set();
let exitHookInstalled = false;

function cleanupTempRoots() {
  for (const root of tempRoots) {
    try { fs.rmSync(root, { recursive: true, force: true }); } catch (e) { /* best-effort */ }
    tempRoots.delete(root);
  }
}

// mkdtemp creates the dir with mode 0700; chmod again in case of an odd umask.
function createTempRoot() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'caveman-bench-'));
  fs.chmodSync(root, 0o700);
  tempRoots.add(root);
  if (!exitHookInstalled) {
    process.on('exit', cleanupTempRoots);
    exitHookInstalled = true;
  }
  return root;
}

let defaultRoot = null;
function getDefaultRoot() {
  if (!defaultRoot || !tempRoots.has(defaultRoot)) defaultRoot = createTempRoot();
  return defaultRoot;
}

// --- resolution helpers --------------------------------------------------

function realConfigDir(env) {
  return env.CLAUDE_CONFIG_DIR || path.join(env.HOME || os.homedir(), '.claude');
}

// Auth order (spec #1): ANTHROPIC_API_KEY, then a readable credentials file
// in the real config dir, else a hard error naming both options.
function resolveAuth(env) {
  if (env.ANTHROPIC_API_KEY) return { kind: 'api-key' };
  const credentials = path.join(realConfigDir(env), CREDENTIALS_FILE);
  try {
    fs.accessSync(credentials, fs.constants.R_OK);
    if (fs.statSync(credentials).isFile()) return { kind: 'credentials', path: credentials };
  } catch (e) { /* fall through */ }
  throw new BenchError(
    'no auth: set ANTHROPIC_API_KEY, or provide a readable credentials file at ' +
    `${credentials} (copied into each isolated config dir)`
  );
}

function skillFile(root) {
  return path.join(root, 'skills', 'caveman', 'SKILL.md');
}

// Directory holding skills/caveman/SKILL.md, in order: CAVEMAN_BENCH_SKILL_ROOT,
// the kit manifest's pluginRoot, the real config dir. The file is copied into
// each arm, so this path itself is never passed to claude.
function resolveSkillRoot(env) {
  const candidates = [];
  if (env.CAVEMAN_BENCH_SKILL_ROOT) candidates.push(env.CAVEMAN_BENCH_SKILL_ROOT);
  try {
    const manifest = path.join(env.HOME || os.homedir(), '.caveman-kit', 'manifest.json');
    const root = JSON.parse(fs.readFileSync(manifest, 'utf8')).pluginRoot;
    if (typeof root === 'string' && root) candidates.push(root);
  } catch (e) { /* no manifest */ }
  candidates.push(realConfigDir(env));
  for (const root of candidates) {
    try {
      fs.accessSync(skillFile(root), fs.constants.R_OK);
      return root;
    } catch (e) { /* next */ }
  }
  throw new BenchError(
    `caveman SKILL.md not found under: ${candidates.map(skillFile).join(', ')} ` +
    '(set CAVEMAN_BENCH_SKILL_ROOT to a dir containing skills/caveman/SKILL.md)'
  );
}

function shellQuote(s) {
  return `'${String(s).replace(/'/g, `'\\''`)}'`;
}

function hookCommand(pluginRoot, hooksDir, script) {
  return `CLAUDE_PLUGIN_ROOT=${shellQuote(pluginRoot)} node ${shellQuote(path.join(hooksDir, script))}`;
}

// --- arm config ----------------------------------------------------------

let armCounter = 0;

// arm: { name, mode, env? }. Options:
//   kitDir    kit checkout whose hooks/ are measured (required unless hooksDir)
//   env       base environment (default process.env)
//   hooksDir  hook scripts dir, overriding <kitDir>/hooks (e.g. a patched copy)
//   root      parent dir (default: a module-managed 0700 temp root)
//   auth      result of resolveAuth (default: resolved from env)
//   skillRoot result of resolveSkillRoot (default: resolved from env)
function buildArmConfig(arm, options = {}) {
  if (!arm || typeof arm.name !== 'string' || !/^[a-z0-9][a-z0-9-]*$/.test(arm.name)) {
    throw new BenchError(`invalid arm name: ${arm && arm.name}`);
  }
  if (!VALID_MODES.includes(arm.mode)) throw new BenchError(`arm ${arm.name}: invalid mode ${arm.mode}`);
  const baseEnv = options.env || process.env;
  const hooksDir = path.resolve(options.hooksDir || path.join(options.kitDir || '', 'hooks'));
  if (!options.hooksDir && !options.kitDir) throw new BenchError('buildArmConfig needs kitDir or hooksDir');
  for (const script of [ACTIVATE, TRACKER]) {
    if (!fs.existsSync(path.join(hooksDir, script))) {
      throw new BenchError(`hook script missing: ${path.join(hooksDir, script)}`);
    }
  }
  const auth = options.auth || resolveAuth(baseEnv);
  const skillRoot = options.skillRoot || resolveSkillRoot(baseEnv);

  const parent = options.root || getDefaultRoot();
  armCounter += 1;
  const dir = path.join(parent, `${arm.name}.${process.pid}.${armCounter}`);
  const configDir = path.join(dir, 'config');
  const pluginRoot = path.join(dir, 'plugin');
  const workDir = path.join(dir, 'work');
  for (const d of [dir, configDir, workDir, path.dirname(skillFile(pluginRoot))]) {
    fs.mkdirSync(d, { recursive: true, mode: 0o700 });
  }
  fs.copyFileSync(skillFile(skillRoot), skillFile(pluginRoot));

  const activateCmd = hookCommand(pluginRoot, hooksDir, ACTIVATE);
  const trackerCmd = hookCommand(pluginRoot, hooksDir, TRACKER);
  const settings = {
    hooks: {
      SessionStart: [{ hooks: [{ type: 'command', command: activateCmd }] }],
      SubagentStart: [{ hooks: [{ type: 'command', command: activateCmd }] }],
      UserPromptSubmit: [{ hooks: [{ type: 'command', command: trackerCmd }] }],
    },
  };
  const settingsPath = path.join(configDir, 'settings.json');
  fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + '\n', { mode: 0o600 });

  const flagPath = path.join(configDir, '.caveman-active');
  fs.writeFileSync(flagPath, arm.mode, { mode: 0o600 });

  if (auth.kind === 'credentials') {
    fs.copyFileSync(auth.path, path.join(configDir, CREDENTIALS_FILE));
    fs.chmodSync(path.join(configDir, CREDENTIALS_FILE), 0o600);
  }

  // The user's own caveman/plugin settings must not leak in: drop every
  // CAVEMAN_* and the config/plugin pointers, then apply the arm's own.
  const env = {};
  for (const [k, v] of Object.entries(baseEnv)) {
    if (k.startsWith('CAVEMAN_') || k === 'CLAUDE_CONFIG_DIR' || k === 'CLAUDE_PLUGIN_ROOT') continue;
    env[k] = v;
  }
  if (auth.kind !== 'api-key') delete env.ANTHROPIC_API_KEY;
  Object.assign(env, arm.env || {});
  // Bare arms: hooks run but inject nothing, even after SessionStart clears
  // the 'off' flag (the hook then falls back to CAVEMAN_DEFAULT_MODE).
  if (arm.mode === 'off') env.CAVEMAN_DEFAULT_MODE = 'off';
  env.CLAUDE_CONFIG_DIR = configDir;
  env.CLAUDE_PLUGIN_ROOT = pluginRoot;

  return {
    arm, name: arm.name, mode: arm.mode,
    dir, configDir, pluginRoot, workDir, hooksDir, settingsPath, flagPath,
    sessionStartCommand: activateCmd, userPromptSubmitCommand: trackerCmd, env,
  };
}

function disposeArmConfig(armConfig) {
  try { fs.rmSync(armConfig.dir, { recursive: true, force: true }); } catch (e) { /* best-effort */ }
}

// --- preflight -----------------------------------------------------------

function asList(v) {
  if (v === undefined || v === null) return [];
  return Array.isArray(v) ? v : [v];
}

// Runs the arm's SessionStart hook command once, exactly as claude would,
// and checks the injected context. Mode arms must inject something; 'off'
// arms must inject nothing; a mode arm's context must name its own level.
// requireText: string(s) the context must contain.
// forbidText: string(s) it must not contain. The seeded flag is restored
// afterwards, since the hook rewrites (or, for 'off', deletes) it.
// Returns { context }; throws BenchError on any failure.
function preflight(armConfig, options = {}) {
  const input = JSON.stringify({
    session_id: 'bench-preflight',
    hook_event_name: 'SessionStart',
    source: 'startup',
    cwd: armConfig.workDir,
  });
  const res = spawnSync('/bin/sh', ['-c', armConfig.sessionStartCommand], {
    input, env: armConfig.env, cwd: armConfig.workDir, encoding: 'utf8', timeout: 30000,
  });
  fs.writeFileSync(armConfig.flagPath, armConfig.mode, { mode: 0o600 });
  const fail = msg => { throw new BenchError(`preflight ${armConfig.name}: ${msg}`); };
  if (res.error) fail(`hook did not run: ${res.error.message}`);
  if (res.status !== 0) fail(`hook exited ${res.status}: ${(res.stderr || '').trim()}`);

  let context = '';
  const out = (res.stdout || '').trim();
  if (out) {
    try {
      const parsed = JSON.parse(out);
      context = (parsed.hookSpecificOutput && parsed.hookSpecificOutput.additionalContext) || '';
    } catch (e) {
      fail(`hook output is not JSON: ${out.slice(0, 200)}`);
    }
  }
  const stderr = (res.stderr || '').trim();
  if (armConfig.mode === 'off') {
    if (context) fail('bare arm injected context; expected none');
  } else if (!context.trim()) {
    fail(`mode ${armConfig.mode} injected empty context${stderr ? ` (hook stderr: ${stderr})` : ''}`);
  } else if (!context.includes(`level: ${armConfig.mode}`)) {
    // The seeded flag must be what the hook resolved (e.g. not shadowed by a
    // repo-scoped flag above the temp dir).
    fail(`context is not for mode ${armConfig.mode}: ${context.split('\n')[0]}`);
  }
  for (const text of asList(options.requireText)) {
    if (!context.includes(text)) fail(`context lacks required text: ${JSON.stringify(text)}`);
  }
  for (const text of asList(options.forbidText)) {
    if (context.includes(text)) fail(`context contains forbidden text: ${JSON.stringify(text)}`);
  }
  return { context };
}

module.exports = {
  BenchError,
  VALID_MODES,
  createTempRoot,
  getDefaultRoot,
  cleanupTempRoots,
  realConfigDir,
  resolveAuth,
  resolveSkillRoot,
  buildArmConfig,
  disposeArmConfig,
  preflight,
  shellQuote,
};
