# Caveman Installed vs Kit: Comparison

**Date:** 2026-08-28  
**Scope:** Read-only investigation of on-disk files; no installs, no mutations.

---

## Verdict

The installed system and the kit are **architecturally different products** that happen to share nearly the same `caveman/SKILL.md` text. The installed system (`@caveman-ai/cli` v1.2.3, `getcaveman.dev`) is a full-stack API proxy: Go binaries intercept Anthropic API traffic, perform actual context compression at the byte level, maintain a 50 MB SQLite database of sessions, expose an MCP server, and fire hooks on 11 Claude Code event types. The kit is a self-contained style-injection layer: two JS hook scripts write a flag file and inject the SKILL.md text as `additionalContext` every session start and every prompt, instructing the model to write in a compressed style — no proxy, no interception, no database. If installed on top, the two systems would double-inject ruleset text on every turn without coordinating, but they would not crash or overwrite each other's config. The kit's skills (6 new ones) would install cleanly. The `caveman` skill symlink would survive intact.

---

## Comparison table

| Dimension | Installed (npm/proxy) | Kit (standalone hooks) |
|---|---|---|
| Package | `@caveman-ai/cli` v1.2.3 | No version/author metadata |
| Mechanism | Go proxy intercepts API at HTTP level | JS hook injects text ruleset into model context |
| Compression | Real: `output_replacement`, context rewrite via Go engine | Instructional: tells model to respond in compressed style |
| Hook events covered | 11: SessionStart, UserPromptSubmit, PreToolUse ×2, PostToolUse, PostToolUseFailure, PreCompact, PostCompact, Stop, SubagentStart, SubagentStop, SessionEnd | 2: SessionStart, UserPromptSubmit |
| State | `~/.caveman/caveman.db` (50 MB), `ccr.db` (52 MB), 78 session receipt files, `~/.caveman-cloud/config.json` | `~/.claude/.caveman-active` (≤64 byte flag), `~/.caveman-mode-log.jsonl`, `~/.caveman-statusline-suffix` |
| Modes/levels (compression) | record / compress / pixel (proxy policy); safe / max (native hook policy) | off, lite, full, ultra (ADR 0006: wenyan modes dropped) |
| Config file | `~/.caveman-cloud/config.json` | `$XDG_CONFIG_HOME/caveman/config.json` (XDG) or env `CAVEMAN_DEFAULT_MODE`; per-repo: `.caveman/config.json` or `.caveman.json` walked from cwd |
| Per-repo config | None visible on disk | Walked upward from session cwd; 64-level depth limit |
| Default mode | compress (unless `~/.caveman-cloud/config.json` overrides) | full |
| Stats | SQLite + session receipts; `caveman stats` CLI reads actual verified usage | Reads Claude Code session JSONL (`~/.claude/projects/`), computes estimated savings; 65% figure for `full` only, labeled "inferred"; also reports ~1250 tokens/turn overhead from rule injection |
| Statusline | Proxy provides suffix data (written to `~/.caveman-statusline-suffix` by stats script) rendered by `caveman-statusline.sh` | Same bash script ships in kit, reads `~/.claude/.caveman-active` flag + `.caveman-statusline-suffix` |
| Skills installed | 1: `~/.claude/skills/caveman` symlink → `~/.agents/skills/caveman` | 7: caveman, caveman-commit, caveman-review, caveman-compress, caveman-help, caveman-stats, cavecrew |
| SKILL.md frontmatter | `disable-model-invocation: true` present | `disable-model-invocation` absent |
| Boundaries section | Longer (adds "issue/PR/MR/defect/ticket/bug-report text" and "open a defect"/"file a bug" equivalences) | Shorter (omits defect-tracking wording) |
| Safety carve-outs | Same as kit (in SKILL.md): security warnings, irreversible-action confirmations, multi-step sequences, user repeats question | Same (from SKILL.md): security warnings, irreversible-action confirmations, ambiguous multi-step sequences, user repeats |
| Written artifacts | Normal prose (code, commits, PRs, docs, memory files) — SKILL.md identical in both | Same |
| MCP | `caveman-mcp` binary in `~/.claude.json` | None |
| Telemetry | Cloud audit via `caveman cloud audit` CLI; opt-in | None |
| Update path | `npm update -g @caveman-ai/cli` + `caveman setup --install` for Go binaries | Manual re-download |
| Installation | `caveman setup --agent-native claude` (managed) | `./install.sh` + manual `settings.json` edit |

