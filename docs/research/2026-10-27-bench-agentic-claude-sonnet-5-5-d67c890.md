# Bench agentic: agentic-claude-sonnet-5-5-d67c890

Date: 2026-10-27

## Run parameters

- Kind: agentic
- Model: claude-sonnet-5-5
- Seeds: 3 (escalated to 6)
- Warmup before each cell (ADR 0010): on
- Kit dir: /Users/roman/projects/caveman-kit
- Kit-dir commit: d67c890ef80ba9b86b0f56b034d46c2cd3061f87
- Raw cells: /Users/roman/projects/caveman-kit/bench/results/agentic-claude-sonnet-5-5-d67c890
- Cold starts (first request read 0 cached tokens): bare 0/36, full 0/36, full-diet 0/36
- SubagentStart hook fires per arm: bare 12 in 6/36 cells, full 12 in 6/36 cells, full-diet 12 in 6/36 cells; Task/Agent calls: bare 12, full 12, full-diet 12

## Gate

Paired difference is full-diet minus full, paired by fixture and seed; both cells must have completed.
`ship`: the 95% cost interval excludes zero below and full-diet passes at most 4 fewer paired cells than full (margin ceil(10% of pairs), ADR 0016).
`no-ship`: the interval excludes zero above, or the pass drop exceeds the margin, or the interval still includes zero after escalation (3 to 6 seeds, once).
`inconclusive`: fewer than 3 fixtures remain; counts as no-ship.

- Pairs: 36 across 6 fixture(s) (bigfile, noisylog, parallel, reuse, rootcause, suitecheck); floor 3 fixtures
- Cost (cache-weighted input): full-diet 41792.0, full 41679.8, paired diff +112.2, 95% CI [-3476.3, +3700.8]
- Pass rate over paired cells: full-diet 36/36 (100%), full 36/36 (100%); net drop 0, margin 4 (within)
- Turn-capped cells (hitMaxTurns): bare 0/36, full 0/36, full-diet 0/36
- Bare arm (reference only, feeds no verdict): 36 cells, 36 hidden-test passes, mean cost 37713.1
- Unpaired cells excluded (0): none
- Verdict: no-ship (cost interval includes zero after escalation)

## Diagnostics per arm

| arm | cells | hidden_pass | max_turns | ran_tests | tests_executed | subagent_start | read_chars | re_reads | turns | output |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| bare | 36 | 36/36 | 0 | 25/36 | 11/36 | 6/36 | 151755 | 3 | 282 | 58964 |
| full | 36 | 36/36 | 0 | 26/36 | 12/36 | 6/36 | 179129 | 1 | 306 | 61251 |
| full-diet | 36 | 36/36 | 0 | 21/36 | 12/36 | 6/36 | 113467 | 2 | 303 | 61444 |

## Decision

Revert the Context Diet supplement (ADR 0019). Verdict `no-ship` after escalation to 6 seeds on a valid single-model run.

## Caveats

- The run went through a pass-through anthproxy on port 8084 (`--lock-requested-model off`, `--db-path ~/.anthproxy/bench.db`). The proxy DB shows 3,527 requests, all requested and routed as `claude-sonnet-5-5`. This is a maintainer-local fact; the DB is not committed.
- Cost split per cell (uncached input / cache read / cache write, cache-weighted): `full` 16 / 20,566 / 21,097; `full-diet` 17 / 21,017 / 20,758.
- Paired cost difference by fixture (mean, sd): bigfile -744 (5,772); noisylog -1,489 (10,667); parallel +4,833 (20,635); reuse -1,092 (5,969); rootcause +1,628 (4,082); suitecheck -2,462 (10,914). Overall sd 10,606.
- With that sd the run excludes a saving of about 8% or more; a few percent is not ruled out.
