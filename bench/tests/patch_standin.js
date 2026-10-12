// Builds an offline stand-in for a fixture's source repo from its plant patch.
//
//   node patch_standin.js <plant.patch> <out-dir>
//
// For each file the patch touches, writes <out-dir>/pre/<file> holding every
// hunk's pre-image (context + removed lines) and <out-dir>/post/<file> holding
// the matching post-image (context + added lines). Hunks are separated by a
// filler line so `git apply` must locate each hunk by its context, as it does
// against the real file at a different offset. Prints the touched paths, one
// per line. Exits 1 on a patch with no file or no hunk.
'use strict';

const fs = require('fs');
const path = require('path');

const [patchFile, outDir] = process.argv.slice(2);
const files = new Map();
let current = null;
let inHunk = false;
for (const line of fs.readFileSync(patchFile, 'utf8').split('\n')) {
  if (line.startsWith('diff --git ')) { current = null; inHunk = false; continue; }
  if (line.startsWith('+++ ') && !inHunk) {
    const name = line.slice(4).replace(/^b\//, '');
    current = { pre: [], post: [], hunks: 0 };
    files.set(name, current);
    continue;
  }
  if (line.startsWith('--- ') && !inHunk) continue;
  if (line.startsWith('@@ ')) {
    if (!current) { console.error(`hunk before file header: ${line}`); process.exit(1); }
    if (current.hunks > 0) { current.pre.push('# stand-in filler'); current.post.push('# stand-in filler'); }
    current.hunks++;
    inHunk = true;
    continue;
  }
  if (!inHunk || !current || line.startsWith('\\')) continue;
  const tag = line[0];
  const body = line.slice(1);
  if (tag === ' ') { current.pre.push(body); current.post.push(body); }
  else if (tag === '-') current.pre.push(body);
  else if (tag === '+') current.post.push(body);
}
if (files.size === 0) { console.error('patch touches no file'); process.exit(1); }
for (const [name, f] of files) {
  if (f.hunks === 0) { console.error(`no hunk for ${name}`); process.exit(1); }
  for (const side of ['pre', 'post']) {
    const target = path.join(outDir, side, name);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, `${f[side].join('\n')}\n`);
  }
  console.log(name);
}