---

## Detailed sections

### 1. What the installed npm package actually does

**Package:** `@caveman-ai/cli` v1.2.3  
**Source:** `/Users/r.herasymenk/.nvm/versions/node/v20.18.3/lib/node_modules/@caveman-ai/cli/package.json`  
**Repo:** `github.com/JuliusBrussee/caveman`, homepage `getcaveman.dev`

The npm package is a thin JavaScript CLI frontend. The actual work runs in six downloaded Go binaries in `~/.caveman/bin/` (manifest at `~/.caveman/bin/.bin-manifest.json`, release `bin-v1.1.2`):

| Binary | Size | Role |
|---|---|---|
| `caveman-proxy` | 37.8 MB | HTTP proxy intercepts Anthropic API traffic at `127.0.0.1:8082` (see `~/.caveman/caveman.yaml`) |
| `caveman-engine` | 27.4 MB | Compression, shrink, retrieve, evals |
| `caveman-mcp` | 25.5 MB | MCP server registered in `~/.claude.json` |
| `cavemem` | 25.5 MB | Local context memory offload |
| `caveman-browse` | 32.7 MB | Compressed page snapshots |
| `caveman-shrink` | 25.3 MB | Tool-schema compression (fires on PreToolUse via `caveman shrink-hook`) |

The hook entry point is `dist/native-hook-fast.js` (21 KB, readable source, not minified). It:

1. Reads the event payload from stdin via a streaming JSON parser that returns as soon as one complete JSON object is parseable (not waiting for EOF, to handle Windows pipe lag — see comments at line 81).
2. For `SessionStart` and `PostCompact`, delegates to the full `index.js` CLI via a child process with a 3-second cap.
3. For all other events, builds a structured request and sends it over a Unix socket at `~/.caveman/run/native.sock` (Windows: named pipe). Times out at 250 ms; falls back to logging the event to `~/.caveman/runtime/native-events.jsonl`.
4. On a valid response from the Go runtime:
   - Injects `additionalContext` on `UserPromptSubmit` and `PreToolUse` (the "Core" ruleset from the Go runtime, if `think.core` is enabled and mode is not `record`).
   - Replaces tool output on `PostToolUse` via `output_replacement` (actual compression of command output).
   - Emits a summary message on `SessionEnd`.

Policy modes (`native-hook-fast.js` lines 62–80): `record` → record only; `safe` (default when `compress` mode is configured) → lossless-safe compression; `max` (when `pixel` mode) → maximum compression. The Go runtime makes the actual policy decision; the JS hook is a thin serialization layer.

Config is read from `~/.caveman-cloud/config.json` under `think.mode` and `think.core` keys. The `~/.caveman/integrations/claude.json` file records what the managed setup wrote: it patched `~/.claude/settings.json` with 11 hook entries and installed the MCP binary in `~/.claude.json`.

**State on disk:**
- `~/.caveman/caveman.db` — 49.6 MB SQLite, primary session/compression database  
- `~/.caveman/ccr.db` — 52.1 MB SQLite, context compression records  
- `~/.caveman/mem/mem.db` and `ccr.db` — memory subsystem  
- `~/.caveman/receipts/` — 76 per-session JSON files (billing-grade records)  
- `~/.caveman/reports/` — generated reports  
- `~/.caveman/runtime/` — native event fallback log  

### 2. The symlinked caveman skill

`~/.claude/skills/caveman` is a symlink:  
`~/.claude/skills/caveman → ../../.agents/skills/caveman`  
Resolved real path: `/Users/r.herasymenk/.agents/skills/caveman`  
(Confirmed via `readlink -f`; `~/.agents/` appears to not be a git repo — `git -C ~/.agents remote -v` returned empty.)

