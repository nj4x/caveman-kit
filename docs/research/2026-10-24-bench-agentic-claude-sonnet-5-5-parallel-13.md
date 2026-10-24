# Bench agentic: agentic-claude-sonnet-5-5-parallel-13

Date: 2026-10-24

## Run parameters

- Kind: agentic
- Model: claude-sonnet-5-5
- Seeds: 3
- Warmup before each cell (ADR 0010): on
- Kit dir: /Users/roman/projects/caveman-kit/.claude/worktrees/13-bench-subagentstart
- Kit-dir commit: ed931c77063c8a0a02b84856f6df957c31f68e65
- Raw cells: /Users/roman/projects/caveman-kit/.claude/worktrees/13-bench-subagentstart/bench/results/agentic-claude-sonnet-5-5-parallel-13
- Cold starts (first request read 0 cached tokens): bare 0/3, full 0/3, full-diet 0/3
- SubagentStart hook fires per arm: bare 6 in 3/3 cells, full 6 in 3/3 cells, full-diet 6 in 3/3 cells; Task/Agent calls: bare 6, full 6, full-diet 6

## Gate

Paired difference is full-diet minus full, paired by fixture and seed; both cells must have completed.
`ship`: the 95% cost interval excludes zero below and full-diet pass rate is not lower than full.
`no-ship`: the interval excludes zero above, or the pass rate is lower, or the interval still includes zero after escalation (3 to 6 seeds, once).
`inconclusive`: fewer than 1 fixtures remain; counts as no-ship.

- Pairs: 3 across 1 fixture(s) (parallel); floor 1 fixtures
- Cost (cache-weighted input): full-diet 65590.8, full 71830.7, paired diff -6239.9, 95% CI [-20912.9, +8433.1]
- Pass rate over paired cells: full-diet 3/3 (100%), full 3/3 (100%)
- Turn-capped cells (hitMaxTurns): bare 0/3, full 0/3, full-diet 0/3
- Bare arm (reference only, feeds no verdict): 3 cells, 3 hidden-test passes, mean cost 71454.6
- Unpaired cells excluded (0): none
- WARNING: fixture floor lowered to 1 (default 3): this verdict is not a valid gate
- Verdict: no-ship (cost interval includes zero (escalation disabled))

## Diagnostics per arm

| arm | cells | hidden_pass | max_turns | ran_tests | subagent_start | read_chars | re_reads | turns | output |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| bare | 3 | 3/3 | 0 | 3/3 | 3/3 | 4774 | 2 | 30 | 10502 |
| full | 3 | 3/3 | 0 | 2/3 | 3/3 | 5821 | 0 | 31 | 9617 |
| full-diet | 3 | 3/3 | 0 | 2/3 | 3/3 | 1991 | 0 | 29 | 8787 |
