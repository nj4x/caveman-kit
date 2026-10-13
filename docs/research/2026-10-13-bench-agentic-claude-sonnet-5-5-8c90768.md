# Bench agentic: agentic-claude-sonnet-5-5-8c90768

Date: 2026-10-13

## Run parameters

- Kind: agentic
- Model: claude-sonnet-5-5
- Seeds: 3 (escalated to 6)
- Kit dir: /Users/roman/projects/caveman-kit-context-diet
- Kit-dir commit: 8c907683bd15da7e5b3b7a9220d220c1a345a976
- Raw cells: /Users/roman/projects/caveman-kit/bench/results/agentic-claude-sonnet-5-5-8c90768

## Gate

Paired difference is full-diet minus full, paired by fixture and seed; both cells must have completed.
`ship`: the 95% cost interval excludes zero below and full-diet pass rate is not lower than full.
`no-ship`: the interval excludes zero above, or the pass rate is lower, or the interval still includes zero after escalation (3 to 6 seeds, once).
`inconclusive`: fewer than 3 fixtures remain; counts as no-ship.

- Pairs: 24 across 4 fixture(s) (bigfile, noisylog, reuse, rootcause); floor 3 fixtures
- Cost (cache-weighted input): full-diet 37280.3, full 40991.0, paired diff -3710.7, 95% CI [-8985.1, +1563.6]
- Pass rate over paired cells: full-diet 24/24 (100%), full 24/24 (100%)
- Turn-capped cells (hitMaxTurns): bare 0/24, full 0/24, full-diet 0/24
- Bare arm (reference only, feeds no verdict): 24 cells, 24 hidden-test passes, mean cost 39522.9
- Unpaired cells excluded (0): none
- Verdict: no-ship (cost interval includes zero after escalation)

## Decision

The gate verdict is `no-ship`. The maintainer overrode it and decided to merge `context-diet` into `master` anyway. ADR 0009 says Context Diet merges only after the gate passes, so this merge is an explicit exception to that rule, not a gate result.

Evidence the maintainer weighed: the hidden-test pass rate is equal in both arms (24/24), and the diagnostics point the right way (`read_chars` 139903 to 117173, `turns` 202 to 186, no re-reads, no turn-capped cells). The cost interval still includes zero after 6 seeds, so the cost saving is not demonstrated.

Follow-up: a ticket to analyze why the cost effect is not significant and to improve the section. See follow-up issue #11.

## Diagnostics per arm

| arm | cells | hidden_pass | max_turns | read_chars | re_reads | turns | output |
| --- | --- | --- | --- | --- | --- | --- | --- |
| bare | 24 | 24/24 | 0 | 154354 | 0 | 209 | 44393 |
| full | 24 | 24/24 | 0 | 139903 | 0 | 202 | 38844 |
| full-diet | 24 | 24/24 | 0 | 117173 | 0 | 186 | 38694 |
