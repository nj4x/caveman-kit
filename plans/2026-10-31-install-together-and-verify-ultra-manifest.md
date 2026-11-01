---
artifact-type: design-review
---

# Design Decisions Reached During Grilling: install both skills together, verify the `ultra` ruleset

These ADRs record design decisions reached during a grilling session on 2026-10-31. They answer two questions: can `caveman` and `ultracave` install in one call, and how does the kit verify that `ultra` mode uses the real `ultracave` skill. Related, already accepted: `docs/adr/0020-onboard-ultracave-skill.md`, `docs/adr/0021-unpin-skill-version.md`. Review them for contradictions, blind spots and edge cases. Edit the ADR files directly.

- docs/adr/0025-install-both-skills-in-one-call.md
- docs/adr/0026-verify-the-active-ultra-ruleset.md

---

## Session Ledger

| Role         | Outcome                      |
|--------------|------------------------------|
| orchestrator | —                            |
| planner      | complete (2 revisions, then 2 orchestrator fixes) |
| critic #1    | revise (major), 2 open major |
| critic #2    | revise (major), 1 open major |
| critic #3    | revise (major), 2 open major |
| critic #4    | revise (major), 1 open major |
| critic #5    | approve (minor)              |

## Critic Review

- **Final verdict:** approve
- **Severity:** minor
- **Iterations used:** 5
- **Approval status:** ✓ Approved by critic.
- **Risks / questions:**
  - [minor] ADR 0025 adds many case rules for a modest saving; the two-call path stays as the named fallback.
  - [minor] ADR 0025 flowchart: the single-skill branch has no edge into the presence/exit judgment, though decisions 2-4 apply to it.
