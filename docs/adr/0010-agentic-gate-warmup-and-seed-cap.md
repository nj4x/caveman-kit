---
artifact-type: adr
lineage-rules: exempt
---

# ADR 0010: Agentic gate: cache warmup per arm and fixture, higher seed cap

**Status**: Approved. Supersedes the seed cap in ADR 0008 Decision 8 (agentic harness only). The rest of Decision 8 stands.

**Context:**

The agentic gate of ADR 0008 pairs `full` + Context Diet against `full` by fixture and seed, and escalates to 6 seeds at most. The R1 and R2 runs (`docs/research/2026-10-23-bench-compare-8c90768-vs-b56c077.md`) gave a cost interval that includes zero, and the sign flipped between runs.

The research note `docs/research/2026-10-23-context-diet-prompt-improvements.md` found the cause of much of the variance. In 13 of 48 pairs one cell of the pair started with a cold prompt cache and the other with a warm one. A cold start adds about 15k cost units. Removing the cold-start effect cuts the paired standard deviation from 11.7k to 7.0k. The same note estimates that detecting a one-call-per-cell saving needs about 53 pairs, which is more than the 24 pairs the cap allows.

**Decision:**

1. Before every measured cell, the harness runs one warmup call: a one-turn `claude -p` in the cell's own arm config and work dir. Its record goes to `<run dir>/warmup/` with `warmup: true` and is excluded from every statistic and pairing. Warming every cell, not only the first of each (arm, fixture), is needed because cold starts also occur mid-run with cells 1 to 2 seconds apart (research note, "Cold-start cache misses dominate the noise"). A warm warmup reads the prefix from cache, so it costs far less than the cold start it prevents. A failed warmup is a warning, never a cell failure.
2. The agentic gate may escalate to 13 seeds per fixture (52 pairs with 4 fixtures), set with `--max-seeds`. The escalation rule is otherwise unchanged: 3 seeds first, then one escalation only if the interval includes zero.
3. The estimated cost printed before a run must include the warmup calls.
4. The `cacheWeightedCost` formula (cache read 0.1x, cache write 1.25x) is unchanged. It is kept so results remain comparable with R1 and R2. The CLI's USD field is recorded but not used for the gate.

**Consequences:**

- Estimated cost per candidate is about $11 to $23 (research note, cell cost about $0.10). This is more than the earlier 6-seed cap allowed. Each run prints the estimate before it starts (ADR 0008 Consequences).
- The warmup doubles the number of calls. The extra calls are short, paid, and outside the gate.
- Each cell records `diagnostics.firstCacheRead`, and the summary note counts cold starts per arm, so a run can show whether the warmup worked.
- Pairs from runs before this ADR have no warmup. Their cold-start outliers stay in the record. Results from before and after this ADR are not pooled for the gate.
- `--no-warmup` exists for tests and for reproducing pre-ADR runs. A gate run under this ADR keeps the warmup on.
