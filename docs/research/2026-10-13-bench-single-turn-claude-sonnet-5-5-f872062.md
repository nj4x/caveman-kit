# Bench single-turn: single-turn-claude-sonnet-5-5-f872062

Date: 2026-10-13

## Run parameters

- Kind: single-turn
- Model: claude-sonnet-5-5
- Seeds: 3
- Kit dir: /Users/roman/projects/caveman-kit
- Kit-dir commit: f872062c3256abbec6990d15461bf838ddf1e73c
- Raw cells: /Users/roman/projects/caveman-kit/bench/results/single-turn-claude-sonnet-5-5-f872062

## Gate

Paired differences are candidate minus reference, paired by task and seed, with 95% t-intervals.
Cost is cache-weighted input tokens (input + 0.1 x cache read + 1.25 x cache write); lower is better for both metrics.
`ship`: one interval excludes zero below and the other does not exclude zero above.
`no-ship`: either interval excludes zero above, or both include zero.
`inconclusive`: bare vs bare-control excludes zero on either metric, or has fewer than 2 pairs; counts as no-ship.

| candidate | reference | pairs | cost_cand | cost_ref | cost_diff | cost_ci95 | out_cand | out_ref | out_diff | out_ci95 | verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| lite | bare | 18 | 10539.1 | 10376.2 | +162.8 | [-3010.2, +3335.9] | 387.9 | 926.6 | -538.6 | [-676.3, -400.9] | **ship** |
| full | bare | 18 | 10385.3 | 10376.2 | +9.1 | [-3163.9, +3182.1] | 383.7 | 926.6 | -542.9 | [-700.6, -385.2] | **ship** |
| ultra | bare | 18 | 10351.6 | 10376.2 | -24.7 | [-3197.7, +3148.4] | 340.3 | 926.6 | -586.3 | [-763.5, -409.0] | **ship** |
| ultra-no-focus | ultra | 18 | 10286.6 | 10351.6 | -65.0 | [-65.0, -65.0] | 613.2 | 340.3 | +272.9 | [+144.7, +401.1] | **no-ship** |
| bare | bare-control | 18 | 10376.2 | 8191.6 | +2184.7 | [-988.4, +5357.7] | 926.6 | 998.3 | -71.8 | [-149.2, +5.6] | baseline |

Noise baseline includes zero on both metrics.

Unpaired cells excluded: none

## Findings and follow-up

- `lite`, `full` and `ultra` each ship against bare on billed output tokens (about 540 to 590 fewer per call, interval excludes zero). Cache-weighted input cost shows no significant difference for any of them.
- The noise baseline (bare vs bare-control) includes zero on both metrics, so no verdict is `inconclusive`.
- `ultra`-no-focus vs `ultra` is `no-ship`: removing the focus clause from the reminder raised billed output by about 273 tokens per call (interval +144.7 to +401.1). This is evidence that the `e11e665` focus directive helps on this task set.
- The cost interval for this pair is zero-width (`[-65.0, -65.0]`), meaning every paired cost difference was identical. Treat that interval as a data artifact, not as a result. The output interval carries the verdict.
- Recommendation: keep `e11e665`. Do not revert it. This run uses one model (`claude-sonnet-5-5`), 6 tasks and 3 seeds, so repeat it on `claude-opus-5-5` before treating the finding as general. No ADR is needed unless a later run contradicts this one.

## Raw totals

| arm | cells | output | input | cache_read | cache_write | cost_usd |
| --- | --- | --- | --- | --- | --- | --- |
| bare | 18 | 16678 | 36 | 274496 | 127429 | 0.5403 |
| bare-control | 18 | 17970 | 36 | 308808 | 93225 | 0.4746 |
| lite | 18 | 6983 | 36 | 308808 | 127029 | 0.4492 |
| full | 18 | 6906 | 36 | 308808 | 124815 | 0.4429 |
| ultra | 18 | 6125 | 36 | 308808 | 124329 | 0.4339 |
| ultra-no-focus | 18 | 11037 | 36 | 308808 | 123393 | 0.4807 |
