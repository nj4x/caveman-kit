# Research note: global flag override on session startup

Status: research note (not an ADR). This repo has no prior research-note
convention — `docs/` held only `adr/` and `agents/` — so `docs/research/` is
introduced here. If a decision comes out of this, record it as a new ADR per
CLAUDE.md.

## Problem statement (user report)

> Global `~/.claude/.caveman-active` gets overridden when a new Claude Code
> instance starts. Is it only when it starts in a repository without
> `.claude`? If so, the `/caveman <mode>` command should create local
> `.claude/.caveman-active` (with the mode) and exclude it from git in
> `.git/info/exclude` (the `.claude` directory as well).

## 1. What `caveman-activate.js` does on `source === 'startup'`

Trace (`hooks/caveman-activate.js`):

1. Parses `source` and `cwd` from stdin (lines 17–28); missing/bad stdin is
   treated as `startup` (line 28).
2. `resolveFlagPath(cwd)` picks the flag file (line 30): repo-scoped
   `<repo>/.claude/.caveman-mode` only when the repo root already has a
   `.claude/` directory (`hooks/caveman-config.js:32-50`); otherwise global
   `~/.claude/.caveman-active` with `repoRoot: null` (`caveman-config.js:49`
   — note the fall-through at line 47: repo found but no `.claude/` returns
   the *global* path).
