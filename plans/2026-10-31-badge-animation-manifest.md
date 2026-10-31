---
artifact-type: design-review
---

# Design Decisions Reached During Grilling: desktop badge bone animation

These are the design decisions reached during a grilling session on 2026-10-31 about animating the desktop badge chip (bones fall and re-stack at random moments, bone colors change) and about playing a sound on the fall (rejected). Background: ADR 0022 (desktop badge mod), ADR 0023 (bone chip) and `docs/research/2026-10-29-claude-code-plugins-cli-vs-desktop.md` (section 5, redraw throttle and timers). Review it for contradictions, blind spots and edge cases, and check it against ADR 0022 and ADR 0023. Edit the ADR file directly.

- docs/adr/0024-desktop-badge-bone-animation.md

---

## Session Ledger

| Role         | Outcome                  |
|--------------|--------------------------|
| orchestrator | —                        |
| planner      | skipped (pickup)         |
| critic #1    | approve (minor)          |
| critic #2    | approve (minor), after the manual fix pass |

## Critic Review

- **Final verdict:** approve
- **Severity:** minor
- **Iterations used:** 1 of ∞ (backstop 10)
- **Approval status:** ✓ Automatically approved by critic. No manual review required.
- **Follow-up (2026-10-31):** all twelve minors below were fixed in a manual pass. Two of them changed the design. The ticker is now one always-on design, and the timer probe is dropped. A fall in progress is now cancelled while the band is hidden. The ADR was not re-reviewed after this pass.
- **Risks / questions (minors from critic #1, now fixed):**
  - The Decision 10 tick tree does not schedule the first `nextFallAt` and does not reset on a mode change. Both are in prose only.
  - A fall cancelled by a mode change does not reschedule `nextFallAt`, so a new fall can start on the next tick.
  - Bone color while falling is unspecified: `planFall` has no landed-color input.
  - It is unclear whether `chipSvg(mode, landed)` with `landed` unset equals `chipSvg(mode)` (the `0.2.0` output).
  - Decision 9 gives two ticker starters, and Decision 6 calls the poll "unchanged" while giving it a new duty. The amendment of ADR 0022 Decision 12 (state in `register.tsx`) is not recorded in Status.
  - The WCAG 2.2.2 reasoning treats each fall as separate content, but the motion recurs all session.
  - Check 8(a) does not cover the hover label or `alt` across frame swaps.
  - No end state if no palette is legible (fall back to single `#B07A4B`).
  - No runtime failure policy for the animation path.
  - The fall state while the band is hidden (survey) is unspecified, and so is the reset across module reloads.
  - The two timer designs could be one (always-on ticker).
  - The gate flowchart omits the timer probe.

## Critic #2 (2026-10-31)

- **Verdict:** approve (minor). There are 0 open majors.
- **Open minors (not fixed):**
  - The band can be hidden while the chip is at rest. The next fall time is never pushed forward then, so a fall can start the moment the band returns.
  - `landed` and `landedFrame` are two names for one state. The reset rules for `landedFrame` are incomplete.
  - The tick transitions live in the untested `register.tsx`. A pure step function in `chip.mjs` would make them testable. The Status claim that every computation stays pure overstates this.
  - The opt-out still runs the 125 ms ticker, unlike `0.2.0`. The ADR does not say how the opt-out takes effect (reload or restart).
  - It is not said whether an OS reduced-motion preference is in scope.
  - Gate check (a) does not verify that typing, the caret and IME composition survive the redraws during a fall.
  - What vacated solid slots show during a fall is unspecified.
  - The fade-out fallback for check (b) needs an `opacity` field in each frame.
  - The test list conflicts on the last frame. There is no landing-frame color test and no 16-frame cap test, and it is unclear whether 16 is a hard cap or a starting value.
  - ADR 0022 and ADR 0023 get no "amended by ADR 0024" status note.

## Follow-up after critic #2 (2026-10-31)

All ten minors above were fixed by hand in ADR 0024. The ADR was not re-reviewed after this pass.

- A countdown no longer runs while the band is hidden. A fresh delay starts when the chip is drawn again.
- `landed` is the single resting-state variable. The transitions moved into a pure `stepAnimation(state, event, rng)` in `chip.mjs`, with its own bats cases.
- The opt-out stops the ticker from starting. The variable takes effect after an app restart or plugin reload. OS reduced-motion is out of scope.
- Prototype check (a) also covers typing, caret, focus and IME composition.
- A solid slot whose bone is away draws nothing.
- Frames carry an `opacity` field (1 as shipped) for the fade-out fallback.
- The test list is fixed: the last frame is the resting stack, with landing-color and 16-frame-cap cases.
- The 16-frame limit is a hard cap.
- The status lines of ADR 0022 and ADR 0023 get an "amended by ADR 0024" note once 0024 is accepted.
