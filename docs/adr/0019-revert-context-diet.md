---
artifact-type: adr
lineage-rules: exempt
---

# ADR 0019: Revert the Context Diet supplement

**Status**: Accepted. Supersedes ADR 0009.

**Context:**

ADR 0009 allowed the Context Diet section to ship only if the agentic gate (ADR 0008 decision 8, ADR 0016) showed a cache-weighted input cost interval below zero. The first gate run (8c90768) returned `no-ship`: interval [-8985.1, +1563.6] after 6 seeds. The maintainer merged the section anyway, as a stated exception, and issue #11 asked why a 16% drop in read characters did not reach the cost metric.

The b56c077 run was not valid evidence: it went through a routing proxy and 9 of 24 pairs compared different models (ADR 0011). Issue #11 was therefore left open for a clean rerun.

The clean rerun is run `agentic-claude-sonnet-5-5-d67c890`: pass-through proxy on port 8084, six default fixtures, 3 arms, escalated from 3 to 6 seeds, 36 pairs. The proxy database shows 3,527 requests, every one requested and routed as `claude-sonnet-5-5`. Every cell started warm (ADR 0010). Results:

- Paired cost difference `full-diet` minus `full`: +112.2 (0.3% of the `full` mean of 41,680), 95% interval [-3476.3, +3700.8]. Verdict `no-ship`.
- Hidden-test pass rate: 36/36 in both arms. No turn-capped cell.
- `read_chars` per arm: `full` 179,129, `full-diet` 113,467, `bare` 151,755. `turns` 306 against 303.

**Analysis:**

1. Cost is cache traffic, not fresh input. Per cell the cache-weighted cost splits into about 16 units of uncached input, about 21,000 of cache read (0.1 per token) and about 21,000 of cache write (1.25 per token). A read-volume saving can only act through those two.
2. The read-volume saving is small against that base. The `full` to `full-diet` gap in `read_chars` is about 66,000 characters over 36 cells, about 1,800 characters (roughly 500 tokens) per cell. The cache write costs about 625 units (500 tokens at 1.25) and re-sends on later turns add about 200 to 400 more (0.1 per token per turn), roughly 2% of the 41,680 per cell.
3. The gap in `read_chars` comes mostly from one fixture. Per-fixture mean difference in `read_chars` (`full-diet` minus `full`) is -9,728 on `reuse` and between -1,931 and +1,147 on the other five. `reuse` is also where the paired cost difference is not clearly negative (-1,092, sd 5,969).
4. Variance is large against any plausible effect. The standard deviation of the paired cost difference is 10,606 (36 pairs). `parallel` alone has sd 20,635. Pairs needed for the 95% interval to exclude zero: about 25 at a 10% saving, about 100 at a 5% saving, over 34,000 at the observed +0.3%. The run has enough power to rule out a saving of about 8% or more; it cannot rule out a saving of a few percent. The interval's lower edge is -3476.3, about 8% of the `full` mean.
5. The rule "never re-read an unchanged file" has nothing to act on. Re-reads are 1 (`full`), 2 (`full-diet`) and 3 (`bare`) across 36 cells each.

The 16% read reduction seen in 8c90768 did not reproduce as a cost effect, and in this run the 37% read reduction did not either. Fewer read characters do not translate into lower cache-weighted cost on these fixtures.

**Decision:**

1. Revert the section. Delete `hooks/caveman-context-diet.md`, the diet block and `CAVEMAN_CONTEXT_DIET` handling in `hooks/caveman-activate.js`, the diet tests in `tests/caveman-activate.bats`, and the Context Diet sentence in `CLAUDE.md`. ADR 0009 is marked superseded.
2. The gate stays the criterion (ADR 0008 is unchanged). It failed twice, the second time on a valid run, so the maintainer's earlier exception is withdrawn.
3. Shrinking was not chosen. The section is 421 bytes; shrinking it would remove text that already shows no effect, and the analysis finds no rule that acts on these fixtures.
4. The bench harness and its `full`/`full-diet` arms stay. A new candidate follows the ADR 0009 layout: the file, the hook change and the `CAVEMAN_CONTEXT_DIET=0` opt-out that the `full` arm sets (`bench/lib/arms.js`) go on a branch, `--kit-dir` pointed at it, gate before any merge. The runner aborts when `hooks/caveman-context-diet.md` is missing in the kit dir, which is the intended guard.
5. A candidate worth testing must act where cost is: cache write and cache read over long sessions. The current fixtures average about 8 turns per cell (303 to 306 turns over 36 cells). A longer-horizon fixture, where a large early read is re-sent for many turns, is the first thing to add; rule text comes second.

**Consequences:**

- Hooks no longer read `caveman-context-diet.md`. A copy left in `~/.caveman-kit/hooks/` by an earlier install or update is inert. `uninstall.sh` removes the whole directory.
- `CAVEMAN_CONTEXT_DIET` has no effect after this change. Setting it is harmless.
- SessionStart and SubagentStart text shrinks by about 325 characters in every non-`off` mode.
- The evidence is `docs/research/2026-10-27-bench-agentic-claude-sonnet-5-5-d67c890.md` and the cells in `bench/results/agentic-claude-sonnet-5-5-d67c890`.

**Source SRS:** none (repo uses `lineage-rules: exempt`).
