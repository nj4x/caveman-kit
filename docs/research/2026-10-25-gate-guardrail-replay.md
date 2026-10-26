# Gate guardrail replay: strict rule vs margin rule (issue #18, ADR 0016)

Date: 2026-10-25

This note records the offline replay the acceptance of issue #18 asks for: the hidden-test guardrail of the agentic gate re-judged over every committed run under the old strict rule (`full-diet` passes < `full` passes) and the new margin rule (net drop > ceil(10% of pairs); `bench/lib/stats.js`, `passGuardrail`). Every number below is the output of `node bench/replay-gate.js` at the commit that introduces the script, over `bench/results/`. No `node bench/run.js` call was made.

## Bottom line

1. No committed run, and no 3-seed subset of one, trips either rule. Every `full` and `full-diet` cell in `bench/results/` passes its hidden test (24 of 24 pairs in each of `8c90768` and `b56c077` over `bigfile`, `noisylog`, `reuse`, `rootcause`; 3 of 3 on `parallel`; 12 of 12, 6 of 6, 6 of 6 and 6 of 6 on the `retryafter` and `suitecheck` calibrations). Across 7 runs and 321 subsets the verdict flip count is 0. The committed data cannot show the false alarm the ticket describes, because they hold no discordant pair.
2. The exact rates reproduce the ticket's analysis. With equal true pass rate p in both arms and independent per-arm pass counts, the strict rule fires on 33.4% (3 pairs), 38.1% (6) and 41.5% (12) of runs at p = 0.65, and 44.0% at 24. The margin rule fires on 9.6%, 18.1%, 14.2% and 14.4%.
3. Power to see a drop from 0.65 to 0.40 falls from 59.6% / 72.9% / 85.4% / 94.8% (strict, at 3 / 6 / 12 / 24 pairs) to 27.4% / 51.0% / 59.0% / 77.4% (margin). The margin rule gives up 18 to 54 percent of the strict rule's relative power (the most at 3 pairs, the least at 24) for a two- to threefold cut in false alarms. Seed escalation to 6 seeds (ADR 0010) moves a 12-pair first pass to 24 pairs.
4. The exact table assumes the two arms pass each paired cell independently. A fixture that is hard for both arms on the same seed makes the pairs concordant, which lowers both rates; the table is an upper bound for both rules.

## Replay output

