#!/usr/bin/env node
// caveman-kit — UserPromptSubmit hook.
//
// Detects /caveman mode-change commands (and a few natural-language
// equivalents) in the prompt, updates the flag file, and re-asserts a short
// reminder every turn so caveman mode doesn't drift after the SessionStart
// ruleset scrolls out of a long session's attention.
'use strict';

const { getDefaultMode, safeWriteFlag, readFlag, clearFlag, resolveFlagPath, ensureGitExclude } = require('./caveman-config');
const { parseModeChange } = require('./caveman-parse');

let input = '';
process.stdin.on('data', chunk => { input += chunk; });
// A broken pipe/parent crash emits 'error'; without a listener Node throws it
// as uncaught and the hook exits non-zero. Hooks must always exit 0.
process.stdin.on('error', () => process.exit(0));
process.stdin.on('end', () => {
  try {
    const data = JSON.parse(input);
    const { flagPath, repoRoot } = resolveFlagPath(typeof data.cwd === 'string' ? data.cwd : null);
    let prompt = (data.prompt || '').trim().toLowerCase().replace(/\s+/g, ' ');

    // Claude Code delivers slash commands to this hook as an envelope, not
    // the literal text:
    //   <command-name>/caveman</command-name><command-args>ultra</command-args>
    // Reconstruct '/caveman ultra' for our own command; leave any other
    // command's envelope untouched (and skip mode-change parsing for it, so
    // its own arguments can't misfire our triggers) while still falling
    // through to the reinforcement check below.
    let skipParse = false;
    const envName = /<command-name>\s*([^<\s]+)\s*<\/command-name>/.exec(prompt);
    if (envName) {
      if (envName[1] === '/caveman') {
        const envArgs = /<command-args>\s*([^<]*?)\s*<\/command-args>/.exec(prompt);
        const args = envArgs ? envArgs[1].trim() : '';
        prompt = args ? envName[1] + ' ' + args : envName[1];
      } else {
        skipParse = true;
      }
    }

    const change = skipParse ? null : parseModeChange(prompt);
    if (change && change.action === 'set') {
      safeWriteFlag(flagPath, change.mode);
      if (repoRoot) ensureGitExclude(repoRoot);
    } else if (change && change.action === 'clear') {
      clearFlag(flagPath);
    }

    // readFlag enforces symlink-safety + size cap + mode whitelist — if the
    // flag is missing, corrupted, or tampered with, this returns null and we
    // emit nothing rather than injecting untrusted bytes into model context.
    const activeMode = readFlag(flagPath);
    if (activeMode && getDefaultMode() !== 'off') {
      process.stdout.write(JSON.stringify({
        hookSpecificOutput: {
          hookEventName: 'UserPromptSubmit',
          additionalContext: `CAVEMAN MODE ACTIVE (${activeMode}) — session ruleset applies.`
        }
      }));
    }
  } catch (e) {
    // silent fail — hooks must always exit 0
  }
});
