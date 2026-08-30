#!/usr/bin/env node
// caveman-kit — inserts a caveman-mode badge block into an existing
// statusline.sh, right before its last output line, wrapped in sentinel
// comments. Idempotent: skips if the block is already present. Uninstall
// does not use this file's inverse — it restores statusline.sh from the
// backup copy install.sh made, which is simpler and byte-exact.
'use strict';

const fs = require('fs');

const BEGIN = '# CAVEMAN-KIT BEGIN';
const END = '# CAVEMAN-KIT END';

const BLOCK = [
  BEGIN,
  'CAVEMAN_FLAG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.caveman-active"',
  '# Repo-scoped flag wins when the repo root has a .claude/ dir (ADR 0004).',
  'CAVEMAN_DIR="$PWD"',
  'while [ "$CAVEMAN_DIR" != "/" ]; do',
  '  if [ -e "$CAVEMAN_DIR/.git" ]; then',
  '    if [ -d "$CAVEMAN_DIR/.claude" ]; then',
  '      CAVEMAN_FLAG="$CAVEMAN_DIR/.claude/.caveman-mode"',
  '    fi',
  '    break',
  '  fi',
  '  CAVEMAN_DIR="$(dirname "$CAVEMAN_DIR")"',
  'done',
  'if [ -f "$CAVEMAN_FLAG" ] && [ ! -L "$CAVEMAN_FLAG" ]; then',
  "  CAVEMAN_MODE=$(head -c 16 \"$CAVEMAN_FLAG\" 2>/dev/null | tr -d '\\n\\r' | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')",
  '  case "$CAVEMAN_MODE" in',
  '    lite|full|ultra|wenyan-lite|wenyan-full|wenyan-ultra)',
  '      if [ "$CAVEMAN_MODE" = "full" ]; then',
  "        printf '[CAVEMAN] '",
  '      else',
  "        CAVEMAN_SUFFIX=$(printf '%s' \"$CAVEMAN_MODE\" | tr '[:lower:]' '[:upper:]')",
  "        printf '[CAVEMAN:%s] ' \"$CAVEMAN_SUFFIX\"",
  '      fi',
  '      ;;',
  '  esac',
  'fi',
  END
].join('\n');

const filePath = process.argv[2];
if (!filePath) {
  console.error('usage: statusline-patch.js <statusline.sh>');
  process.exit(1);
}

const content = fs.readFileSync(filePath, 'utf8');

if (content.includes(BEGIN)) {
  console.log('statusline already patched, skipping');
  process.exit(0);
}

const lines = content.split('\n');
// Skip trailing blank lines to find the real last output line.
let lastIdx = lines.length - 1;
while (lastIdx > 0 && lines[lastIdx].trim() === '') lastIdx--;

const before = lines.slice(0, lastIdx);
const lastLine = lines[lastIdx];
const after = lines.slice(lastIdx + 1);

const patched = [...before, BLOCK, lastLine, ...after].join('\n');
fs.writeFileSync(filePath, patched);
fs.chmodSync(filePath, 0o755);
console.log('statusline patched');