`~/.agents/skills/caveman/` contains two files: `README.md` and `SKILL.md`.

**Installed SKILL.md vs kit SKILL.md — diff summary:**

Both files share the same frontmatter description text, all Rules prose, all intensity table rows, all examples, and the Auto-Clarity section verbatim. Two differences:

1. **`disable-model-invocation: true`** is present in the installed `SKILL.md` frontmatter (line 9); absent from the kit's `SKILL.md`. This Claude Code frontmatter flag prevents the model from being invoked when the skill file is loaded. The kit's version lacks it, which means loading the skill with `/caveman` would invoke the model through the normal path.

2. **Boundaries section** (last section of each file):  
   - Installed (line 91): `"code, comments, commits, docs, issue/PR/MR/defect/ticket/bug-report text, memory files"` and adds `"Open a defect" or "file a bug" mean the same as "open issue"`.  
   - Kit (line 88): shorter: `"code, comments, commits, docs, issue/PR/MR text, memory files"` — no defect-tracking equivalences.

Otherwise the SKILL.md texts are byte-for-byte equivalent. The kit is at most one edit behind the installed version.

**README.md note:** Both the installed `~/.agents/skills/caveman/README.md` and the kit's `skills/caveman/README.md` describe the ultra intensity as "Bare fragments. Abbreviations (DB, auth, fn). Arrows for causality." — but both SKILL.md files say the opposite ("NO prose abbreviations... NO arrows (X → Y)"). The READMEs are stale relative to the SKILL.md.

### 3. The kit's hook mechanism

**Files:** `~/Downloads/caveman-kit/hooks/` — 7 files.

**`caveman-activate.js`** (SessionStart hook, `caveman-activate.js` line 3):
- Reads the hook payload's `source` field. Only a `startup` source resets the mode to the configured default; `resume`/`clear`/`compact` re-fires preserve whatever mode was already set.
- If mode is `off`: deletes the flag file, exits with `OK`.
- Reads `SKILL.md` from one of three candidate paths in order: `$CLAUDE_PLUGIN_ROOT/skills/caveman/SKILL.md`, `../../skills/caveman/SKILL.md`, `../skills/caveman/SKILL.md`. Falls back to a hardcoded 10-line ruleset if none found.
- Filters the SKILL.md: strips frontmatter, keeps only the active intensity's table row and example line.
- Emits `CAVEMAN MODE ACTIVE — level: <mode>\n\n<filtered SKILL.md>` as stdout, which Claude Code delivers as hidden `additionalContext` to the model.
- On first session where `settings.json` lacks a `statusLine` key, appends a nudge to the output asking the model to offer statusline setup (one-shot, gated by `~/.claude/.caveman-nudge-shown` marker file, `caveman-activate.js` line 166).
- Tries to apply cavecrew model overrides (`cavecrew-model-overrides` module) but swallows any error silently — that module is not in the kit.

