# Bench agentic: agentic-claude-sonnet-5-5-adminalias-calibration-2

Date: 2026-10-27

## Run parameters

- Kind: agentic
- Model: claude-sonnet-5-5
- Seeds: 6
- Warmup before each cell (ADR 0010): on
- Kit dir: /Users/roman/projects/caveman-kit/.claude/worktrees/12-retryafter-orphan-helper
- Kit-dir commit: 2094b774c2432e668cf03d624851b503dee8a330
- Raw cells: /Users/roman/projects/caveman-kit/.claude/worktrees/12-retryafter-orphan-helper/bench/results/agentic-claude-sonnet-5-5-adminalias-calibration-2
- Cold starts (first request read 0 cached tokens): bare 0/6, full 0/6, full-diet 0/6
- SubagentStart hook fires per arm: bare 0 in 0/6 cells, full 0 in 0/6 cells, full-diet 0 in 0/6 cells; Task/Agent calls: bare 0, full 0, full-diet 0

## Gate

Paired difference is full-diet minus full, paired by fixture and seed; both cells must have completed.
`ship`: the 95% cost interval excludes zero below and full-diet passes at most 1 fewer paired cells than full (margin ceil(10% of pairs), ADR 0016).
`no-ship`: the interval excludes zero above, or the pass drop exceeds the margin, or the interval still includes zero after escalation (6 to 12 seeds, once).
`inconclusive`: fewer than 1 fixtures remain; counts as no-ship.

- Pairs: 6 across 1 fixture(s) (adminalias); floor 1 fixtures
- Cost (cache-weighted input): full-diet 46192.9, full 52754.2, paired diff -6561.3, 95% CI [-8914.7, -4208.0]
- Pass rate over paired cells: full-diet 6/6 (100%), full 6/6 (100%); net drop 0, margin 1 (within)
- Turn-capped cells (hitMaxTurns): bare 0/6, full 0/6, full-diet 0/6
- Bare arm (reference only, feeds no verdict): 6 cells, 6 hidden-test passes, mean cost 39540.8
- Unpaired cells excluded (0): none
- WARNING: fixture floor lowered to 1 (default 3): this verdict is not a valid gate
- Verdict: ship (cost interval excludes zero in the good direction and hidden-test passes are within the margin)

## Diagnostics per arm

| arm | cells | hidden_pass | max_turns | ran_tests | tests_executed | subagent_start | read_chars | re_reads | turns | output |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| bare | 6 | 6/6 | 0 | 6/6 | 5/6 | 0/6 | 0 | 0 | 53 | 13093 |
| full | 6 | 6/6 | 0 | 6/6 | 6/6 | 0/6 | 0 | 0 | 70 | 15019 |
| full-diet | 6 | 6/6 | 0 | 6/6 | 4/6 | 0/6 | 5930 | 0 | 60 | 14245 |
