# Bench agentic: agentic-claude-sonnet-5-5-tierslot-calibration-2

Date: 2026-10-27

This note was written by hand from the cell files. The run ended at the escalation prompt: no cell for seeds 7-12 exists, so the runner wrote no note. The tables below come from the bench's own report code. The cost gate is not a valid verdict here (see Gate); the calibration question is the `bare` row.

- Kind: agentic, fixture `tierslot` (ADR 0018), four-case hidden test (the lock case was dropped after calibration 1).
- Result: `bare` 2 of 6, `full` 1 of 6, `full-diet` 0 of 6. All 15 failing cells fail the same test, `test_alias_and_full_id_of_one_tier_share_the_slot`. Every failing agent fixed the opus symptom and passed the other three cases. They keyed the tier cache by the raw model string, so `sonnet` and `claude-sonnet-5-5` get separate slots. The prompt gives no hint that they must share one.
- The target (ADR 0012 decision 2) is a `bare` pass rate of roughly 50-80%. With 6 seeds the `bare` pass rate of 33% has a 95% interval of about 4% to 78%, so the observed rate (33%) is below the band and the interval does not exclude it.
- The order `bare` > `full` > `full-diet` (2, 1, 0 passes) is within noise at 6 seeds on one fixture.

## Run parameters

- Kind: agentic
- Model: claude-sonnet-5-5
- Seeds: 6
- Warmup before each cell (ADR 0010): on
- Kit dir and commit: not recorded
- Raw cells: /Users/roman/projects/caveman-kit/.claude/worktrees/12-retryafter-orphan-helper/bench/results/agentic-claude-sonnet-5-5-tierslot-calibration-2
- Cold starts (first request read 0 cached tokens): bare 0/6, full 0/6, full-diet 0/6
- SubagentStart hook fires per arm: bare 0 in 0/6 cells, full 0 in 0/6 cells, full-diet 0 in 0/6 cells; Task/Agent calls: bare 0, full 0, full-diet 0

## Gate

Paired difference is full-diet minus full, paired by fixture and seed; both cells must have completed.
`ship`: the 95% cost interval excludes zero below and full-diet passes at most 1 fewer paired cells than full (margin ceil(10% of pairs), ADR 0016).
`no-ship`: the interval excludes zero above, or the pass drop exceeds the margin, or the interval still includes zero after escalation (6 to 12 seeds, once).
`inconclusive`: fewer than 1 fixtures remain; counts as no-ship.

- Pairs: 6 across 1 fixture(s) (tierslot); floor 1 fixtures
- Cost (cache-weighted input): full-diet 96586.0, full 88954.7, paired diff +7631.4, 95% CI [-48982.1, +64244.8]
- Pass rate over paired cells: full-diet 0/6 (0%), full 1/6 (17%); net drop 1, margin 1 (within)
- Turn-capped cells (hitMaxTurns): bare 0/6, full 0/6, full-diet 0/6
- Bare arm (reference only, feeds no verdict): 6 cells, 2 hidden-test passes, mean cost 85760.4
- Unpaired cells excluded (0): none
- WARNING: fixture floor lowered to 1 (default 3): this verdict is not a valid gate
- Verdict: none. An offline replay of the report code prints `no-ship (cost interval includes zero (escalation disabled))`, but escalation was not disabled: it stopped at the prompt and seeds 7-12 never ran. The gate did not run to its end. Fixture floor 1, one fixture: not a valid gate.

## Diagnostics per arm

| arm | cells | hidden_pass | max_turns | ran_tests | tests_executed | subagent_start | read_chars | re_reads | turns | output |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| bare | 6 | 2/6 | 0 | 6/6 | 4/6 | 0/6 | 108401 | 0 | 102 | 22507 |
| full | 6 | 1/6 | 0 | 6/6 | 6/6 | 0/6 | 65175 | 0 | 100 | 20374 |
| full-diet | 6 | 0/6 | 0 | 6/6 | 4/6 | 0/6 | 50825 | 0 | 109 | 24738 |

