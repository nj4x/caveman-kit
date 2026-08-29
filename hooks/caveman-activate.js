#!/usr/bin/env node
// caveman-kit — SessionStart hook.
//
// Resolves the active mode, persists it to a flag file (read by the
// statusline badge and the UserPromptSubmit hook), and — unless mode is
// 'off' — injects the caveman ruleset filtered to that mode's row/examples
// from the preinstalled caveman skill's SKILL.md.
'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');
const { getDefaultMode, safeWriteFlag, readFlag, clearFlag } = require('./caveman-config');

const claudeDir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
const flagPath = path.join(claudeDir, '.caveman-active');

// SessionStart re-fires mid-conversation (resume, /clear, compaction), not
// just at true session start. Only a real 'startup' resets to the configured
// default; other sources preserve whatever mode the user already switched to.
let source = 'startup';
try {
  if (!process.stdin.isTTY) {
    const raw = fs.readFileSync(0, 'utf8');
    if (raw) {
      const data = JSON.parse(raw);
      if (data && typeof data.source === 'string') source = data.source;
    }
  }
} catch (e) { /* no/bad stdin → treat as startup */ }

let mode = getDefaultMode();
if (source !== 'startup') {
  const existing = readFlag(flagPath);
  if (existing) mode = existing;
}

if (mode === 'off') {
  clearFlag(flagPath);
  process.exit(0);
}

safeWriteFlag(flagPath, mode);

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

// Strip YAML frontmatter, then keep only the active level's intensity-table
// row and example lines — the rest of the ruleset (rules, boundaries, etc.)
// applies at every level and is kept as-is.
const body = skillContent.replace(/^---[\s\S]*?---\s*/, '');

const filtered = body.split('\n').reduce((acc, line) => {
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
  acc.push(line);
  return acc;
}, []);

process.stdout.write(`CAVEMAN MODE ACTIVE — level: ${mode}\n\n` + filtered.join('\n'));
