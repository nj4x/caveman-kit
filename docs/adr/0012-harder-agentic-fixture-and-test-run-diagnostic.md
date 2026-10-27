---
artifact-type: adr
lineage-rules: exempt
---

# ADR 0012: A harder agentic fixture and a test-run diagnostic

**Status**: Approved

**Context:**

ADR 0008 decision 7 makes the hidden-test pass rate the agentic guardrail: a ruleset change must not lower it. In both agentic runs so far (8c90768 and b56c077) every cell passed in every arm, 144 of 144 (`docs/research/2026-10-23-bench-compare-8c90768-vs-b56c077.md`). On the four fixtures of ADR 0008 decision 5 the guardrail cannot tell arms apart, so a quality regression would go unseen (issue #12).

There is a concrete case. On `bigfile`, the Context Diet arm skipped running tests in 9 of 12 cells, against 5 of 12 for `full` (`docs/research/2026-10-23-context-diet-prompt-improvements.md`). The hidden test still passed, so nothing in the cell records showed it.

**Decision:**

1. Add a fifth fixture, `suitecheck`, under the rules of ADR 0008 decision 5: the same pinned `nj4x/anthrouter` commit as the other anthrouter fixtures, a planted patch, and an offline hidden test. The patch makes `pace.period_workday_dates` treat the exclusive UTC period end as inclusive, in the code and in its docstring. A zone at UTC+0 then gains the first day of the next month. The prompt reports only the UTC symptom (23 workdays in September 2026 instead of 22). The direct fix, ending the date loop one day early, makes the UTC count right but drops the edge days of other zones. It fails 13 of the 30 tests in the repo's own `tests/test_pace.py`, and only running that suite shows it. A fix that special-cases the `UTC` zone name passes the suite but misses other UTC+0 zones. The hidden test checks UTC, `Europe/London` in winter, `America/Los_Angeles` and `Europe/Berlin`.
2. The fixture is meant to make the bare arm fail some seeds (target: a bare pass rate of roughly 50-80%), so that a drop in pass rate is detectable. A calibration run of the bare arm checks this. If bare still passes every seed, the fixture does not meet this decision: change it or replace it, and record the change. A fixture that is not reliable offline is dropped, as ADR 0008 decision 5 says.
3. The default agentic fixture set becomes five fixtures, so 3 seeds give 15 gate pairs instead of 12. The gate rule (ADR 0008 decision 8, ADR 0010) is unchanged. Earlier runs used four fixtures. Their committed cells stay as they are, and `--fixtures bigfile,noisylog,reuse,rootcause` reproduces their fixture set. ADR 0013 decision 4 later raised the default set to six, and ADR 0015 to seven.
4. Each agentic cell records `diagnostics.testRuns`: the number of Bash calls whose command invokes a test runner (`bench/lib/stream.js`, `isTestCommand`). The per-arm table and the summary note show `ran_tests`, the cells with at least one test run out of the cells that record it. It is a diagnostic only and plays no part in the gate, like the other diagnostics of ADR 0008 decision 7.

**Consequences:**

- An agentic run costs about 25% more: 45 runs instead of 36 at 3 seeds.
- "Skipped verification" is visible per arm even when the hidden test passes.
- `testRuns` is a heuristic over the command text, and it errs toward counting. A test runner called from inside a script the agent wrote is not counted. An unquoted bare runner name inside another program's arguments (`cat pytest.ini`, `rg -n pytest`) is not counted, but a quoted one (`rg "pytest" .`) is. A two-word form such as `make test`, `make check` or `python -m pytest` counts wherever it appears. Both can overstate test runs (`grep "make test" Makefile`).
- Until a calibration run confirms decision 2, the guardrail is still not shown to detect a drop.

**Source SRS:** none (repo uses `lineage-rules: exempt`).

## Outcome (issue #12)

Decision 2's target (a bare pass rate of roughly 50-80%) was not met by any fixture design. Before `tierslot`, ten recorded calibration runs (the `calibration` notes in `docs/research/`; the unrecorded `retryafter-calibration-5` is excluded) across `suitecheck`, `retryafter` (four designs) and `adminalias` (two prompts) gave `bare` 6/6 or 12/12 in every run except one `retryafter` run with no end-to-end sentence, which gave 0/4. The `tests_executed` diagnostic (decision 1) did show skipped verification per arm, which this ADR asked for. The guardrail is therefore still not shown to detect a drop. Fixtures `retryafter` and `adminalias` are kept in `bench/fixtures/` but left out of the default set (ADR 0015, ADR 0017). Issue #22 added `tierslot` (ADR 0018); its second calibration gave `bare` 2/6, still outside the band, and it is also left out of the default set. Issue #12 ends with the target not met. The guardrail keeps ADR 0016's non-inferiority margin, and `bench/README.md` states its limit.
