---
artifact-type: design-review
---

# Design Decisions Reached During Grilling: ultracave onboarding and unpinned skills

These ADRs record design decisions reached during a grilling session on 2026-10-29. Background: `docs/research/2026-10-29-ultracave-alias-and-ultra-mode.md`. Review them for contradictions, blind spots and edge cases. Edit the ADR files directly.

- docs/adr/0020-onboard-ultracave-skill.md
- docs/adr/0021-unpin-skill-version.md

---

## Session Ledger

| Role         | Outcome                 |
|--------------|-------------------------|
| orchestrator | —                       |
| planner      | complete (2 revisions)  |
| critic #1    | revise (major), 5 open major |
| critic #2    | revise (major), 2 open major |
| critic #3    | revise (major), 3 open major, convergence guard halted |

## Critic Review

- **Final verdict:** revise
- **Severity:** major
- **Iterations used:** 3
- **Approval status:** Requires manual review and approval. Convergence guard halted: major count did not decrease (2 to 3).
- **Open majors:**
  - Legacy two-run migration (old then new `update.sh`) has no sequence or state diagram (ADR 0021).
  - Tag-lookup failure aborts `install.sh` when only `ultracave` is missing, contradicting "an `ultracave` failure never blocks install" (ADR 0020 decision 6 and Consequences).
  - A partial `ultracave` directory (no `SKILL.md`) is recorded `false` on the next update and never retried (ADR 0020 decisions 5 and 7).
- **Open minors:** drop or justify persisted `skillRefOverride`; legacy `skillInstalledByKit: false` has no step that records `false` in the update flowchart; `skillRef` unspecified for ultracave-only and pending installs; ADR 0020 decision 7 lacks a cross-reference to the two-run migration; user-deleted kit-owned `ultracave` dir with unchanged tag is unaddressed; both ADRs are `lineage-rules: exempt` (informational).

---

## Session Ledger (final)

| Role         | Outcome                                  |
|--------------|------------------------------------------|
| orchestrator | —                                        |
| planner      | complete (4 revisions)                   |
| critic #1    | revise (major), 5 open major             |
| critic #2    | revise (major), 2 open major             |
| critic #3    | revise (major), 3 open major             |
| critic #4    | approve (minor), 0 open major            |

## Critic Review

- **Final verdict:** approve
- **Severity:** minor
- **Iterations used:** 4
- **Approval status:** Automatically approved by critic at minor severity. Minor items below are not yet addressed.
- **Ledger note:** the pass-4 `upsert` rejected one informational line (unprefixed), so ledger file `plans/critic-ledger-baf99b73-001a-47af-ac3b-2661d896b299.json` reflects through pass 3 only.
- **Open minors (not fixed):**
  - ADR 0021 flowchart: legacy absent-field `false` path unreachable through gate O.
  - ADR 0020 hook flowchart: missing second lookup root.
  - ADR 0020 ownership flowchart: missing `true`-with-missing transition.
  - Test inventory sits inside an architecture decision (ADR 0020 decision 10).
  - Release-note `npx` command has no tag; it would install upstream `main`.
  - `skillRef` can be saved with no kit-owned skill reinstalled.
  - Wrong cross-reference: ADR 0020 decision 4 points to ADR 0021 decision 6, should be decision 5.
  - ADR 0021 decision 8 "self-contained" overstates skew safety.
  - Null with ultracave present not recorded `false` on lookup failure.
  - Hidden `CLAUDE_CONFIG_DIR` assumption at hook runtime.
  - Upgrade can reinstall a user-deleted kit-owned `ultracave`.
  - Empty qualifying tag set undefined.
  - Downgrade policy undefined.

---

## Final status (after pass 6)

Critic #6: approve (minor), 0 open major. Passes 5 and 6 followed the minor-fix round. Remaining minors (not fixed): release-notes deliverable not listed in ADR 0020 decision 10; `null` + hand-installed `ultracave` is deleted by uninstall until the next `update.sh`; no end condition when upstream permanently drops `ultracave` (repeating warning); persisted `skillRefOverride` is more machinery than a per-run env var.
