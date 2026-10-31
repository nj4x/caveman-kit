// Runs plugins/caveman-badge/hooks/badge.mjs against the real file system
// (lstat for stat, as the JS hooks do) and prints the resolved mode, or none.
// usage: node badge-run.mjs <home> <cwd>
import { lstatSync, statSync, readFileSync } from 'node:fs';
import { resolveMode } from '../../plugins/caveman-badge/hooks/badge.mjs';

const [home, cwd] = process.argv.slice(2);
const fs = {
  stat: async path => {
    try {
      const own = lstatSync(path);
      let kind = 'other';
      if (own.isSymbolicLink()) {
        try { kind = statSync(path).isDirectory() ? 'dir' : 'file'; } catch (e) { return null; }
      } else if (own.isDirectory()) kind = 'dir';
      else if (own.isFile()) kind = 'file';
      return { kind, size: own.size, isLink: own.isSymbolicLink() };
    } catch (e) { return null; }
  },
  read: async path => readFileSync(path, 'utf8'),
};
const mode = await resolveMode({ home, configDir: process.env.CLAUDE_CONFIG_DIR, cwd, fs });
process.stdout.write(mode || 'none');
