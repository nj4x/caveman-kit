// caveman-badge — pure flag resolution and parsing (ADR 0022 decisions 9-12;
// drawing moved to chip.mjs by ADR 0023). No `$` and no Node built-ins:
// every file access goes through the injected `fs`, so tests run it with
// node's fs and register.tsx runs it with `$.fs`.
//
// fs.stat(path) -> { kind, size, isLink } | null   (null when missing)
// fs.read(path) -> string
// This is a third copy of the ADR 0004 resolution (hooks/caveman-config.js and
// the shell block in lib/statusline-patch.js); change all three together.

const MAX_FLAG_BYTES = 16;
const MODES = ['off', 'lite', 'full', 'ultra'];
const KIT_MARKER = '.caveman-kit/hooks/caveman-activate.js';

function parentOf(dir) {
  const cut = dir.lastIndexOf('/');
  if (cut <= 0) return '/';
  return dir.slice(0, cut);
}

// Whitelist like the shell block: strip everything outside a-z0-9-. (readFlag
// in hooks/caveman-config.js only trims; a hand-edited `lite!` is accepted
// here and by the shell block, rejected by the hooks.) 'off' is a valid mode
// that draws no badge.
export function parseMode(text) {
  const mode = String(text).toLowerCase().replace(/[^a-z0-9-]/g, '');
  return MODES.includes(mode) ? mode : null;
}

// Returns 'lite' | 'full' | 'ultra' | null. Every failure is null.
export async function resolveMode({ home, configDir, cwd, fs }) {
  try {
    if (!home) return null;
    // Decision 11: no kit hooks, no badge.
    if (!(await fs.stat(`${home}/${KIT_MARKER}`))) return null;

    const globalFlag = `${configDir || `${home}/.claude`}/.caveman-active`;
    let flag = globalFlag;
    if (cwd) {
      let dir = cwd;
      for (;;) {
        if (await fs.stat(`${dir}/.git`)) {
          const claude = await fs.stat(`${dir}/.claude`);
          if (claude && claude.kind === 'dir' && !claude.isLink && (await fs.stat(`${dir}/.claude/.caveman-mode`))) {
            flag = `${dir}/.claude/.caveman-mode`;
          }
          break;
        }
        if (dir === '/') break;
        dir = parentOf(dir);
      }
    }

    // A rejected repo flag falls back to the global flag, as the hooks do
    // (readFlag null, then readFlag(globalFlag)); a valid 'off' does not.
    let mode = await readFlag(fs, flag);
    if (mode === null && flag !== globalFlag) mode = await readFlag(fs, globalFlag);
    return mode === 'off' ? null : mode;
  } catch {
    return null;
  }
}

// Mirrors readFlag: a link, a non-file or a file over 16 bytes is rejected.
async function readFlag(fs, path) {
  const st = await fs.stat(path);
  if (!st || st.isLink || st.kind !== 'file' || st.size > MAX_FLAG_BYTES) return null;
  try {
    return parseMode(await fs.read(path));
  } catch {
    // Unreadable: null, so a repo flag falls back to global as in the hooks.
    return null;
  }
}
