# ADR 0001: Auto-install caveman skill on missing prerequisite

**Status:** Accepted

**Context:**

caveman-kit installer requires `$CLAUDE_CONFIG_DIR/skills/caveman/SKILL.md` to exist before proceeding (checked at `install.sh:36-41`). If missing, install fails with a GitHub URL pointing to the caveman repo.

Users approaching the install will encounter a three-step manual workflow:
1. Install caveman skill via `npx skills add JuliusBrussee/caveman`
2. Run `caveman-kit/install.sh`
3. Restart Claude Code

This friction is avoidable: caveman-kit's own hooks never invoke the caveman CLI binary, proxy, or MCP server. They only read the skill's `SKILL.md` file. The lightweight skill-only install path exists in upstream (`npx skills add JuliusBrussee/caveman`, ~0 MB, ~10 seconds), and caveman-kit can trigger it automatically with user consent.

**Decision:**

1. **Detect and offer auto-install:** If `$CLAUDE_CONFIG_DIR/skills/caveman/SKILL.md` does not exist when `install.sh` runs, offer automated installation via `npx skills add JuliusBrussee/caveman@v2.2.0 --skill caveman -g -y --copy`.
2. **Require explicit consent:** 
   - Interactive (TTY): Prompt `Install caveman skill? (y/N)`. Decline exits with current error+URL message.
   - Non-interactive: Require `CAVEMAN_KIT_INSTALL_SKILL=1` environment variable or `--install-skill` shell argument to proceed. Without it, exit with error+URL.
3. **Version pin:** Pin to `@v2.2.0` to match caveman repository version. Bump explicitly when caveman tags a new release.
4. **Fallback on failure:** If auto-install fails (npx missing, network down, `skills add` exits non-zero), fall back to current error+URL message. Do not hard-fail with raw npx error.
5. **Copy, don't symlink:** Use `--copy` flag so kit receives a private copy of `SKILL.md`, avoiding mutation of shared skill store when patching frontmatter later.
6. **Track auto-install in manifest:** Record `"skillInstalledByKit": true` in `~/.caveman-kit/manifest.json` if kit performed the install.

**Consequences:**

- **Friction reduced:** Single command `caveman-kit/install.sh` completes both skill and kit setup interactively.
- **Non-interactive CI/automation:** Scripts, Docker, and CI must either set `CAVEMAN_KIT_INSTALL_SKILL=1` or pre-stage the skill manually.
- **Skill ownership:** caveman-kit takes responsibility for installing and uninstalling the skill it auto-added; pre-existing installs are never removed.
- **Uninstall symmetry:** `uninstall.sh` removes skill only if `"skillInstalledByKit": true`; otherwise leaves it in place.
- **Trust boundary:** User sees a prompt before third-party skill (JuliusBrussee/caveman) is fetched and injected. Manual `npx` runs or CI override require explicit opt-in.
- **Version drift risk:** Pinning means caveman-kit must stay in sync with upstream skill format changes. Future caveman releases may break older kit versions silently if they change SKILL.md structure.
