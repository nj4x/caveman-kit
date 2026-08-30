# ADR 0003: Uninstall symmetry and manifest-based tracking

**Status:** Accepted

**Context:**

caveman-kit's install flow modifies multiple system files:
- `~/.claude/settings.json` (injects hook entries)
- `~/.claude/statusline.sh` (injects badge block, if it exists)
- `~/.claude/skills/caveman/SKILL.md` (patches frontmatter)
- `~/.claude/skills/caveman/` directory itself (if auto-installed by kit)

Today, `uninstall.sh` restores `settings.json` and `statusline.sh` from backups, but has no tracking for what it installed vs. what was pre-existing. If uninstall is ever extended to remove the skill, it must distinguish:
- Skill auto-installed by kit → remove it entirely
- Skill pre-existing → restore only the frontmatter patch, never remove

Similarly, `install.sh` must track whether it auto-installed the skill so uninstall can act correctly later.

**Decision:**

1. **Extended manifest:** `~/.caveman-kit/manifest.json` records:
   - `installedAt`, `claudeDir`, `settingsBackup`, `statuslineBackup`, `pluginRoot` (existing)
   - `skillInstalledByKit: boolean` (new) — true if kit ran auto-install, false if skill was pre-existing
   - `skillBackup: string | null` (new) — path to backed-up `SKILL.md`, or null if skill was not patched
2. **Uninstall logic:**
   - If `skillInstalledByKit === true`: Remove `$CLAUDE_CONFIG_DIR/skills/caveman/` directory entirely, including `SKILL.md`.
   - If `skillInstalledByKit === false` and `skillBackup` is set: Restore backed-up `SKILL.md` to remove the patch, leave directory in place.
   - Always restore `settings.json` and `statusline.sh` from backups as today.
3. **Idempotent manifest updates:** If `install.sh` runs twice (user forgets to uninstall first), it will error at the check `[ -d "$KIT_HOME" ]` before touching the manifest. No double-write risk.
4. **Pre-existing install detection:** `install.sh` checks for `SKILL.md` existence and backup state to infer `skillInstalledByKit`. If install created the skill, set flag to true. If it already existed, set to false and only back it up if patching is needed.

**Consequences:**

- **Complete reversal:** Uninstall is now symmetrical — leaves no traces of kit's changes or auto-installed skills.
- **Manifest as source of truth:** Uninstall depends on manifest correctness. If manifest is corrupted or lost, uninstall cannot know which skill to remove and will err on the safe side (restore only, never remove).
- **Lost manifest recovery:** If `~/.caveman-kit/manifest.json` is deleted but `~/.caveman-kit/` remains, `install.sh` will error (already-installed check). User must manually `rm -rf ~/.caveman-kit` and re-run, or reconstruct manifest by hand.
- **Upgrade path:** Future major caveman versions can compare manifest version and auto-migrate on `install.sh` re-run if schema changes.
