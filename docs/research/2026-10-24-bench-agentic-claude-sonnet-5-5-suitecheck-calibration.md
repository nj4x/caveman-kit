# Bench agentic: agentic-claude-sonnet-5-5-suitecheck-calibration

Date: 2026-10-24

## Run parameters

- Kind: agentic
- Model: claude-sonnet-5-5
- Seeds: 6
- Warmup before each cell (ADR 0010): on
- Kit dir: /Users/roman/projects/caveman-kit
- Kit-dir commit: 6eb88eeb512c528ff8cc93bc6d5a0fd7806a86b5
- Raw cells: /Users/roman/projects/caveman-kit/bench/results/agentic-claude-sonnet-5-5-suitecheck-calibration
- Cold starts (first request read 0 cached tokens): bare 0/6, full 0/6, full-diet 0/6
- SubagentStart hook fires per arm: bare 0 in 0/6 cells, full 0 in 0/6 cells, full-diet 0 in 0/6 cells; Task/Agent calls: bare 0, full 0, full-diet 0

## Gate

Paired difference is full-diet minus full, paired by fixture and seed; both cells must have completed.
`ship`: the 95% cost interval excludes zero below and full-diet pass rate is not lower than full.
`no-ship`: the interval excludes zero above, or the pass rate is lower, or the interval still includes zero after escalation (6 to 12 seeds, once).
`inconclusive`: fewer than 1 fixtures remain; counts as no-ship.

- Pairs: 6 across 1 fixture(s) (suitecheck); floor 1 fixtures
- Cost (cache-weighted input): full-diet 33768.4, full 33524.0, paired diff +244.4, 95% CI [-3974.0, +4462.9]
- Pass rate over paired cells: full-diet 6/6 (100%), full 6/6 (100%)
- Turn-capped cells (hitMaxTurns): bare 0/6, full 0/6, full-diet 0/6
- Bare arm (reference only, feeds no verdict): 6 cells, 6 hidden-test passes, mean cost 32814.9
- Unpaired cells excluded (0): none
- WARNING: fixture floor lowered to 1 (default 3): this verdict is not a valid gate
- Verdict: no-ship (cost interval includes zero (escalation disabled))

## Diagnostics per arm

| arm | cells | hidden_pass | max_turns | ran_tests | tests_executed | subagent_start | read_chars | re_reads | turns | output |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| bare | 6 | 6/6 | 0 | 6/6 | 0/6 | 0/6 | 5723 | 0 | 49 | 9565 |
| full | 6 | 6/6 | 0 | 6/6 | 0/6 | 0/6 | 34338 | 0 | 48 | 9490 |
| full-diet | 6 | 6/6 | 0 | 6/6 | 0/6 | 0/6 | 27040 | 0 | 50 | 9613 |

## Calibration result (issue #12, ADR 0012 decision 2)

Target: `bare` passes roughly 50-80% of seeds on `suitecheck`. Result: `bare` passed 6 of 6, as did `full` and `full-diet`. The fixture does not meet ADR 0012 decision 2 as it stands.

Why the trap did not spring: in none of the 18 cells did a test run execute (`tests_executed` 0/6 in every arm). Every agent tried `python3 -m pytest` (18 of 18 streams hold `No module named pytest`) and went on without running the suite; no stream contains `uv run`, `uvx` or `uv pip`. The environment was missing more than pytest: bare `python` was not found in 15 cells, and `make test` failed on `python` in 5. All 18 final summaries say the suite was not run or that pytest is unavailable. `ran_tests` read 6/6 in every arm only because it counts the attempt. The agents instead read `period_workday_dates` and fixed the real cause (the exclusive period end), and in 17 of 18 cells checked the result with a direct call (`bare` s5 did not, and its summary says the fix is untested). Two cells (`bare` s2, `full-diet` s4) used a conditional day-subtraction variant of the "end the loop one day early" fix that the repo suite would test; the plain version was not seen.

So this run does not show that the fixture is too easy to ever fail `bare`. It shows the suite was out of reach. Only `noisylog` names the `uv` fallback in its prompt. Re-calibrate after giving `suitecheck` a runner hint like the `noisylog` prompt has, naming `python3` and `uv` (ADR 0014).

The cells' `diagnostics` were re-derived from their stored streams after `tests_executed` was added (re-analysis of each stored stream matched its stored usage).