3. Mode selection (lines 32–41):
   - Start from `getDefaultMode()` = `CAVEMAN_DEFAULT_MODE` env or built-in
     `full` (`caveman-config.js:12-16`).
   - `source !== 'startup'` (resume, `/clear`, compaction): read the resolved
     flag and keep it (lines 33–35). No clobber.
   - `source === 'startup'` **and** `repoRoot` is set: read the persisted repo
     flag and honor it (lines 36–41, citing ADR 0004 — "repo flag doubles as
     the persisted per-repo default").
   - `source === 'startup'` **and** `repoRoot` is null (global path): **the
     existing global flag is never read.** Mode stays at the env/built-in
     default.
4. The resolved mode is then written back unconditionally:
   `safeWriteFlag(flagPath, mode)` (line 48), or `clearFlag(flagPath)` if the
   mode is `off` (lines 43–45).

So on a true startup that resolves to the global flag, line 48 overwrites
`~/.claude/.caveman-active` with the default — whatever the user last set via
`/caveman <mode>` is discarded. This is by design per the code comment at
lines 14–16 ("Only a real 'startup' resets to the configured default"), but
ADR 0004 later made the *repo* flag persistent across startups (decision 3),
leaving the global flag asymmetric.

## 2. The four cases (user's hypothesis: partially confirmed)

| Case | Resolution (`caveman-config.js:32-50`) | On `startup` | Global flag clobbered? |
|---|---|---|---|
| (a) cwd not in a git repo | global flag, `repoRoot: null` (line 35 or 49) | default written to global (`caveman-activate.js:48`) | **Yes** |
| (b) git repo, no `.claude/` | global flag, `repoRoot: null` (line 47 catch → 49) | default written to global | **Yes** |
| (c) git repo, `.claude/` exists, no `.caveman-mode` file | repo flag (line 45) | `readFlag` returns null (line 39–40) → default written to **repo** flag; repo flag is created with the default | No — global untouched |
| (d) git repo, `.claude/` + `.caveman-mode` present | repo flag | persisted mode honored (lines 39–40) and rewritten (no-op) | No — global untouched |

Verdict: the hypothesis is **too narrow**. The global flag is clobbered
whenever resolution falls through to it on a real startup — that is cases
(a) *and* (b), not only (b). Starting Claude Code in `~/` or any non-repo
directory resets it too.

Cross-session side effect worth noting: any new startup in scope (a)/(b)
resets the global flag while other already-running global-scoped sessions may
be mid-conversation in a different mode. Their per-turn reminder
(`caveman-mode-tracker.js:54-61`) re-reads the flag each prompt and will
silently start reporting the reset mode. This is the reverse of the
cross-repo leak ADR 0004 fixed for repo-scoped sessions.

## 3. What `/caveman <mode>` currently writes

`hooks/caveman-mode-tracker.js`:

- Resolves the flag path with the same `resolveFlagPath(data.cwd)` (line 21).
- On a `set` action: `safeWriteFlag(flagPath, change.mode)` +
  `ensureGitExclude(repoRoot)` (lines 44–46). On `clear` (`/caveman off`):
  `clearFlag(flagPath)` (lines 47–48).
- Target is therefore repo-scoped **only if `<repo>/.claude/` already
  exists**; otherwise the global flag.
- It never creates `.claude/`. `safeWriteFlag` does
  `fs.mkdirSync(dir, { recursive: true })` (`caveman-config.js:77-78`), but
  the dir can only be `<repo>/.claude` when `resolveFlagPath` already
  `lstat`-confirmed it exists (line 44), so that mkdir is a no-op for the
  repo case; for the global case it creates `~/.claude` if missing.

## 4. Evaluation of the proposed fix

Proposal: `/caveman <mode>` creates `<repo>/.claude/` + a flag file, and adds
exclusions to `.git/info/exclude`.

**Filename discrepancy.** The user names the local file `.caveman-active`.
The repo flag is `.caveman-mode` everywhere: `caveman-config.js:45`
(resolution), `caveman-config.js:52` (`EXCLUDE_LINE = '.claude/.caveman-mode'`),
`lib/statusline-patch.js:22` (shell duplicate), ADR 0004 decision 2. Any fix
must use `.caveman-mode`, or it creates a file nothing reads.

**Excluding the `.claude` directory.** Unnecessary: git tracks files, not
directories. The existing `EXCLUDE_LINE` (`.claude/.caveman-mode`,
`caveman-config.js:52-68`) already keeps the only file the kit writes out of
`git status`. Excluding all of `.claude/` would also hide user-managed files
(e.g. `settings.local.json`, agent configs) that the user may *want* tracked
— overreach the kit shouldn't take.

**ADR conflict.** ADR 0004 decision 2 says explicitly: "Do **not**
auto-create `.claude/`"
(`docs/adr/0004-per-repository-mode-configuration.md:26`), restated in
`caveman-config.js:28-31` and acknowledged as the "first-use-in-fresh-repo
caveat" in the ADR's consequences (line 35). The ADR does not spell out a
single rationale sentence, but three motives are recoverable from it:

1. "No migration needed / no behavior changes for users/repos without a
   `.claude/` directory" (line 36) — existing global behavior preserved
   byte-for-byte as the fallback.
2. Not littering every repo the user merely cd's into — both hooks fire on
   every session/prompt, so auto-creation at *hook* level would spray
   `.claude/` dirs across all visited repos.
3. Security posture: `resolveFlagPath` refuses to follow a symlinked
   `.claude/` (`caveman-config.js:39-47`); never creating the dir keeps the
   hook from having a create-vs-attack race to reason about.

However, motive 2 distinguishes the *SessionStart/UserPromptSubmit hooks
firing passively* from *an explicit `/caveman <mode>` command*. The user
typing `/caveman ultra` inside a repo is unambiguous intent to configure that
context. Creating `.claude/` only on the explicit `set` path in
`caveman-mode-tracker.js` (never in `caveman-activate.js`, never on `clear`
or on the reinforcement path) does not trigger motive 2 and does not break
motive 1 for passive sessions. It **does** contradict the ADR's letter, so it
requires a superseding/amending ADR — but the rationale is not fundamentally
opposed to an intent-gated exception.

Caveat: even intent-gated, this changes behavior for users who deliberately
rely on the fall-through — someone who wants `/caveman` in a repo without
`.claude/` to set the *global* mode would lose that. An explicit opt-in
syntax avoids the ambiguity (see alternatives).

**Security invariants any fix must preserve** (all in
`hooks/caveman-config.js`):

- `resolveFlagPath` uses `lstat`, never following a symlinked `.claude/`
  (lines 39–47).
- `ensureGitExclude` uses `lstat` on `.git`, skipping worktree/submodule
  `.git` files and symlinked `.git` dirs (lines 57–60).
- `safeWriteFlag` refuses a symlink at the flag path and writes atomically
  via temp + rename, mode 0600 (lines 75–90).
- `readFlag` rejects symlinks/non-files, caps at 16 bytes, whitelists modes
  (lines 96–105).
- New requirement introduced by dir creation: the create step itself must be
  symlink-safe. `fs.mkdirSync(path, { recursive: true })` succeeds silently
  when the path already exists as a symlink-to-directory, so a naive
  create-then-resolve would write through a hostile symlinked `.claude/`.
  The fix must `lstat` after (or instead of trusting) the mkdir — e.g.
  `mkdirSync` without `recursive`, treating `EEXIST` as "re-run
  `resolveFlagPath` and let its lstat check decide".

## 5. Statusline shell duplication

`lib/statusline-patch.js:14-42` duplicates resolution in shell: walk up to
`.git` (line 20), prefer `<repo>/.claude/.caveman-mode` when the dir exists
(lines 21–23), else global `.caveman-active` (line 16), reject symlinked flag
files (line 28).

- For the intent-gated create fix: **no statusline change needed** — once
  `/caveman <mode>` has created `.claude/` + the flag, the existing shell
  `-d` check finds it. Resolution rules are unchanged.
- For alternatives that change *resolution or precedence* (e.g. global flag
  overlaying repo, or a new flag filename): the shell block must be updated
  in lockstep (CLAUDE.md invariant: "keep the two in sync"), and the change
  only reaches installed users via re-running `install.sh` (the block is
  baked into their `statusline.sh` at install time — sentinel markers at
  lines 11–12 make the old block detectable but the patcher currently skips,
  not upgrades, an existing block, `statusline-patch.js:52-55`).

## 6. Alternative fixes

**A. Make the global flag a persisted default too (smallest fix, no ADR 0004
conflict).** In `caveman-activate.js`, extend the startup branch at lines
36–41 to also read the persisted flag when `repoRoot` is null — i.e. drop the
`repoRoot` condition and honor whatever `readFlag(flagPath)` returns on every
startup, falling back to `getDefaultMode()` only when the flag is absent or
invalid. This is exactly the semantics ADR 0004 decision 3 already gave the
repo flag ("simultaneously the live session state and the persisted
default"); the bug is the asymmetry. `CAVEMAN_DEFAULT_MODE` becomes a
first-run/after-`off` seed rather than an every-startup reset. `/caveman off`
still resets cleanly: it *deletes* the flag (`caveman-mode-tracker.js:47-48`,
`caveman-activate.js:43-45`), so the next startup falls back to the default.
No statusline change, no new file, no security surface. Downside: users who
*relied* on startup resetting to `CAVEMAN_DEFAULT_MODE` lose that; it also
does not fix the "one repo's mode change leaks to other global-scoped
sessions" half of the problem — only per-repo scoping does that.

**B. Intent-gated auto-create (the user's fix, corrected).** On the `set`
action only in `caveman-mode-tracker.js` (lines 44–46), when `repoRoot` was
found but `.claude/` was absent: symlink-safely create `<repo>/.claude/`,
re-resolve, write `.caveman-mode` (not `.caveman-active`), call
`ensureGitExclude` (which already handles the exclude line; do not exclude
the whole `.claude/` dir). Requires an ADR amending 0004 decision 2. Fixes
both the reset-clobber (for repos, after first `/caveman` use) and the
cross-session leak; leaves non-repo startups still resetting the global flag
unless combined with A.

**C. Explicit pin syntax.** Keep decision 2 intact for `/caveman <mode>` and
add an explicit form (e.g. `/caveman <mode> repo` or `/caveman pin <mode>`)
that is allowed to create `.claude/`. Zero ambiguity about intent, no silent
behavior change for global-mode users, but more parsing surface in
`caveman-parse.js` and more for users to learn.

**Recommendation.** A + B together: A repairs the reported symptom
everywhere immediately (including case (a), which the user's proposal does
not cover); B removes the fresh-repo caveat for users who actively use
`/caveman` in a repo. If the team wants to keep ADR 0004's letter, ship A
alone and re-evaluate — A alone makes the global flag behave the way the
user expects, at the cost of demoting `CAVEMAN_DEFAULT_MODE`.
