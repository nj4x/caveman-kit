---
artifact-type: adr
lineage-rules: exempt
---

# ADR 0004: Per-repository caveman mode configuration

**Status:** Accepted (amended 2026-08-29: global flag persistence; `.claude/` auto-creation on explicit `/caveman <mode>`; repo-flag-absent fallback to global flag)

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
   - Otherwise (no repo root found, or repo root found but `.claude/` does not exist): fall back entirely to the existing global flag `~/.claude/.caveman-active`. The passive hooks (SessionStart, and the UserPromptSubmit reminder path) never auto-create `.claude/` — they fire in every repo the user merely visits.
   - **Amendment — explicit-set exception:** an explicit `/caveman <mode>` set (not `off`, not the per-turn reminder) issued inside a repo whose root lacks `.claude/` creates the directory and writes the repo flag, so the mode lands repo-scoped instead of clobbering the global flag. Creation is symlink-safe: `mkdir` without `recursive`, so an existing entry — including a hostile symlinked `.claude/` committed by the repo — surfaces as `EEXIST`, after which the path is re-resolved and the standard `lstat` check decides whether it is usable (falling back to global if not).
3. **No separate persistence layers:** `/caveman <mode>` writes directly to whichever target Decision 2 selects — no `--save-repo` flag, no ephemeral per-session flag layered on top of the repo file, no per-repo flag-hash scheme under `~/.claude/`. **Amendment:** the resolved flag file — repo-scoped *or global* — is simultaneously the live session state and the persisted default. Every SessionStart (startup, resume, `/clear`, compaction) honors the persisted flag; `CAVEMAN_DEFAULT_MODE` / built-in `full` seed only the first run or the run after `/caveman off` cleared the flag. (Originally only the repo flag persisted across real startups; the global flag was reset to the default on each startup, discarding the user's last `/caveman <mode>` — the asymmetry this amendment removes.)
4. **Manual editing works:** Since the repo file is a plain mode string, users can hand-edit `<repo>/.claude/.caveman-mode` directly; the hooks only read/write it, they do not require it to have been created via `/caveman`.
5. **`.git/info/exclude` bookkeeping:** Whenever a hook is about to write to `<repo root>/.claude/.caveman-mode`, it idempotently ensures the line `.claude/.caveman-mode` is present in `<repo root>/.git/info/exclude` (check-before-append; create the file if absent). This is a local, per-clone exclude — it does not touch or require a tracked `.gitignore`, so the repo config choice is never forced onto other clones or committed to the repo. If `.git/info/exclude` can't be written (permissions), fail silently and continue — this bookkeeping is not load-bearing for correctness.
6. **Precedence (effective mode resolution):** repo flag file → global flag → `CAVEMAN_DEFAULT_MODE` env → built-in `full`. **Amendment (2026-08-29):** this chain is a real fallback. The original text said only one of {repo file, global flag} was ever consulted, and the implementation matched: a repo whose root had a `.claude/` directory but no `.caveman-mode` file skipped the global flag entirely, seeded the built-in default (`full`), and passively wrote it to the repo flag — silently shadowing the user's persisted global mode (e.g. `ultra`) and creating a repo flag file the user never asked for. Claude Code itself creates `.claude/` in visited projects (for `settings.local.json`, plans, etc.), so this was the common case, not an edge. Now: when the repo flag *file* is absent, hooks read the global flag before the default, and the SessionStart re-persist writes to whichever file the mode actually came from — a passive session never creates the repo flag file; only an explicit `/caveman <mode>` scopes the mode to the repo (Decision 2 amendment). The statusline badge applies the same rule (repo path only when the flag file exists).

**Consequences:**

- **Cross-repo leak fixed:** Switching mode in one repo's session no longer affects sessions in other repos, as long as each repo has a `.claude/` directory.
- **First-use-in-fresh-repo caveat (resolved by amendment):** A repo with `.git` but no `.claude/` directory silently uses the global flag only until the first explicit `/caveman <mode>` there, which creates `.claude/` and scopes the mode to the repo. Passive sessions (no explicit set) still use the global flag.
- **Global flag persists (amendment):** `CAVEMAN_DEFAULT_MODE` no longer acts as an every-startup reset; users relying on that reset must `/caveman off` (which clears the flag) to return to the seeded default.
- **Statusline badge:** must apply the same Decision 2 resolution (given its own `cwd`) to show the correct mode per repo; currently reads only the global flag and needs updating to match.
- **`caveman-kit` uninstall:** does not need to clean up per-repo `.caveman-mode` files — they are user data (like the skill's own config), not kit-managed installation state, and are excluded from git via `.git/info/exclude` rather than tracked in `~/.caveman-kit/manifest.json`.
