# Bench agentic: agentic-claude-sonnet-5-5-suitecheck-calibration-2

Date: 2026-10-24

## Run parameters

- Kind: agentic
- Model: claude-sonnet-5-5
- Seeds: 6
- Warmup before each cell (ADR 0010): on
- Kit dir: /Users/roman/projects/caveman-kit
- Kit-dir commit: 379754edf5b02dfb8668a3dfdf0ded55a9f2439f
- Raw cells: /Users/roman/projects/caveman-kit/bench/results/agentic-claude-sonnet-5-5-suitecheck-calibration-2
- Cold starts (first request read 0 cached tokens): bare 0/6, full 0/6, full-diet 0/6
- SubagentStart hook fires per arm: bare 0 in 0/6 cells, full 0 in 0/6 cells, full-diet 0 in 0/6 cells; Task/Agent calls: bare 0, full 0, full-diet 0

## Gate

Paired difference is full-diet minus full, paired by fixture and seed; both cells must have completed.
`ship`: the 95% cost interval excludes zero below and full-diet pass rate is not lower than full.
`no-ship`: the interval excludes zero above, or the pass rate is lower, or the interval still includes zero after escalation (6 to 12 seeds, once).
`inconclusive`: fewer than 1 fixtures remain; counts as no-ship.

- Pairs: 6 across 1 fixture(s) (suitecheck); floor 1 fixtures
- Cost (cache-weighted input): full-diet 36454.9, full 35871.3, paired diff +583.6, 95% CI [-4212.9, +5380.1]
- Pass rate over paired cells: full-diet 6/6 (100%), full 6/6 (100%)
- Turn-capped cells (hitMaxTurns): bare 0/6, full 0/6, full-diet 0/6
- Bare arm (reference only, feeds no verdict): 6 cells, 6 hidden-test passes, mean cost 36906.2
- Unpaired cells excluded (0): none
- WARNING: fixture floor lowered to 1 (default 3): this verdict is not a valid gate
- Verdict: no-ship (cost interval includes zero (escalation disabled))

## Diagnostics per arm

| arm | cells | hidden_pass | max_turns | ran_tests | tests_executed | subagent_start | read_chars | re_reads | turns | output |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| bare | 6 | 6/6 | 0 | 6/6 | 5/6 | 0/6 | 17693 | 0 | 55 | 9614 |
| full | 6 | 6/6 | 0 | 6/6 | 6/6 | 0/6 | 22892 | 0 | 48 | 7711 |
| full-diet | 6 | 6/6 | 0 | 6/6 | 6/6 | 0/6 | 24117 | 0 | 50 | 8633 |

## Calibration result (issue #12, ADR 0012 decision 2, ADR 0014)

Target: `bare` passes roughly 50-80% of seeds on `suitecheck`, now that the prompt names the test runner (PR #17). Result: `bare` passed 6 of 6, as did `full` and `full-diet`. The fixture does not meet ADR 0012 decision 2.

The suite was within reach this time: `tests_executed` read 5/6 for `bare` and 6/6 for `full` and `full-diet`. The runner hint worked, but running the suite was not what made the cells pass. None of the 6 `bare` agents took the "end the loop one day early" fix that the fixture treats as the trap. Four of them (s1, s2, s3, s6) restored the original expression, `end_local = (period_end - dt.timedelta(microseconds=1)).astimezone(tz).date()`, which is what the plant replaced; s1, s2 and s6 also rewrote the docstring the plant had changed, to say that `period_end` is exclusive. The other two (s4, s5) subtracted a day only when `period_end` falls at local midnight. That variant is correct for an exclusive end, and the repo suite and the hidden test both accept it.

Why the trap did not spring: the plant is a one-line change to a recognizable idiom. The symptom in the prompt (September 2026 has 22 weekdays, not 23) points at the period end, and an agent that reads `period_workday_dates` sees that the end is treated as inclusive. The fix that follows from that reading is correct. The wrong fix only attracts an agent that patches the count instead of the cause.

How the cells verified the fix: two `bare` agents (s4, s6) ran the full suite (1,125 passed, 3 failed). The 3 failures exist on the unpatched tree (both agents confirmed this with `git stash`). Three agents (s1, s2, s3) ran only a pace-related subset (53 to 62 tests passed). One agent (s5) started the full suite in the background, did not wait for its result, and checked with a direct call; that is the one `bare` cell without an executed test run.

Conclusion: `suitecheck` is too easy because the correct fix is the natural one, not because agents skip the suite. A fixture needs a plausible wrong fix that tempts the agent, and a correct fix that is not the obvious one. `retryafter` tried to apply this lesson (ADR 0015).