**`caveman-mode-tracker.js`** (UserPromptSubmit hook):
- Reads user prompt from stdin JSON.
- Guards against `<scheduled-task>` wrapped prompts — exits without action.
- Handles Claude Code slash command envelope format: reconstructs `/caveman <args>` from `<command-name>` and `<command-args>` XML wrappers.
- Delegates parsing to `caveman-parse.js` (`parseModeChange` function).
- On mode change: writes new mode to `~/.claude/.caveman-active` via `safeWriteFlag`. Logs transition to `~/.caveman-mode-log.jsonl`.
- On mode clear: deletes flag file.
- One-shot independent modes (commit/review/compress): saves current prose mode to `~/.claude/.caveman-active.prev`, restores it on the next non-independent-mode prompt.
- Per-turn reinforcement: if flag is set and mode is not an independent mode, writes `{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"CAVEMAN MODE ACTIVE (full) — session ruleset applies."}}` to stdout — injected every prompt while caveman is active.
- Handles `/caveman-stats` command by running `caveman-stats.js` and returning its output as `additionalContext`.
- Handles per-repo opt-out: if `getDefaultMode(data.cwd) === 'off'` (via `.caveman/config.json` in the session's cwd), skips reinforcement injection even if the flag is set.

**`caveman-config.js`** (shared config resolver):
- Resolution order for default mode (lines 3–16):
  1. `CAVEMAN_DEFAULT_MODE` env var
  2. Repo-local: walks up from cwd looking for `.caveman/config.json` or `.caveman.json` (64-level cap, refuses symlinks)
  3. User config: `$XDG_CONFIG_HOME/caveman/config.json`, `~/.config/caveman/config.json` (macOS/Linux), `%APPDATA%\caveman\config.json` (Windows)
  4. Default: `full`
- `safeWriteFlag`: atomic write via temp + rename with `O_NOFOLLOW`, 0600 permissions, refuses symlinks at target, resolves and verifies ownership when the parent directory is itself a symlink.
- `readFlag`: refuses symlinks, caps read at 64 bytes, whitelists mode strings.

**`caveman-stats.js`** (lines 1–80 read):
- Scans `~/.claude/projects/` for JSONL session files, tallies actual token counts from Claude Code session logs.
- Estimates savings: only `full` mode has a measured figure (65%, labeled `COMPRESSION = { 'full': 0.65 }`, line 19 — from a benchmark on sonnet-4-20250514).
- Reports per-turn overhead: `DEFAULT_RULE_OVERHEAD_TOKENS_PER_TURN = 1250` (line 27), overrideable via `CAVEMAN_RULE_OVERHEAD_TOKENS`. The script explicitly reports this overhead alongside gross savings so the net figure is honest.
- Model output pricing table for USD estimates (Opus 4.0/4.1 at $75/M, Opus 4 at $25/M, Sonnet 4 at $15/M, Haiku 4 at $5/M, etc., line 41–54).

**`caveman-statusline.sh`**:
- Reads `~/.claude/.caveman-active` (refuses symlinks, strips non-`[a-z0-9-]`, whitelists modes).
- Renders `[CAVEMAN]` or `[CAVEMAN:ULTRA]` in ANSI orange.
- Optionally reads `~/.claude/.caveman-statusline-suffix` (pre-rendered savings string, written by `caveman-stats.js`) to append token savings to the badge. Nothing rendered until `/caveman-stats` has run at least once (safe default).

**`caveman-parse.js`** (lines 1–60 read):
- Shared parser for mode-change detection, used by both the Claude Code hook and an opencode plugin.
- Handles `/caveman <level>` slash commands, natural-language activation/deactivation phrases, brevity triggers, and namespaced `/caveman:caveman-*` forms.

**`settings-snippet.json`**: registers two hooks — `SessionStart` with `caveman-activate.js` and `UserPromptSubmit` with `caveman-mode-tracker.js`, each with a 5-second timeout.

**`install.sh`**:
- Copies `skills/*` to `$DEST/skills/` with an existence check (`-e`), skipping any that already exist.
- Copies `hooks/*` to `$DEST/hooks/` unconditionally (overwrites).
- Does NOT touch `settings.json`.

### 4. Config file discrepancy in the kit

`INSTALL.md` line 54 tells users to run:
```bash
echo '{"defaultMode": "ultra"}' > ~/.claude/caveman-config.json
```

But `caveman-config.js` does not read `~/.claude/caveman-config.json`. The user-level config path is `~/.config/caveman/config.json` (XDG) on macOS/Linux. A user following INSTALL.md's step to change the default level would create a file that the code never reads. This is a documentation bug in the kit.

The `INSTALL.md` also says "A `caveman-config.json` committed in a repo sets the default for that project" but `caveman-config.js` looks for `.caveman/config.json` or `.caveman.json` — not `caveman-config.json`. Same discrepancy.

### 5. Coexistence and collision analysis

**`install.sh` behavior with the caveman symlink:**

`~/.claude/skills/caveman` is a symlink. `install.sh` tests existence with `-e`:
```bash
if [ -e "$DEST/skills/$name" ]; then
    echo "skip (exists): skills/$name"
```

`-e` follows symlinks and tests whether the target exists. `~/.agents/skills/caveman/` exists. So `install.sh` would print `skip (exists): skills/caveman` and leave the symlink untouched. The kit's `caveman/SKILL.md` (which lacks `disable-model-invocation: true`) would NOT be installed.

**Other skills:** `caveman-commit`, `caveman-review`, `caveman-compress`, `caveman-help`, `caveman-stats`, `cavecrew` do not currently exist in `~/.claude/skills/`. All six would be copied by `install.sh`.

**Hooks:** `install.sh` copies hooks unconditionally. `~/.claude/hooks/caveman-activate.js`, `caveman-config.js`, `caveman-mode-tracker.js`, `caveman-parse.js`, `caveman-stats.js`, `caveman-statusline.sh`, `caveman-statusline.ps1` would be written. Currently there are no `caveman-*` files in `~/.claude/hooks/`, so no existing files would be clobbered.

**settings.json double-hook risk:**

If the user then manually adds the kit's two hook entries from `settings-snippet.json`, the active `settings.json` would contain:
- `SessionStart`: npm's `caveman-proxy native-hook claude --adapter native-hook-fast.js` AND kit's `caveman-activate.js`
- `UserPromptSubmit`: npm's `caveman-proxy native-hook claude --adapter native-hook-fast.js` AND kit's `caveman-mode-tracker.js`

Effects:
1. Every session start: npm hook connects to Go runtime and injects Core ruleset from `~/.caveman-cloud/`; kit hook reads `SKILL.md` and injects the full filtered ruleset. Two separate `additionalContext` blocks injected simultaneously.
2. Every prompt: npm hook sends event to Go runtime (which may inject Core context); kit hook injects `"CAVEMAN MODE ACTIVE (full) — session ruleset applies."`. The kit's overhead figure of ~1250 tokens/turn would stack on top of whatever the npm system injects.
3. The kit flag file (`~/.claude/.caveman-active`) would be written by the kit hook but not read by the npm hook. The npm system has its own mode state in `~/.caveman-cloud/config.json`. They track mode independently.
4. Both hooks would process `/caveman off` independently. The kit would delete its flag file. The npm system would not see the off command (it doesn't parse natural language) — the npm system's compression behavior would continue unless configured via `caveman tools config set think.mode record`.

**Config file:** no clash. npm reads `~/.caveman-cloud/config.json`; kit reads `~/.config/caveman/config.json`. Different paths.

**MCP:** kit adds no MCP entry. npm already has `caveman-mcp` in `~/.claude.json`. No conflict.

**Statusline:** both use the same `caveman-statusline.sh` script reading the same `~/.claude/.caveman-active` flag. The npm system populates `~/.caveman-statusline-suffix` when `caveman stats` is run. If both a statusline entry for the npm script and one for the kit's script were in `settings.json`, they would render two badges. In practice, there is currently only one `statusLine` entry — this is unaffected by running `install.sh` since `install.sh` does not touch `settings.json`.

**Verdict on coexistence:** Mechanically safe for files but logically conflicting for behavior. Running `install.sh` alone (without editing `settings.json`) adds 6 new skills and 7 hook files to disk harmlessly. Adding the kit's `settings.json` hook entries would cause double-injection of compression rules on every session start and every prompt, increasing context overhead rather than reducing it, and creating two independently tracked mode states that cannot coordinate with each other.

### 6. Provenance

**npm package:** Public, published on npmjs.com (`@caveman-ai/cli`). Repository `github.com/JuliusBrussee/caveman` (monorepo, `packages/cli` directory). Homepage `getcaveman.dev`. Version 1.2.3. MIT license. Binary release `bin-v1.1.2`.

**Kit:** No version, no author, no homepage, no license file in the kit root. The hook JS files reference issue numbers (#537, #538, #578, #591, #598, #599, #601, #602, #618, #634, #657, #661, #691, #711, #729, #819, #833) suggesting a sustained development history. The `caveman/SKILL.md` is nearly identical to the skill in `~/.agents/skills/caveman` (itself from a `getcaveman.dev`-installed package), differing only by two additions in the installed version. Given the shared SKILL.md content, same mode names, same hook event targets, and the cross-reference in `caveman-parse.js` to an "opencode plugin," the kit appears to be a standalone/extracted distribution of the same project's hook layer — not an independent reimplementation. The npm package's `--agent-native claude` setup writes the Go-proxy hook entries; the kit provides an alternative that works without the Go runtime. Both likely share the same upstream project.

---

## Sources

All claims cite the file read, with line numbers where material.

- `/Users/r.herasymenk/.nvm/versions/node/v20.18.3/lib/node_modules/@caveman-ai/cli/package.json` — name, version, repo, homepage, bin entries
- `/Users/r.herasymenk/.nvm/versions/node/v20.18.3/lib/node_modules/@caveman-ai/cli/README.md` — binary table, modes, update path
- `/Users/r.herasymenk/.nvm/versions/node/v20.18.3/lib/node_modules/@caveman-ai/cli/dist/native-hook-fast.js` — hook event list (line 11), protocol events (line 12–17), policy modes (lines 62–80), socket path (line 356), output_replacement (line 470), additionalContext injection (lines 461–475)
- `/Users/r.herasymenk/.caveman/caveman.yaml` — proxy base URL
- `/Users/r.herasymenk/.caveman/bin/.bin-manifest.json` — Go binary release version and hashes
- `/Users/r.herasymenk/.caveman/integrations/claude.json` — what the managed setup wrote to settings.json and claude.json
- `/Users/r.herasymenk/.caveman/receipts/` — 76 session receipt files (count only)
- `/Users/r.herasymenk/.agents/skills/caveman/SKILL.md` — installed skill text (symlink target)
- `/Users/r.herasymenk/.agents/skills/caveman/README.md` — human-facing docs (stale ultra description)
- `/Users/r.herasymenk/Downloads/caveman-kit/INSTALL.md` — install steps, config location (buggy), cavecrew warning
- `/Users/r.herasymenk/Downloads/caveman-kit/install.sh` — `-e` check behavior (line 13), hooks overwrite (line 21), no settings.json edit
- `/Users/r.herasymenk/Downloads/caveman-kit/settings-snippet.json` — two hook events, timeouts
- `/Users/r.herasymenk/Downloads/caveman-kit/hooks/caveman-activate.js` — SessionStart behavior, SKILL.md candidate paths (lines 93–100), mode-source branching (lines 33–48), statusline nudge (lines 166–196)
- `/Users/r.herasymenk/Downloads/caveman-kit/hooks/caveman-mode-tracker.js` — per-turn reinforcement (lines 138–169), scheduled-task guard (line 38), one-shot restore (lines 143–155), repo opt-out (line 162)
- `/Users/r.herasymenk/Downloads/caveman-kit/hooks/caveman-config.js` — config resolution order (lines 3–16), user config path (lines 28–38), `safeWriteFlag` (lines 138–231), `readFlag` (lines 246–276), mode-log (lines 344–358)
- `/Users/r.herasymenk/Downloads/caveman-kit/hooks/caveman-stats.js` lines 1–80 — COMPRESSION table (line 19), rule overhead (line 27), model pricing table (lines 41–54)
- `/Users/r.herasymenk/Downloads/caveman-kit/hooks/caveman-statusline.sh` — flag read, savings suffix, ANSI output
- `/Users/r.herasymenk/Downloads/caveman-kit/hooks/caveman-parse.js` lines 1–60 — INDEPENDENT_MODES (line 53)
- `/Users/r.herasymenk/Downloads/caveman-kit/skills/caveman/SKILL.md` — kit skill text
- `/Users/r.herasymenk/Downloads/caveman-kit/skills/cavecrew/SKILL.md` — incomplete cavecrew, references missing subagents
- `/Users/r.herasymenk/Downloads/caveman-kit/skills/caveman-compress/SECURITY.md` — subprocess usage clarification
- `~/.claude/settings.json` — 11 hook entries, events covered (via python3 parse)
- `~/.claude/skills/` directory listing — symlink to `../../.agents/skills/caveman`, 6 kit skills absent
