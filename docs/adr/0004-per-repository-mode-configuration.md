---
artifact-type: adr
lineage-rules: exempt
---

# ADR 0004: Per-repository caveman mode configuration

**Status:** Accepted

**Context:**

Today caveman-kit's mode configuration is fully global:

1. Default mode resolution: `CAVEMAN_DEFAULT_MODE` env var, else built-in `full` (`hooks/caveman-config.js:12-16`)
2. Runtime mode switching (`/caveman <mode>`): writes to a single global flag file `~/.claude/.caveman-active` (`caveman-activate.js:16`, `caveman-mode-tracker.js:16`)

Switching mode in one repo's session changes the mode for every other concurrently running session in every other repo, since the flag file path is not scoped by working directory. There is no way to set a different default mode per project (e.g. `off` for a docs repo, `full` for an active codebase).

Both hooks (`caveman-activate.js` SessionStart, `caveman-mode-tracker.js` UserPromptSubmit) already receive `cwd` in their JSON stdin payload from Claude Code, unused today — only `prompt`/`source` are read. This makes repo-scoped resolution straightforward without new plumbing.

**Decision:**

1. **Repo detection:** On each hook invocation, walk up from `data.cwd` to the nearest ancestor directory containing `.git` (dir or file, covering worktrees/submodules). If found, that is the repo root for this invocation.
2. **Write/read target selection:**
   - If a repo root is found **and** `<repo root>/.claude/` already exists as a directory: read and write mode at `<repo root>/.claude/.caveman-mode` (plain text mode string, same format and validation as the existing global flag — reuses `VALID_MODES` and the symlink/size-cap safety checks in `caveman-config.js`).
   - Otherwise (no repo root found, or repo root found but `.claude/` does not exist): fall back entirely to the existing global flag `~/.claude/.caveman-active`, unchanged from today's behavior. Do **not** auto-create `.claude/`.
3. **No separate persistence layers:** `/caveman <mode>` writes directly to whichever target Decision 2 selects — no `--save-repo` flag, no ephemeral per-session flag layered on top of the repo file, no per-repo flag-hash scheme under `~/.claude/`. The repo file (when applicable) is simultaneously the live session state and the persisted default; `caveman-activate.js`'s existing "only real startup resets to default; resume/compaction preserve the current flag" logic applies identically, just against whichever file Decision 2 resolved.
4. **Manual editing works:** Since the repo file is a plain mode string, users can hand-edit `<repo>/.claude/.caveman-mode` directly; the hooks only read/write it, they do not require it to have been created via `/caveman`.
5. **`.git/info/exclude` bookkeeping:** Whenever a hook is about to write to `<repo root>/.claude/.caveman-mode`, it idempotently ensures the line `.claude/.caveman-mode` is present in `<repo root>/.git/info/exclude` (check-before-append; create the file if absent). This is a local, per-clone exclude — it does not touch or require a tracked `.gitignore`, so the repo config choice is never forced onto other clones or committed to the repo. If `.git/info/exclude` can't be written (permissions), fail silently and continue — this bookkeeping is not load-bearing for correctness.
6. **Precedence (effective mode resolution):** repo file (only in the branch where `.claude/` exists) → global flag → `CAVEMAN_DEFAULT_MODE` env → built-in `full`. Only one of {repo file, global flag} is ever consulted for a given invocation per Decision 2 — they are not both checked and merged.

**Consequences:**

- **Cross-repo leak fixed:** Switching mode in one repo's session no longer affects sessions in other repos, as long as each repo has a `.claude/` directory.
- **First-use-in-fresh-repo caveat:** A repo with `.git` but no `.claude/` directory yet will silently use the global flag until `.claude/` is created (by any means — this ADR does not auto-create it). Mode switches in that repo affect all other global-flag-scoped sessions until then.
- **No migration needed:** Existing global-flag behavior is preserved byte-for-byte as the fallback path; no behavior changes for users/repos without a `.claude/` directory.
- **Statusline badge:** must apply the same Decision 2 resolution (given its own `cwd`) to show the correct mode per repo; currently reads only the global flag and needs updating to match.
- **`caveman-kit` uninstall:** does not need to clean up per-repo `.caveman-mode` files — they are user data (like the skill's own config), not kit-managed installation state, and are excluded from git via `.git/info/exclude` rather than tracked in `~/.caveman-kit/manifest.json`.
