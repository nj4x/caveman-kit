# Bench agentic: agentic-claude-sonnet-5-5-b56c077

Date: 2026-10-21

## Run parameters

- Kind: agentic
- Model: claude-sonnet-5-5
- Seeds: 3 (escalated to 6)
- Kit dir: /Users/roman/projects/caveman-kit
- Kit-dir commit: b56c077deebf89367a97c9121f492030380cad6a
- Raw cells: /Users/roman/projects/caveman-kit/bench/results/agentic-claude-sonnet-5-5-b56c077

## Gate

Paired difference is full-diet minus full, paired by fixture and seed; both cells must have completed.
`ship`: the 95% cost interval excludes zero below and full-diet pass rate is not lower than full.
`no-ship`: the interval excludes zero above, or the pass rate is lower, or the interval still includes zero after escalation (3 to 6 seeds, once).
`inconclusive`: fewer than 3 fixtures remain; counts as no-ship.

- Pairs: 24 across 4 fixture(s) (bigfile, noisylog, reuse, rootcause); floor 3 fixtures
- Cost (cache-weighted input): full-diet 42403.5, full 39700.8, paired diff +2702.7, 95% CI [-1600.2, +7005.6]
- Pass rate over paired cells: full-diet 24/24 (100%), full 24/24 (100%)
- Turn-capped cells (hitMaxTurns): bare 0/24, full 0/24, full-diet 0/24
- Bare arm (reference only, feeds no verdict): 24 cells, 24 hidden-test passes, mean cost 40107.6
- Unpaired cells excluded (0): none
- Verdict: no-ship (cost interval includes zero after escalation)

## Decision

The gate verdict is `no-ship`. This run replicates the 8c90768 run (same configuration, 8 days later) and reproduces its no-ship result. It does not change the merge: `context-diet` is already on `master` by the maintainer's override recorded in `docs/research/2026-10-13-bench-agentic-claude-sonnet-5-5-8c90768.md`.

The pooled 48-pair analysis is in `docs/research/2026-10-23-bench-compare-8c90768-vs-b56c077.md`: cost difference -504 [-3910, +2902]. Turns in this run went from 199 (full) to 206 (full-diet), which does not support the turns evidence cited in the override. Follow-up: issue #11, and ADR 0010 for the warmup and seed cap.

## Caveats

- `ANTHROPIC_API_KEY` was a short proxy placeholder. Redaction split on it and replaced ordinary digit runs in the stored streams and `result` text (321 `[redacted]` hits). Metrics are computed before redaction and are unaffected. The fix (no redaction below 20 chars) is in commit `93a5a08`; the stored files were not regenerated.
- Pairs with a cold prompt cache in one cell of the pair inflate the variance. See ADR 0010 and `docs/research/2026-10-23-context-diet-prompt-improvements.md`.

## Diagnostics per arm

| arm | cells | hidden_pass | max_turns | read_chars | re_reads | turns | output |
| --- | --- | --- | --- | --- | --- | --- | --- |
| bare | 24 | 24/24 | 0 | 158860 | 0 | 211 | 45644 |
| full | 24 | 24/24 | 0 | 152570 | 0 | 199 | 39940 |
| full-diet | 24 | 24/24 | 0 | 111269 | 0 | 206 | 41198 |
