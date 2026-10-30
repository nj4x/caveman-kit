---
artifact-type: design-review
---

# Design Decisions Reached During Grilling: desktop badge mod

This ADR records the design decisions reached during a grilling session on 2026-10-29 about showing the caveman mode badge in the desktop app's Code tab with a separately installed mod. Background: `docs/research/2026-10-29-claude-code-plugins-cli-vs-desktop.md` (sections 3 and 5). Review it for contradictions, blind spots and edge cases, and check it against ADR 0003 and ADR 0004. Edit the ADR file directly.

- docs/adr/0022-desktop-badge-mod.md

---

## Session Ledger

| Role         | Outcome                                  |
|--------------|------------------------------------------|
| orchestrator | —                                        |
| planner      | complete (2 revisions)                   |
| critic #1    | revise (major), 1 open major             |
| critic #2    | revise (major), 3 open major, convergence guard halted |

## Critic Review

- **Final verdict:** revise
- **Severity:** major
- **Iterations used:** 2 of ∞ (backstop 10)
- **Approval status:** Requires manual review and approval. Convergence guard halted: the open-major count rose from 1 to 3. ID-001 (stale badge after uninstall) is fixed. The three new majors were minors in pass 1 and were promoted in pass 2.
- **Open majors:**
  - Per-tick flag resolution (Decisions 9–11) has no flowchart; the outcome of a skipped symlinked `.claude/` or flag is not shown.
  - Decision 9 promises a 16-byte read cap that `$.fs.read` cannot enforce (research 5.2); not recorded as a deviation in Decision 10.
  - The double-badge premise on desktop is untested: the Decision 7 prototype does not check whether the desktop Code tab already renders the patched `statusline.sh`.
- **Open minors:** prototype gate has no flowchart; subprocess reuse of `caveman-config.js` not weighed as an alternative; symlinked `.claude/` outcome missing from the parity table; poll restart after a module reload unspecified; Consequences claims kit/mod same-release lockstep that Decision 3 cannot enforce.

---

## Final status (after pass 3)

Critic #3: approve (minor), 0 open major. Pass 3 followed a manual fix round that added the per-tick resolution flowchart, the prototype gate flowchart (including the double-badge check), the stat-based 16-byte cap with its fallback deviation, the symlinked `.claude/` outcome, lazy timer restart, the rejected `$.process.run` alternative, and a reworded release-coupling consequence.

- **Approval status:** Automatically approved by critic at minor severity. Minor items below are not yet addressed.
- **Open minors (not fixed):**
  - Unconditional uninstall reminder is a small scope exception to Decision 4.
  - Shared parity table includes the two known shell-divergence rows; could run against the helper only, with shell parity as a follow-up.
  - Timer lifecycle has no state diagram.
  - No weighed alternative of a simpler global-flag-only v1.
  - Decision 12's injected interface omits size source, ancestors/cwd and configDir; the table tests helper logic, not runtime behavior.
  - The ADR does not say how a `--plugin-dir` prototype reaches the desktop Code tab.
  - The `AbovePrompt` fallback has no visibility check, and no outcome is defined when neither site shows.
  - `$.fs.list` entry size not considered before accepting an unbounded read.
  - No failure policy: any error should count as mode none and return `next(e)` unchanged so native labels survive.
