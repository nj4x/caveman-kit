# Design Decisions Reached During Grilling: bench harness and Context Diet

Design decisions reached during grilling (source: `docs/research/chisle-complementary-features.md`, candidates 3 and 5). Each ADR is the ground truth; this list only points to them.

- docs/adr/0008-live-benchmark-harness-in-bench.md
- docs/adr/0009-context-diet-supplement-section.md

---

## Session Ledger

| Role         | Outcome                  |
|--------------|--------------------------|
| orchestrator | —                        |
| planner      | complete                 |
| critic #1    | revise (major)           |
| critic #2    | approve (minor)          |

## Critic Review

- **Final verdict:** approve
- **Severity:** minor
- **Iterations used:** 2 of unlimited (backstop 10)
- **Approval status:** Automatically approved by critic. No manual review required.
- **Risks / questions (all minor, advisory):**
  - Single-turn gate does not map each candidate arm to its reference arm, and Decisions 7 and 8 differ on whether both co-primary metrics must improve or one may only not regress.
  - The agentic bare arm costs 12 to 24 paid runs but feeds no gate decision.
  - The bare arms conflict with "every arm runs real hooks" (Decision 3).
  - The 3-then-6 seed rerun is a second look at the data and inflates the false-positive rate of a nominal 95% interval. Justify it or pre-register 6 seeds.
  - Context Diet ships to every mode except `off` but is measured only in `full`.
  - Output tokens are not part of the agentic gate, yet grep-first reading could add turns and output.
  - Gate scope does not say whether per-turn reminder changes are gated, or whether the shipped `e11e665` focus directive is reverted if its arm regresses.
  - No fixture floor: the 12/24-pair arithmetic assumes all four fixtures, and Decision 5 allows dropping fixtures.
  - ADRs 0001 to 0003 have no `lineage-rules` key (informational).
