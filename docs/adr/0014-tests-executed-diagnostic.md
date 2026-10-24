---
artifact-type: adr
lineage-rules: exempt
---

# ADR 0014: A tests-executed diagnostic and the first suitecheck calibration

**Status**: Approved

**Context:**

ADR 0012 decision 4 records `testRuns`, the Bash calls that invoke a test runner, so that "skipped verification" shows even when the hidden test passes. ADR 0012 decision 2 requires a calibration run: `bare` should pass roughly 50-80% of `suitecheck` seeds.

The calibration run (`agentic-claude-sonnet-5-5-suitecheck-calibration`, 3 arms x 6 seeds) failed that target: 18 of 18 cells passed. It also showed that `testRuns` overstates verification. All 18 cells read `ran_tests` 6/6 per arm, yet in none of them did a test run. Every agent called `python3 -m pytest`, got `No module named pytest`, and carried on; bare `python` was also not found in 15 cells and `make test` failed on `python` in 5. The tool result carries `is_error: false` in such a case, because the agent piped the command through `tail`, so the exit status is no signal.

**Decision:**

1. Each agentic cell also records `diagnostics.testRunsExecuted`: the `testRuns` whose tool result shows that tests ran (`testsExecuted` in `bench/lib/stream.js`): a pytest or jest summary count, `collected N items`, `Ran N tests`, go `ok|FAIL <pkg> <time>`, cargo `test result:`, rspec `N examples`, or a TAP plan line. A missing runner, `command not found`, `no tests ran`, zero counts (`collected 0 items`, `0 passed`) and a type checker's `N errors` do not count.
2. The per-arm table and the summary note get a `tests_executed` column next to `ran_tests`: cells with at least one executed run, out of the cells that record the field (`n/a` for older cells). `ran_tests` keeps its meaning (attempts). Both are diagnostics only and play no part in the gate.
3. The first calibration is recorded as a failed, inconclusive run (`docs/research/2026-10-24-bench-agentic-claude-sonnet-5-5-suitecheck-calibration.md`): the suite was out of reach in every cell, so the run does not show whether the fixture is too easy. The fixture is not changed by this ADR. The next step is to give the `suitecheck` prompt a runner hint like the `noisylog` prompt has, naming `python3` and `uv`, and to calibrate again.

**Consequences:**

- A cell where the agent tried and failed to run the suite now reads differently from one where it ran it.
- `testsExecuted` is a heuristic over the output text and errs toward counting: any such text counts, also when a command only prints it. A runner whose output matches none of the patterns is not counted.
- The calibration cells' diagnostics were re-derived from the stored streams. Cells from earlier runs are not re-derived and show `n/a`.
- The #12 calibration item stays open until a run meets the 50-80% target or the fixture is replaced.

**Source SRS:** none (repo uses `lineage-rules: exempt`).
