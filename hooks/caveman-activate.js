#!/usr/bin/env node
// caveman-kit — SessionStart and SubagentStart hook.
//
// Resolves the active mode, persists it to a flag file (read by the
// statusline badge and the UserPromptSubmit hook), and — unless mode is
// 'off' — injects the caveman ruleset filtered to that mode's row/examples
// from the preinstalled caveman skill's SKILL.md.
'use strict';

const fs = require('fs');
const path = require('path');
const { getDefaultMode, safeWriteFlag, readFlag, clearFlag, resolveFlagPath, ensureGitExclude } = require('./caveman-config');

let cwd = null;
let hookEventName = 'SessionStart';
try {
  if (!process.stdin.isTTY) {
    const raw = fs.readFileSync(0, 'utf8');
    if (raw) {
      const data = JSON.parse(raw);
      if (data && typeof data.cwd === 'string') cwd = data.cwd;
      if (data && typeof data.hook_event_name === 'string') hookEventName = data.hook_event_name;
    }
  }
} catch (e) { /* no/bad stdin → global flag fallback */ }

const { flagPath, repoRoot, globalFlag } = resolveFlagPath(cwd);

// The flag file — repo-scoped or global — is both the live session state and
// the persisted default (ADR 0004): every SessionStart honors it, including
// a real startup. Precedence (decision 6): repo flag file → global flag →
// CAVEMAN_DEFAULT_MODE / built-in 'full'. The write goes to whichever file
// the mode came from — a passive session never creates the repo flag file,
// even when a .claude/ dir already exists (only an explicit '/caveman <mode>'
// scopes the mode to the repo).
let mode = readFlag(flagPath);
let target = flagPath;
if (mode === null && flagPath !== globalFlag) {
  mode = readFlag(globalFlag);
  if (mode !== null) target = globalFlag;
}
if (mode === null) {
  mode = getDefaultMode();
  target = globalFlag;
}

if (mode === 'off') {
  clearFlag(target);
  process.exit(0);
}

safeWriteFlag(target, mode);
if (target === flagPath && repoRoot) ensureGitExclude(repoRoot);

if (!process.env.CLAUDE_PLUGIN_ROOT) {
  process.stderr.write('caveman-kit: CLAUDE_PLUGIN_ROOT not set, cannot locate the caveman skill\n');
  process.exit(0);
}

const skillPath = path.join(process.env.CLAUDE_PLUGIN_ROOT, 'skills', 'caveman', 'SKILL.md');
let skillContent;
try {
  skillContent = fs.readFileSync(skillPath, 'utf8');
} catch (e) {
  process.stderr.write(`caveman-kit: could not read ${skillPath}\n`);
  process.exit(0);
}

// Supplemental kit-authored examples (hooks/caveman-examples.md), covering
// topics the upstream skill doesn't demonstrate. Optional — a missing file
// just means no supplemental examples, never a hard failure.
let examplesContent = '';
try {
  examplesContent = fs.readFileSync(path.join(__dirname, 'caveman-examples.md'), 'utf8');
} catch (e) { /* no supplemental examples shipped/found */ }

// Strip YAML frontmatter, then keep only the active level's intensity-table
// row and example lines — the rest of the ruleset (rules, boundaries, etc.)
// applies at every level and is kept as-is. Supplemental examples are
// appended before filtering so the same mode-keyed bullet regex applies.
const body = skillContent.replace(/^---[\s\S]*?---\s*/, '') + (examplesContent ? '\n' + examplesContent : '');

// The kit no longer supports wenyan-* modes (ADR 0006), but the pinned
// upstream SKILL.md still advertises them in prose outside the table/bullet
// lines below (e.g. the "Switch:" line). Strip those mentions so the
// injected ruleset never advertises a mode caveman-mode-tracker.js rejects.
const dropUnsupportedMode = line => line.replace(/\|?wenyan-(lite|full|ultra)/gi, '');

const filtered = body.split('\n').reduce((acc, rawLine) => {
  const line = dropUnsupportedMode(rawLine);
  const tableRowMatch = line.match(/^\|\s*\*\*(\S+?)\*\*\s*\|/);
  if (tableRowMatch) {
    if (tableRowMatch[1] === mode) acc.push(line);
    return acc;
  }
  const exampleMatch = line.match(/^- (\S+?):\s/);
  if (exampleMatch) {
    if (exampleMatch[1] === mode) acc.push(line);
    return acc;
  }
  if (/wenyan/i.test(line)) return acc;
  acc.push(line);
  return acc;
}, []);

process.stdout.write(JSON.stringify({
  hookSpecificOutput: {
    hookEventName,
    additionalContext: `CAVEMAN MODE ACTIVE — level: ${mode}\n\n` + filtered.join('\n')
  }
}));
