---
artifact-type: adr
lineage-rules: exempt
---

# ADR 0016: Hidden-test guardrail with a non-inferiority margin

**Status**: Approved

**Context:**

ADR 0008 decision 7 states the agentic guardrail as "the hidden-test pass rate must not drop". `bench/lib/stats.js` implemented it as a strict inequality over paired cells: one net failed `full-diet` cell, however many pairs passed, gave `no-ship`. The same flag also blocked `ship`, so it decided both verdicts.

With a true pass rate p equal in both arms (no regression) and independent per-arm pass counts, the strict rule fires with probability P(Bin(n,p) for `full` > Bin(n,p) for `full-diet`). At p = 0.65 that is 33% at 3 pairs, 38% at 6 and 41.5% at 12 (`node bench/replay-gate.js`, exact table). More seeds raise the false-alarm rate, because a tie gets rarer. Issue #12 tried to work around this by finding a fixture where `bare` passes 50-80% of seeds (`suitecheck`, `retryafter`); none landed in range, and that search answered a different question anyway, since the gate pairs `full-diet` against `full` and `bare` feeds no verdict. Issue #18 asked for a rule that tolerates seed noise.

Every committed `full`/`full-diet` cell passes its hidden test (96 of 96 cells, 48 pairs, over the four original fixtures in the two committed runs, plus every calibration run), so no committed run shows the false alarm. The replay note records this (`docs/research/2026-10-25-gate-guardrail-replay.md`).

**Decision:**

1. The guardrail is a non-inferiority margin on paired passes. Let net = `full` passes minus `full-diet` passes over the paired cells. The guardrail fires (`no-ship`, no escalation) when net > ceil(0.1 × pairs). With 9 pairs the margin is 1, with 12 it is 2, with 21 it is 3, with 42 it is 5. `stats.passMargin` and `stats.passGuardrail` are pure functions; `agenticGate` takes `opts.passMarginRate` for tests, and the runner never sets it.
2. The gate output's `pass` block gains `net`, `margin`, `lower` and `discordant` (pairs that disagree, per direction). The console report, the summary note and both verdict reasons name the net drop and the margin, so a reader can check the arithmetic from the note alone.
3. `bench/replay-gate.js` re-judges every committed run, and every 3-seed subset of it, under both rules and prints the verdict flips, followed by exact false-alarm and power rates at the replayed pair sizes. It reads cells only and spends no quota. Rule changes to the guardrail are checked with it before they land.
4. Alternatives not taken:
   - An exact one-sided sign test (McNemar) on the discordant pairs at α = 0.05 cannot reject with fewer than 5 discordant pairs, so at 9 to 21 pairs it would wave through 4 net failures out of 4 discordant pairs. The margin rule fires there.
   - Partial credit from the pytest summary in `hiddenTest.tail`, and `diagnostics.tests_executed` (ADR 0014) as a paired signal, stay open. Neither is replayable on the committed cells: every `full` and `full-diet` summary reads "N passed" (the only failed summaries are four `bare` cells of `retryafter` calibration 2), and `diagnostics.testRunsExecuted` exists only in the single-fixture calibration cells; the four-fixture runs `8c90768` and `b56c077` predate ADR 0014 and lack it.
5. ADR 0008 decision 7 ("must not drop") and the ADR 0008 decision 8 ship rule now read with this margin. ADR 0008 is amended in place with a pointer here.

**Consequences:**

- Under independence the margin rule's false-alarm rate at p = 0.65 is 9.6% at 3 pairs, 18.1% at 6, 14.2% at 12 and 14.4% at 24, down from 33 to 44%. Power to see a drop from 0.65 to 0.40 is 27%, 51%, 59% and 77% at those sizes, down from 60 to 95%. The gate gives up 18 to 54 percent of its relative power (the most at 3 pairs) for a two- to threefold cut in false alarms; the escalation to 6 seeds (ADR 0010) recovers part of the power. Within-pair correlation (a fixture that is hard for both arms on the same seed) lowers both rates; the exact table is an upper bound.
- A `full-diet` run can now ship with one or two more failed cells than `full`. The note shows the counts, so a reader can still object to a specific drop.
- Fixture calibration against `bare` (ADR 0012 decision 2, ADR 0015) is no longer needed for the guardrail to work: a fixture with 100% pass in both arms contributes zero to net and leaves the margin alone.

**Source SRS:** none (repo uses `lineage-rules: exempt`).
