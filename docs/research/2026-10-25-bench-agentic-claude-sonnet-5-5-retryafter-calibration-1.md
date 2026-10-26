# Bench agentic: agentic-claude-sonnet-5-5-retryafter-calibration-1

Date: 2026-10-25

## Run parameters

- Kind: agentic
- Model: claude-sonnet-5-5
- Seeds: 6 (escalated to 12)
- Warmup before each cell (ADR 0010): on
- Kit dir: /Users/roman/projects/caveman-kit
- Kit-dir commit: 379754edf5b02dfb8668a3dfdf0ded55a9f2439f
- Raw cells: /Users/roman/projects/caveman-kit/bench/results/agentic-claude-sonnet-5-5-retryafter-calibration-1
- Cold starts (first request read 0 cached tokens): bare 0/12, full 0/12, full-diet 0/12
- SubagentStart hook fires per arm: bare 0 in 0/12 cells, full 0 in 0/12 cells, full-diet 0 in 0/12 cells; Task/Agent calls: bare 0, full 0, full-diet 0

## Gate

Paired difference is full-diet minus full, paired by fixture and seed; both cells must have completed.
`ship`: the 95% cost interval excludes zero below and full-diet pass rate is not lower than full.
`no-ship`: the interval excludes zero above, or the pass rate is lower, or the interval still includes zero after escalation (6 to 12 seeds, once).
`inconclusive`: fewer than 1 fixtures remain; counts as no-ship.

- Pairs: 12 across 1 fixture(s) (retryafter); floor 1 fixtures
- Cost (cache-weighted input): full-diet 43795.8, full 40991.6, paired diff +2804.2, 95% CI [-3407.4, +9015.8]
- Pass rate over paired cells: full-diet 12/12 (100%), full 12/12 (100%)
- Turn-capped cells (hitMaxTurns): bare 0/12, full 0/12, full-diet 0/12
- Bare arm (reference only, feeds no verdict): 12 cells, 12 hidden-test passes, mean cost 36678.7
- Unpaired cells excluded (0): none
- WARNING: fixture floor lowered to 1 (default 3): this verdict is not a valid gate
- Verdict: no-ship (cost interval includes zero after escalation)

## Diagnostics per arm

| arm | cells | hidden_pass | max_turns | ran_tests | tests_executed | subagent_start | read_chars | re_reads | turns | output |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| bare | 12 | 12/12 | 0 | 12/12 | 8/12 | 0/12 | 23502 | 0 | 116 | 19102 |
| full | 12 | 12/12 | 0 | 12/12 | 8/12 | 0/12 | 44571 | 0 | 124 | 19507 |
| full-diet | 12 | 12/12 | 0 | 12/12 | 9/12 | 0/12 | 47707 | 0 | 130 | 20898 |

## Calibration result (issue #12, ADR 0012 decision 2, ADR 0015)

Target: `bare` passes roughly 50-80% of seeds on `retryafter`. Result: `bare` passed 12 of 12 over 12 seeds (the run escalated from 6 to 12 because the cost interval included zero), as did `full` and `full-diet`. The fixture, in its first design, does not meet the target. This run used `--min-fixtures 1`, so its gate verdict is not valid and is not used.

Why the trap did not spring: the first design planted both bugs in `anthrouter/http_util.py` (the `should_retry` inversion and a dropped `/ 1000.0` in `parse_retry_after`). In all 12 `bare` streams the first step was `grep -i "retry-after\|retry_after" anthrouter`, because the prompt names `retry-after-ms`. The grep led to `http_util.py`, which each agent read from about line 80 to 190, a window that holds both bugs, and every agent fixed both there. Only `bare` s3 and s4 opened `transport.py`, and only after a partial fix left a repo test red.

Follow-up: the second plant moved to `transport._send_with_retries`, outside that window (ADR 0015).
