'use strict';
// Distinguishing lines between the caveman and ultracave skill bodies
// (ADR 0026 decisions 3 and 4). Shared by bench/contract.js and the bench
// preflight so the two checks cannot drift apart.
//
// The skip list mirrors what hooks/caveman-activate.js rewrites or drops
// (filterForMode, dropUnsupportedMode): intensity-table rows, `- <mode>:`
// bullets and anything mentioning wenyan. A change there must update
// skippedByHook here, or a check may pick a line the hook never injects.

const fs = require('fs');

// Same whole-line fences as the hook's FRONTMATTER and lib/skills.sh
// ultracave_present.
const FRONTMATTER = /^---[ \t]*\r?\n[\s\S]*?\r?\n---[ \t]*(?:\r?\n|$)\s*/;
const OPENING_FENCE = /^---[ \t]*\r?\n/;

// Body of a skill file after frontmatter, or null when the skill is not
// usable: unreadable, unterminated frontmatter, or an empty body (the
// ultracave_present rule of ADR 0020 decision 1, applied to any skill).
function readSkillBody(file) {
  let raw;
  try {
    raw = fs.readFileSync(file, 'utf8');
  } catch (e) {
    return null;
  }
  if (OPENING_FENCE.test(raw) && !FRONTMATTER.test(raw)) return null;
  const body = raw.replace(FRONTMATTER, '');
  return body.trim() ? body : null;
}

function skippedByHook(line) {
  if (/^\|\s*\*\*(\S+?)\*\*\s*\|/.test(line)) return true;
  if (/^- (\S+?):\s/.test(line)) return true;
  return /wenyan/i.test(line);
}

const lines = body => body.split(/\r?\n/).map(l => l.trim());

// First non-empty, non-skipped line of `body` that does not occur in
// `otherBody` (lines compared trimmed). null when there is none.
function distinguishingLine(body, otherBody) {
  const other = new Set(lines(otherBody));
  for (const line of lines(body)) {
    if (!line || skippedByHook(line)) continue;
    if (!other.has(line)) return line;
  }
  return null;
}

// { caveman, ultracave } distinguishing lines. Throws, naming each skill
// without one, when either is missing.
function distinguishingLines(cavemanBody, ultracaveBody) {
  const result = {
    caveman: distinguishingLine(cavemanBody, ultracaveBody),
    ultracave: distinguishingLine(ultracaveBody, cavemanBody),
  };
  const missing = Object.keys(result).filter(k => result[k] === null);
  if (missing.length) {
    throw new Error(`no distinguishing line for: ${missing.join(', ')}`);
  }
  return result;
}

module.exports = { readSkillBody, distinguishingLine, distinguishingLines, skippedByHook };
