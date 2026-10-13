// caveman-kit bench — the `ultra-no-focus` arm's patched hooks (ADR 0008
// decision 3, spec #1 user story 9).
//
// Measures commit e11e665 (the focus directive in the per-turn reminder)
// without a benchmark-only switch in shipped code: the kit's hooks/ dir is
// copied into a temp dir and the focus clause is removed from the reminder in
// the copied caveman-mode-tracker.js. The shipped scripts are only read.
//
// The focus clause is the text after FOCUS_ANCHOR up to the end of the
// reminder's template literal. If it is missing, the patch throws, so the arm
// can never silently equal `ultra`.
'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { BenchError } = require('./isolation');

const TRACKER = 'caveman-mode-tracker.js';
const FOCUS_ANCHOR = '— session ruleset applies.';

// Returns { start, end, clause }: the clause spans tracker[start, end).
function findFocusClause(source, trackerPath) {
  const fail = why => {
    throw new BenchError(
      `ultra-no-focus: focus clause not found in ${trackerPath} (${why}); ` +
      'refusing to run an arm identical to ultra'
    );
  };
  const at = source.indexOf(FOCUS_ANCHOR);
  if (at < 0) fail(`no ${JSON.stringify(FOCUS_ANCHOR)}`);
  if (source.indexOf(FOCUS_ANCHOR, at + 1) >= 0) fail(`${JSON.stringify(FOCUS_ANCHOR)} appears more than once`);
  const start = at + FOCUS_ANCHOR.length;
  const end = source.indexOf('`', start);
  if (end < 0) fail('reminder template literal does not close');
  const clause = source.slice(start, end);
  if (!clause.trim()) fail(`nothing follows ${JSON.stringify(FOCUS_ANCHOR)} in the reminder`);
  return { start, end, clause: clause.trim() };
}

// Copies srcHooksDir to <root>/hooks-no-focus and strips the focus clause
// from the copied tracker. Returns { hooksDir, clause }; throws BenchError
// when the clause is absent. srcHooksDir is never written.
function patchNoFocus(srcHooksDir, root) {
  const srcTracker = path.join(srcHooksDir, TRACKER);
  let source;
  try {
    source = fs.readFileSync(srcTracker, 'utf8');
  } catch (e) {
    throw new BenchError(`ultra-no-focus: cannot read ${srcTracker}: ${e.message}`);
  }
  const { start, end, clause } = findFocusClause(source, srcTracker);
  const hooksDir = path.join(root, 'hooks-no-focus');
  fs.cpSync(srcHooksDir, hooksDir, { recursive: true, dereference: true });
  const dest = path.join(hooksDir, TRACKER);
  fs.rmSync(dest, { force: true });
  fs.writeFileSync(dest, source.slice(0, start) + source.slice(end), { mode: 0o600 });
  return { hooksDir, clause };
}

// Runs an arm's UserPromptSubmit hook once, as claude would, and returns the
// injected reminder. Checks it still carries FOCUS_ANCHOR and lacks clause.
function checkReminder(armConfig, clause) {
  const res = spawnSync('/bin/sh', ['-c', armConfig.userPromptSubmitCommand], {
    input: JSON.stringify({ session_id: 'bench-preflight', hook_event_name: 'UserPromptSubmit', prompt: 'hello', cwd: armConfig.workDir }),
    env: armConfig.env, cwd: armConfig.workDir, encoding: 'utf8', timeout: 30000,
  });
  const fail = msg => { throw new BenchError(`preflight ${armConfig.name}: ${msg}`); };
  if (res.error || res.status !== 0) fail(`reminder hook failed: ${res.error ? res.error.message : `exit ${res.status}`}`);
  let reminder = '';
  try {
    reminder = JSON.parse(res.stdout).hookSpecificOutput.additionalContext || '';
  } catch (e) {
    fail(`reminder hook output is not JSON: ${(res.stdout || '').slice(0, 200)}`);
  }
  if (!reminder.includes(FOCUS_ANCHOR)) fail(`reminder lacks ${JSON.stringify(FOCUS_ANCHOR)}: ${reminder}`);
  if (reminder.includes(clause)) fail('reminder still contains the focus clause');
  return reminder;
}

module.exports = { FOCUS_ANCHOR, findFocusClause, patchNoFocus, checkReminder };
