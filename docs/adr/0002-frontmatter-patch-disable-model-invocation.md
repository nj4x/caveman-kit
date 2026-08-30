# ADR 0002: Patch caveman skill frontmatter with disable-model-invocation

**Status:** Accepted

**Context:**

caveman-kit's SessionStart hook (`hooks/caveman-activate.js`) injects caveman rulesets into Claude Code's `additionalContext`, instructing the agent to compress output and drop filler. However, Claude Code also allows agents to invoke tools and make decisions autonomously.

The caveman skill's own hooks (`caveman-activate.js`, `caveman-mode-tracker.js`) are system-level metadata that affect how the agent _itself_ behaves, not just what it outputs. Injecting these rulesets unconditionally into an agent's context means the agent runs code that modifies its own decision-making and tool invocation logic.

To prevent caveman hooks from running as code inside the agent (only reading and enforcing the ruleset), the skill's frontmatter should declare `disable-model-invocation: true`, disabling tool-use and inline code execution within the skill file itself.

**Decision:**

1. **Patch target:** Both:
   - Auto-installed skill: Patch `SKILL.md` immediately after install.
   - Pre-existing skill: Patch in-place on first kit install (whether the skill was installed by kit previously or by the user manually).
2. **Backup on patch:** Back up the original `SKILL.md` (before patch) to `~/.caveman-kit/backup/SKILL.md.bak` before modifying.
3. **Mutation acceptable:** Patching the frontmatter is acceptable even if the skill is symlinked into `~/.claude/skills/caveman/` from a shared skill store — the patch does mutate the shared source through the symlink. This is accepted: `uninstall.sh` restores the backup, removing the patch from the shared source again.
4. **Uninstall behavior:** On `uninstall.sh`, restore the backed-up `SKILL.md` to its original state (remove the patch). If the skill was auto-installed by kit, also remove it entirely.
5. **Idempotent patching:** If the patch is already present (e.g., kit run twice), skip re-patching to avoid corrupting the frontmatter.
6. **Write-order and failure policy:** `install.sh` writes `manifest.json` with `skillInstalledByKit` set **before** attempting the frontmatter patch. If the patch step fails (parse error, disk write failure), install.sh does not roll back the already-installed skill or abort the whole install — it prints a non-fatal warning (`warning: failed to patch SKILL.md frontmatter — skill installed without disable-model-invocation`) and continues. This guarantees the manifest always reflects reality, so `uninstall.sh` can correctly find and remove/restore the skill regardless of whether the patch succeeded.

**Consequences:**

- **Security posture:** caveman skill hooks run as declarative metadata (read-only context injection), not executable agent code.
- **Shared store side effect:** Patching a symlinked skill mutates the shared source directly; every agent it's linked into sees the patched frontmatter while kit is installed, and loses it again on uninstall. Users relying on the patched version across multiple agents should keep kit installed or manually apply the patch.
- **Partial-failure safety:** Because the manifest is written before the patch attempt, a failed patch never leaves an orphaned, untracked skill directory — uninstall always knows what to do with it.
- **Backup size:** `~/.caveman-kit/backup/SKILL.md.bak` adds ~6 KB per kit install. Uninstall cleans it up.
- **Frontmatter brittleness:** Naive string-based patching (search for `---` delimiter, insert key) will fail if SKILL.md format changes. Use YAML-safe parsing if possible, fall back to line-based edit with clear error on parse failure.
