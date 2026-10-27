# Bench agentic: agentic-claude-sonnet-5-5-retryafter-calibration-6

Date: 2026-10-26

## Run parameters

- Kind: agentic
- Model: claude-sonnet-5-5
- Seeds: 6
- Warmup before each cell (ADR 0010): on
- Kit dir: /Users/roman/projects/caveman-kit/.claude/worktrees/12-retryafter-orphan-helper
- Kit-dir commit: 2094b774c2432e668cf03d624851b503dee8a330
- Raw cells: /Users/roman/projects/caveman-kit/.claude/worktrees/12-retryafter-orphan-helper/bench/results/agentic-claude-sonnet-5-5-retryafter-calibration-6
- Cold starts (first request read 0 cached tokens): bare 0/6, full 0/6, full-diet 0/6
- SubagentStart hook fires per arm: bare 0 in 0/6 cells, full 0 in 0/6 cells, full-diet 0 in 0/6 cells; Task/Agent calls: bare 0, full 0, full-diet 0

## Gate

Paired difference is full-diet minus full, paired by fixture and seed; both cells must have completed.
`ship`: the 95% cost interval excludes zero below and full-diet passes at most 1 fewer paired cells than full (margin ceil(10% of pairs), ADR 0016).
`no-ship`: the interval excludes zero above, or the pass drop exceeds the margin, or the interval still includes zero after escalation (6 to 12 seeds, once).
`inconclusive`: fewer than 1 fixtures remain; counts as no-ship.

- Pairs: 6 across 1 fixture(s) (retryafter); floor 1 fixtures
- Cost (cache-weighted input): full-diet 49954.2, full 55651.4, paired diff -5697.2, 95% CI [-10467.3, -927.1]
- Pass rate over paired cells: full-diet 6/6 (100%), full 6/6 (100%); net drop 0, margin 1 (within)
- Turn-capped cells (hitMaxTurns): bare 0/6, full 0/6, full-diet 0/6
- Bare arm (reference only, feeds no verdict): 6 cells, 6 hidden-test passes, mean cost 43452.7
- Unpaired cells excluded (0): none
- WARNING: fixture floor lowered to 1 (default 3): this verdict is not a valid gate
- Verdict: ship (cost interval excludes zero in the good direction and hidden-test passes are within the margin)

## Diagnostics per arm

| arm | cells | hidden_pass | max_turns | ran_tests | tests_executed | subagent_start | read_chars | re_reads | turns | output |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| bare | 6 | 6/6 | 0 | 6/6 | 6/6 | 0/6 | 0 | 0 | 61 | 11578 |
| full | 6 | 6/6 | 0 | 6/6 | 6/6 | 0/6 | 5946 | 0 | 74 | 15315 |
| full-diet | 6 | 6/6 | 0 | 6/6 | 6/6 | 0/6 | 5699 | 0 | 67 | 13078 |

## Calibration result (issue #12, ADR 0012 decision 2, ADR 0015)

Target: `bare` passes roughly 50-80% of seeds on `retryafter`. Result: `bare` passed 6 of 6, as did `full` and `full-diet`. The fixture, with this plant, does not meet the target. This run used `--min-fixtures 1`, so its gate verdict is not valid and is not used.

Plant in this run: the 429 inversion in `http_util.should_retry`, and the `retry_delay` helper removed from `http_util.py` and `transport.py`, with `transport._send_with_retries` computing the exponential backoff. Prompt: the end-to-end wording of calibration 4.

What the streams show: all six `bare` agents grepped `retry-after|retry_after`, read `http_util.py`, fixed the inversion, then opened the retry block in `transport.py` (found through `should_retry` or `parse_retry_after` hits) and replaced the backoff line with a delay that honors the upstream guidance. Removing the helper did not hide the second bug: the wrong line sits three lines under the `should_retry` call that the "check end to end" sentence sends the agent to. Five of six ran the full suite (1,125 passed, 3 failed, the same 3 that fail on the unpatched tree); one (s2) also wrote a script against a local stub upstream and measured the wait.

Next plant (ADR 0015): the bug moves into `retry_delay`, which `transport.py` calls correctly, as a cap on the guided delay. The call site then reads correctly.