```
Replay of committed cells under /Users/roman/projects/caveman-kit/bench/results
Rules: strict = full-diet passes < full passes; margin = net drop > ceil(10% of pairs) (stats.passGuardrail)

agentic-claude-sonnet-5-5-8c90768: 24 pairs over bigfile, noisylog, reuse, rootcause (seeds 1,2,3,4,5,6)
  all seeds: full-diet 24/24, full 24/24, net drop 0, margin 3; strict quiet, margin quiet
  20 3-seed subsets: strict fires 0, margin fires 0, verdict flips 0
agentic-claude-sonnet-5-5-b56c077: 24 pairs over bigfile, noisylog, reuse, rootcause (seeds 1,2,3,4,5,6)
  all seeds: full-diet 24/24, full 24/24, net drop 0, margin 3; strict quiet, margin quiet
  20 3-seed subsets: strict fires 0, margin fires 0, verdict flips 0
agentic-claude-sonnet-5-5-parallel-13: 3 pairs over parallel (seeds 1,2,3)
  all seeds: full-diet 3/3, full 3/3, net drop 0, margin 1; strict quiet, margin quiet
  1 3-seed subsets: strict fires 0, margin fires 0, verdict flips 0
agentic-claude-sonnet-5-5-retryafter-calibration-1: 12 pairs over retryafter (seeds 1,2,3,4,5,6,7,8,9,10,11,12)
  all seeds: full-diet 12/12, full 12/12, net drop 0, margin 2; strict quiet, margin quiet
  220 3-seed subsets: strict fires 0, margin fires 0, verdict flips 0
agentic-claude-sonnet-5-5-retryafter-calibration-3: 6 pairs over retryafter (seeds 1,2,3,4,5,6)
  all seeds: full-diet 6/6, full 6/6, net drop 0, margin 1; strict quiet, margin quiet
  20 3-seed subsets: strict fires 0, margin fires 0, verdict flips 0
agentic-claude-sonnet-5-5-suitecheck-calibration: 6 pairs over suitecheck (seeds 1,2,3,4,5,6)
  all seeds: full-diet 6/6, full 6/6, net drop 0, margin 1; strict quiet, margin quiet
  20 3-seed subsets: strict fires 0, margin fires 0, verdict flips 0
agentic-claude-sonnet-5-5-suitecheck-calibration-2: 6 pairs over suitecheck (seeds 1,2,3,4,5,6)
  all seeds: full-diet 6/6, full 6/6, net drop 0, margin 1; strict quiet, margin quiet
  20 3-seed subsets: strict fires 0, margin fires 0, verdict flips 0

Total: 7 run(s), 321 subset(s), 0 flip(s)

Exact rates for independent per-arm pass counts at the replayed pair sizes (upper bounds, see source):
n    margin  p(both)  strict-FA  margin-FA  | p(full)  p(diet)  strict-power  margin-power
3    1       0.95     12.3%      0.6%       | 0.95     0.70     59.3%         18.9%
3    1       0.80     29.1%      5.6%       | 0.80     0.55     59.9%         25.3%
3    1       0.65     33.4%      9.6%       | 0.65     0.40     59.6%         27.4%
3    1       0.50     34.4%      10.9%      | 0.50     0.25     59.8%         26.4%
6    1       0.95     20.2%      2.5%       | 0.95     0.70     79.1%         48.8%
6    1       0.80     35.5%      13.4%      | 0.80     0.55     74.3%         50.7%
6    1       0.65     38.1%      18.1%      | 0.65     0.40     72.9%         51.0%
6    1       0.50     38.7%      19.4%      | 0.50     0.25     73.6%         50.9%
12   2       0.95     29.1%      1.1%       | 0.95     0.70     92.8%         60.6%
12   2       0.80     39.8%      9.8%       | 0.80     0.55     87.1%         59.4%
12   2       0.65     41.5%      14.2%      | 0.65     0.40     85.4%         59.0%
12   2       0.50     41.9%      15.4%      | 0.50     0.25     86.2%         59.2%
24   3       0.95     36.0%      1.1%       | 0.95     0.70     98.9%         84.4%
24   3       0.80     42.8%      10.2%      | 0.80     0.55     96.0%         78.9%
24   3       0.65     44.0%      14.4%      | 0.65     0.40     94.8%         77.4%
24   3       0.50     44.3%      15.6%      | 0.50     0.25     95.4%         78.1%
```

## Reading the table

- `n`: paired cells. 3 is one fixture at 3 seeds; 6 one fixture at 6 seeds or two at 3; 12 four fixtures at 3 seeds (the first pass of `8c90768` and `b56c077`); 24 the same after escalation.
- `margin`: ceil(0.1 n), the net drop the margin rule tolerates.
- `strict-FA`, `margin-FA`: probability each rule fires when both arms share the pass rate `p(both)`. Every fire here is a false `no-ship`.
- `strict-power`, `margin-power`: probability each rule fires when `full-diet`'s rate is 0.25 below `full`'s.

## What is not in this replay

- Partial credit from the pytest summary in `hiddenTest.tail` (ticket direction 2): every `full` and `full-diet` summary in `bench/results/` reads `N passed`, so the fraction is 1.0 for every paired cell and the replay would be identical.
- `diagnostics.testRunsExecuted` as a paired signal (ticket direction 3, ADR 0014): the field exists only in the single-fixture calibration cells (`suitecheck`, `retryafter`), where every `full`/`full-diet` cell passed anyway. The four-fixture runs `8c90768` and `b56c077` predate ADR 0014 and lack it, so the `bigfile` 9/12 vs 5/12 figure the ticket cites is not in any committed cell file and cannot be replayed from them.
