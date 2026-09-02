# Manifest: SubagentStart hook parity (grilling 2026-09-01)

Design Decisions Reached During Grilling (cross-kit session run from peer-agent-kit) on `docs/research/caveman-kit-subagentstart-parity-2026-09-01.md` (peer-agent-kit's research note, written from that repo, identifying that caveman-kit only registers SessionStart/UserPromptSubmit and proposing SubagentStart parity). The ADR below is ground truth; this file is only a pointer list for critic review.

- docs/adr/0005-deliver-mode-to-subagents-via-subagentstart.md

Scope note: the source research doc only proposed a settings-patch.js/settings-unpatch.js registration diff. During grilling, direct inspection of `hooks/caveman-activate.js` found it still emits plain stdout (no JSON `hookSpecificOutput` envelope, no `hook_event_name` echo) — the same intermediate state peer-agent-kit shipped in commit 3e19e18 before commit 91270b4 fixed it. Registration alone would silently deliver nothing to subagents. The ADR's decision includes the hook-script output-format fix and matching test additions, not just the registration diff.

Also verified during grilling: caveman's SKILL.md mode table rows and examples are already fully self-contained per mode (no "everything in lite"-style forward reference), so peer-agent's separate 9b7afc8 ruleset-content fix has no analog needed here.

Not yet implemented: this manifest/ADR only records the decision. Code changes (settings-patch.js, settings-unpatch.js, caveman-activate.js, tests/*.bats, install.sh/uninstall.sh/README.md docstrings) are pending critic review and then implementation.

---

## Session Ledger

| Role         | Outcome                        |
|--------------|--------------------------------|
| orchestrator | —                              |
| planner      | skipped (pickup of active ADR) |
| critic #1    | approve (minor)                |

## Critic Review

- **Final verdict:** approve
- **Severity:** minor
- **Iterations used:** 1 of ∞ (backstop 10)
- **Approval status:** ✓ Automatically approved by critic. No manual review required.
- **Risks / questions (open minors, advisory):**
  - ID-001..ID-006: applied to ADR 0005 during finalize (Decision 2 scope tightened to envelope/hookEventName only; Decision 4 extended with lib header comments + console log lines; off-mode SubagentStart consequence added; cwd-in-SubagentStart citation added). ID-004 (alleged typo) not reproducible — ADR already read "SessionStart or SubagentStart".
  - ID-007 (open): ADRs 0001–0003 lack `lineage-rules` frontmatter — legacy exception applies; optional housekeeping to add `lineage-rules: exempt`, out of scope for ADR 0005.
