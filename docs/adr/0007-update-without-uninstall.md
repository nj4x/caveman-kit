---
artifact-type: adr
lineage-rules: exempt
---

# ADR 0007: In-place update without uninstall

**Status:** Accepted

**Context:**

Updating the kit or the pinned skill currently requires `uninstall.sh` followed by `bootstrap.sh`. This is disruptive: `settings.json` momentarily loses the caveman hooks, and the user must re-run bootstrap by hand. The building blocks for a gentler path already exist — the patch scripts (`lib/settings-patch.js`, `lib/statusline-patch.js`, `lib/skill-patch.js`) are idempotent and skip when already applied, and the unpatch scripts (`lib/settings-unpatch.js`, `lib/statusline-unpatch.js`) are exact structural inverses of their patch counterparts.

**Decision:**

Introduce `update.sh`, an in-place update mechanism that:

1. Checks whether the kit repo has new commits (`git fetch`, compare SHA against manifest).
2. Unpatches then repatches `settings.json` and `statusline.sh`, reapplying with new hook commands if they changed.
3. Copies updated `hooks/*.{js,md}` files to `~/.caveman-kit/hooks/`.
4. Optionally upgrades the skill when the pin changed and `skillInstalledByKit=true`.
5. Tracks the update via a new `kitSha` field in `manifest.json`.

Update-only mode: an existing `manifest.json` is required — first install still goes through `bootstrap.sh`. Inline unpatch+repatch avoids uninstall's momentary bare-config window.

**Consequences:**

- Users run `update.sh` instead of uninstall+bootstrap for day-to-day updates.
- Manifest gains a `kitSha` field, written after a successful update.
- Skill updates are automatic and passive (whatever the kit pins) when `skillInstalledByKit=true`.
- Failed updates are recoverable via re-run (idempotent) or manual uninstall+bootstrap.
- No new backup/rollback mechanism — relies on patch idempotency.
