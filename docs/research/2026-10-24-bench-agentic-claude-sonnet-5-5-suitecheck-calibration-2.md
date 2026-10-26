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
