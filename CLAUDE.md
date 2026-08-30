# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Installer kit that wires the third-party `caveman` Claude Code skill (JuliusBrussee/caveman, pinned to v2.2.0) into an existing Claude Code configuration via hooks. It does not contain the skill itself — it injects hook entries into `settings.json`, a badge into `statusline.sh`, and patches the skill's frontmatter.

## Commands

No build, lint, or test tooling — plain bash entry points and dependency-free Node scripts (`node` on PATH is the only requirement).

```bash
./install.sh                     # install; auto-installs the skill if missing
./install.sh --no-install-skill  # skip skill auto-install (or CAVEMAN_KIT_INSTALL_SKILL=0)
./uninstall.sh                   # marker-surgical removal of kit patches, removes ~/.caveman-kit
```

Manual smoke-test of hooks (they read JSON on stdin, must always exit 0):

```bash
echo '{"source":"startup","cwd":"'$PWD'"}' | CLAUDE_PLUGIN_ROOT=~/.claude node hooks/caveman-activate.js
echo '{"prompt":"/caveman ultra","cwd":"'$PWD'"}' | node hooks/caveman-mode-tracker.js
```

## Architecture

Two lifecycles that must stay symmetric:

1. **Install time** (`install.sh` + `lib/`): backs up `settings.json`, `statusline.sh`, and `SKILL.md` to `~/.caveman-kit/backup/`, then patches each via a `lib/*.js` script. Writes `~/.caveman-kit/manifest.json` recording backups and whether the kit auto-installed the skill. Manifest is written *before* the skill-frontmatter patch attempt so uninstall can always clean up (ADR 0003 decision 6). `uninstall.sh` removes the kit's own patches surgically (`lib/*-unpatch.js` match hook-command markers and statusline sentinels), so other kits' patches and post-install user edits survive; backups stay in the manifest for manual recovery only. `SKILL.md` frontmatter is still restored from its backup. Any new install-time mutation must add a backup + manifest field + uninstall path.

2. **Runtime** (`hooks/`, copied to `~/.caveman-kit/hooks/` at install):
   - `caveman-activate.js` (SessionStart) — resolves active mode, persists it to a flag file, injects the skill ruleset filtered to that mode's intensity-table row/examples. The persisted flag (repo or global) is honored on every fire, including real startup; `CAVEMAN_DEFAULT_MODE`/built-in `full` seed only when the flag is absent (first run, or after `/caveman off`).
   - `caveman-mode-tracker.js` (UserPromptSubmit) — parses `/caveman <mode>` (delivered as a `<command-name>` envelope, which it unwraps) and natural-language triggers via `caveman-parse.js`, updates the flag, and re-asserts a one-line reminder each turn so mode survives long sessions.
   - `caveman-config.js` — shared: valid modes, flag-file resolution, safe read/write.

**Flag-file resolution** (ADR 0004): repo-scoped `<repo>/.claude/.caveman-mode` when cwd is in a git repo whose root has `.claude/` *and the flag file exists*; when the repo flag file is absent, hooks fall back to reading the global `~/.claude/.caveman-active` before the built-in default — a bare `.claude/` dir never shadows the global mode. Passive hooks never create `.claude/` nor the repo flag file (SessionStart re-persists to whichever file the mode came from); an explicit `/caveman <mode>` set does (symlink-safe, then re-resolves), and the flag file is auto-added to `.git/info/exclude`. Either flag doubles as the persisted default honored at startup. The statusline badge block in `lib/statusline-patch.js` duplicates this resolution in shell — keep the two in sync.

**Skill location**: hooks find `SKILL.md` via `CLAUDE_PLUGIN_ROOT`, baked into the hook commands in `settings.json` at install time (symlink-resolved).

## Invariants

- **Hooks always exit 0** and fail silent/soft — a broken hook must never block Claude Code. Flag operations are best-effort, not load-bearing.
- **Flag files are untrusted input**: `readFlag` rejects symlinks, caps at 16 bytes, whitelists modes; `safeWriteFlag` refuses symlinks and writes atomically (temp + rename). `resolveFlagPath`/`ensureGitExclude` use `lstat`, never following a symlinked `.claude/` or `.git/` a hostile repo could commit. Preserve these properties in any change touching flag I/O.
- **Patch scripts are idempotent** — re-running detects prior injection (marker string in settings, sentinel comments in statusline, existing key in frontmatter) and skips.
- Valid modes: `off, lite, full, ultra, wenyan-lite, wenyan-full, wenyan-ultra` — must match the intensity levels in the upstream skill's SKILL.md.

## Design records

`docs/adr/` holds four accepted ADRs (auto-install, frontmatter patch, uninstall symmetry/manifest, per-repo mode). Code comments cite them by number — read the relevant ADR before changing behavior it governs, and record significant new decisions as a new ADR.

## Agent skills

### Issue tracker

GitHub Issues (`nj4x/caveman-kit`). Use `gh` CLI for all operations. See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical roles, each label string equal to its name: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout: `CONTEXT.md` at repo root + `docs/adr/` for design decisions. See `docs/agents/domain.md`.
