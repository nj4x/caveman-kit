#!/usr/bin/env node
// caveman-kit — shared config + safe flag-file helpers.
'use strict';

const fs = require('fs');
const path = require('path');

// Matches the intensity levels defined in the preinstalled caveman skill's
// SKILL.md (lite/full/ultra/wenyan-lite/wenyan-full/wenyan-ultra), plus 'off'.
const VALID_MODES = ['off', 'lite', 'full', 'ultra', 'wenyan-lite', 'wenyan-full', 'wenyan-ultra'];

function getDefaultMode() {
  const envMode = process.env.CAVEMAN_DEFAULT_MODE;
  if (envMode && VALID_MODES.includes(envMode.toLowerCase())) return envMode.toLowerCase();
  return 'full';
}

// Refuses a symlink at the flag path — defends against a local attacker
// pointing the flag at a sensitive file that a reader (statusline, the
// UserPromptSubmit hook) would then read and act on. Atomic write via
// temp file + rename.
function safeWriteFlag(flagPath, content) {
  try {
    const dir = path.dirname(flagPath);
    fs.mkdirSync(dir, { recursive: true });
    try {
      if (fs.lstatSync(flagPath).isSymbolicLink()) return;
    } catch (e) {
      if (e.code !== 'ENOENT') return;
    }
    const tmp = path.join(dir, `.caveman-active.${process.pid}.${Date.now()}`);
    fs.writeFileSync(tmp, String(content), { mode: 0o600 });
    fs.renameSync(tmp, flagPath);
  } catch (e) {
    // best-effort — the flag is not load-bearing for correctness
  }
}

// Longest valid mode is "wenyan-ultra" (12 bytes); 16 leaves slack without
// letting the flag be used to smuggle arbitrary content into context.
const MAX_FLAG_BYTES = 16;

function readFlag(flagPath) {
  try {
    const st = fs.lstatSync(flagPath);
    if (st.isSymbolicLink() || !st.isFile() || st.size > MAX_FLAG_BYTES) return null;
    const raw = fs.readFileSync(flagPath, 'utf8').trim().toLowerCase();
    return VALID_MODES.includes(raw) ? raw : null;
  } catch (e) {
    return null;
  }
}

function clearFlag(flagPath) {
  try { fs.unlinkSync(flagPath); } catch (e) { /* already gone */ }
}

module.exports = { VALID_MODES, getDefaultMode, safeWriteFlag, readFlag, clearFlag };
