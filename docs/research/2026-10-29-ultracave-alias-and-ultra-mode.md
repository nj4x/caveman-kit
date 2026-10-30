# Is a missing `ultracave` skill critical for `/caveman ultra`?

Date: 2026-10-29. Kit HEAD: `a7b1605`. Upstream pin: `JuliusBrussee/caveman@v4.0.1`. Upstream `main` at `9b68f7e` (2026-10-25).

## Verdict

Not critical. Nothing errors, and the hooks keep working. But the kit's `ultra` mode has silently lost its ultra-specific rules. Today `ultra` injects the same ruleset as `full`, plus three kit-authored `ultra:` example lines. The missing `ultracave` skill is a symptom. The cause is that upstream moved ultra into a separate skill at v3.1.0, and the kit never adapted. Two related defects turned up as well (see "Other findings").

## 1. Does upstream ship `ultracave` / `megacave`?

Yes, from v3.1.0 onward.

- The `skills/` listing at v3.0.0 has no `ultracave` or `megacave` directory. Both appear at v3.1.0 and are still present at v3.2.0, v4.0.0, v4.0.1 and `main`. Source: `gh api repos/JuliusBrussee/caveman/contents/skills?ref=<tag>` (https://github.com/JuliusBrussee/caveman/tree/v4.0.1/skills).
- `skills/ultracave/SKILL.md` at v4.0.1 holds the ultra rules: fragments, one word when one word is enough, each fact once, cut conjunctions only when order survives. Its frontmatter sets `disable-model-invocation: true` and says "Invoke only with /ultracave or /caveman ultra" (https://github.com/JuliusBrussee/caveman/blob/v4.0.1/skills/ultracave/SKILL.md, lines 2-7, 26-48).
- `v4.0.1...main` is 124 commits ahead, but none of them touch `skills/caveman/` or `skills/ultracave/`. Source: `gh api repos/JuliusBrussee/caveman/compare/v4.0.1...main`. A pin bump would not change this picture.

## 2. Is the alias line a version mismatch?

No. The installed file matches the pin.

- `/Users/roman/.claude/skills/caveman/SKILL.md` is byte-identical to upstream `skills/caveman/SKILL.md@v4.0.1`. Source: `diff` against `gh api .../contents/skills/caveman/SKILL.md?ref=v4.0.1`, which printed no differences.
- The alias line is at `/Users/roman/.claude/skills/caveman/SKILL.md:19`. It already exists at v3.1.0, at line 19 of that version's file.
- The sibling-skill design is documented in `/Users/roman/.claude/skills/caveman/README.md:12-20` and `:67` (`../ultracave/`, `../megacave/`).
- The real mismatch is in install scope. `install.sh:106` and `update.sh:167` run `npx skills add "$SKILL_SOURCE" --skill caveman`, so only the `caveman` skill is installed. `/Users/roman/.claude/skills/` has no `ultracave` or `megacave` directory.
- History of the pin: `46377a3` bumped it to v3.0.0, `a8eec6c` (2026-10-10) to v3.2.0, and `f14f5f7` (2026-10-20) to v4.0.1. The last two commits are titled "Update install.sh" and have no ADR. The v3.0.0 to v3.2.0 bump crossed the v3.1.0 split.
- The backup `~/.caveman-kit/backup/SKILL.md.bak` is an older format with a 6-row intensity table, including `| **ultra** |` (lines 42-49). It does not match v3.0.0 byte-for-byte. It does not match v2.5.0-v2.7.0 either. I did not identify which version it is.

## 3. What is lost when ultra comes from the hook instead of `ultracave`

### Kit hook path (SessionStart / SubagentStart)

- `hooks/caveman-activate.js:60` reads only `skills/caveman/SKILL.md`.
- `hooks/caveman-activate.js:89-104` keeps a mode's intensity-table row (`^| **<mode>** |`) and its `- <mode>:` example lines, and drops the rows and examples of other modes.
- Upstream removed the intensity table from `caveman/SKILL.md` at v3.1.0. v3.0.0 has 6 `| **…** |` rows; v3.2.0 and v4.0.1 have 0. The installed file has no `^|` lines at all.
- Net result for `ultra`: the generic caveman rules (`SKILL.md:9-84`, the same text `full` gets), plus the three `- ultra:` lines from `hooks/caveman-examples.md:4,9,14`. The `ultracave` rules are never injected: fragments, one-word answers, each fact once, cut-again.
- `lite` lost its row too. `lite`, `full` and `ultra` now differ only in the kit's example lines.
- Upstream's own hook does it differently. It maps `ultra` to `ultracave` (`src/hooks/caveman-activate.js@v4.0.1:82`, `LEGACY_MODES`) and loads that skill's ruleset (`:385-391`), so the upstream stack would deliver the ultra rules. The kit replaces those hooks.
- The alias line never reaches injected context. It contains the word "wenyan", so `hooks/caveman-activate.js:101` (`if (/wenyan/i.test(line)) return acc;`) drops it. This is consistent with the SubagentStart context this session received: its Persistence section has no alias sentence. The hook path therefore never points the model at the missing skill.

### Slash-command path (`/caveman ultra`)

- Claude Code loads the full `caveman/SKILL.md`, alias line included. The model is told to "follow the `ultracave` … skill instead of this one".
- That skill is not installed. Even if it were installed, `disable-model-invocation: true` (ultracave `SKILL.md:7`) means the model cannot load it through the Skill tool. Only the user's `/ultracave` command can.
- The model then falls back to the caveman text plus the hook's `ultra` level. The mode tracker still records `ultra` (`hooks/caveman-config.js:10`, `hooks/caveman-mode-tracker.js:27-28`).
- So the user sees no error, only weaker compression. Upstream's README measured ultracave at 35% fewer output tokens and caveman at 3% (`/Users/roman/.claude/skills/caveman/README.md:10`: single run, opus, output length only).

## 4. Does the kit need a change?

Yes, but none of these changes is an emergency.

1. **Restore ultra semantics.** One option: install `ultracave` alongside `caveman`, and have `caveman-activate.js` read `skills/ultracave/SKILL.md` for mode `ultra`.
   - This adds an install-time mutation. Per CLAUDE.md it needs a backup, a manifest field, and an uninstall path, plus a new ADR.
   - Check whether `npx skills add` accepts more than one `--skill`. I did not verify this.
   - The other option is a kit-authored ultra supplement next to `hooks/caveman-examples.md`, which avoids the new third-party install.
   - Either way, decide what `lite` means now that its row is gone.
2. **ADR 0006 stripping is stale.** The regexes at `hooks/caveman-activate.js:83-87,101` target v3.0-era `wenyan-*` text. In v4.0.1 the only "wenyan" mention is the alias line, and stripping it is accidentally right.
   - ADR 0006 (`docs/adr/0006-drop-wenyan-support.md:16`) says users "can invoke it directly". At v4.0.1 that means a `megacave` skill, which is not installed.
   - The ADR text should be updated or superseded to match.
3. **Test fixture hides the regression.** `tests/caveman-activate.bats:20-40,102,112` asserts against a fixture with an intensity table and a `| **ultra** |` row. That is the pre-v3.1.0 format, so the suite passes while real ultra injection has no ultra rule. Add a fixture in the v4.0.1 shape.
4. **A pin bump does not help.** `main` has no changes to these skills. Pinning back to v3.0.0 would restore the table but give up the v3.1+ ruleset.

## Other findings (outside the question)

- **The ADR 0002 frontmatter patch is gone from the installed skill.** `/Users/roman/.claude/skills/caveman/SKILL.md:1-7` has no `disable-model-invocation` key, which is why `caveman` shows up in the available-skills list.
  - Cause: `update.sh:163-171` reinstalls the skill with `npx skills add` (manifest `skillInstalledByKit: true`, `~/.caveman-kit/manifest.json`), but it never re-runs `lib/skill-patch.js`. Only `install.sh:172-176` does.
  - So every `update.sh` run that upgrades the skill drops the patch. This breaks ADR 0002 decision 1 (`docs/adr/0002-frontmatter-patch-disable-model-invocation.md:15-17`).
- **The SKILL.md backup is stale.** `~/.caveman-kit/backup/SKILL.md.bak` is still the pre-v3.1 file. `uninstall.sh` restores SKILL.md frontmatter from this backup (CLAUDE.md, Architecture section 1), which would put old frontmatter on a v4.0.1 body. I have not verified how `uninstall.sh` merges them.
