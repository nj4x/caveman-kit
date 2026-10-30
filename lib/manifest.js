#!/usr/bin/env node
// caveman-kit — tiny manifest.json accessor for update.sh (no jq dependency).
//   manifest.js get <file> <key>         → "absent" or the JSON value
//   manifest.js set <file> <key> <json>  → sets key to the parsed JSON value
//   manifest.js setstr <file> <key> <s>  → sets key to the string s (no JSON parsing)
//   manifest.js unset <file> <key>       → removes key
// Exit 1 on any read/parse/write failure.
'use strict';

const fs = require('fs');

const [cmd, file, key, raw] = process.argv.slice(2);
if (!cmd || !file || !key) {
  console.error('usage: manifest.js get|set|setstr|unset <file> <key> [value]');
  process.exit(1);
}

let m;
try {
  m = JSON.parse(fs.readFileSync(file, 'utf8'));
} catch (e) {
  console.error(`error: cannot read ${file}: ${e.message}`);
  process.exit(1);
}
if (m === null || typeof m !== 'object' || Array.isArray(m)) {
  console.error(`error: ${file} is not a JSON object`);
  process.exit(1);
}

if (cmd === 'get') {
  console.log(Object.prototype.hasOwnProperty.call(m, key) ? JSON.stringify(m[key]) : 'absent');
  process.exit(0);
}

if (cmd === 'set') {
  try { m[key] = JSON.parse(raw); } catch (e) { console.error(`error: bad JSON value: ${raw}`); process.exit(1); }
} else if (cmd === 'setstr') {
  if (raw === undefined) { console.error('error: setstr needs a value'); process.exit(1); }
  m[key] = raw;
} else if (cmd === 'unset') {
  delete m[key];
} else {
  console.error(`error: unknown command ${cmd}`);
  process.exit(1);
}

// Write to a temp file and rename, so a crash never leaves a truncated
// manifest (uninstall depends on it).
try {
  const tmp = `${file}.tmp-${process.pid}`;
  fs.writeFileSync(tmp, JSON.stringify(m, null, 2) + '\n');
  fs.renameSync(tmp, file);
} catch (e) {
  console.error(`error: cannot write ${file}: ${e.message}`);
  process.exit(1);
}
