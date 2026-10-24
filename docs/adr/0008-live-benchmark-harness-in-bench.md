---
artifact-type: adr
lineage-rules: exempt
---

# ADR 0008: Live benchmark harness in `bench/`, gated by measured results

**Status**: Approved

**Context:**

The kit changes its injected ruleset and per-turn reminder without measuring them. Commit `e11e665` added a "focus" directive to the reminder with no evidence. Chisle measured a near-identical directive on its own ruleset and it raised billed output from 82% to 95% of a bare model (`Chisle:benchmarks/results/2026-10-01-backfires.md`). A single prompt also varies 0.18x to 5.57x between runs of the bare model, so single cells mean little.

**Decision:**

1. Add a maintainer-only harness in `bench/` at the repo root, written in Node. It is never copied by `install.sh` or `update.sh`, so it adds no runtime footprint and no manifest field. It runs by hand, not in CI (`.github/workflows/smoke.yml` is unchanged).
2. Two harness kinds:
   - **Single-turn:** `claude -p` with no repo. Arms: bare, bare-control, `lite`, `full`, `ultra`, and `ultra` without the focus directive. 6 arms × 6 tasks × 3 seeds.
   - **Agentic:** fixture repos with a planted trap, real tools, and a hidden test copied in after the run. Arms: bare, `full`, `full` + Context Diet. 3 arms × 4 fixtures × 3 seeds (5 fixtures since ADR 0012, 6 since ADR 0013).
3. Each arm runs the kit's real hooks. Each arm gets an isolated config dir whose `settings.json` registers the kit's SessionStart, UserPromptSubmit and SubagentStart hooks, with a seeded flag file. The "no focus directive" arm uses a temp copy of the hook, patched for that arm. The agentic `full` arm runs the real hooks with `CAVEMAN_CONTEXT_DIET=0` in its environment. That variable is the user-facing runtime opt-out from ADR 0009, not a benchmark-only switch. Shipped code gets no benchmark-only switches.
4. Isolation authenticates with an `ANTHROPIC_API_KEY` supplied by the maintainer, in a temp config dir (`0700`, removed on exit). A credentials file copy is the fallback only.
5. Fixtures are clones of pinned commits of `nj4x/anthrouter` and `nj4x/skills-dev`, with a per-fixture patch that plants the bug. The four fixtures are `bigfile`, `rootcause`, `noisylog` and `reuse`; ADR 0012 adds a fifth, `suitecheck`, and ADR 0013 a sixth, `parallel`. A fixture whose tests cannot run reliably offline is dropped, not replaced silently. The harness needs `git`, `python3` and `pytest` or `uv`. This dependency applies to `bench/` only. Node stays the sole runtime requirement.
6. Default model `claude-sonnet-5-5`, overridable to `claude-opus-5-5`. Haiku 4.5 is not the default. Seeds: 3.
7. Metrics differ per harness kind:
   - **Both harnesses:** primary metric is cache-weighted input cost per cell (cache read 0.1×, cache write 1.25×).
   - **Single-turn:** billed output tokens per cell is a co-primary metric. The harm cited in the Context (the focus directive) is an output-token regression, which input cost alone cannot detect. A single-turn change must not regress either co-primary metric.
   - **Agentic:** guardrail is the hidden-test pass rate, which must not drop. The single-turn harness has no hidden tests, so this guardrail does not apply there.
   - Diagnostics (agentic): total Read characters, re-reads of unchanged files, turn count, test runs (ADR 0012), and subagent calls and SubagentStart fires (ADR 0013). Billed output tokens are also recorded as a diagnostic.
8. A change to the ruleset ships only when the 95% confidence interval for the difference excludes zero in the good direction. The noise baseline depends on the harness:
   - **Single-turn:** the difference (candidate arm minus its reference arm) is compared against the bare-vs-bare control (bare vs bare-control).
   - **Agentic:** there is no bare-control arm. The gate uses the paired difference `full` + Context Diet minus `full`, paired by fixture and seed (4 fixtures × 3 seeds = 12 pairs; 15 pairs with the 5 fixtures of ADR 0012, 18 with 6 in ADR 0013). The confidence interval is computed from those pairs, so seed-to-seed spread within each arm is the noise baseline. The bare arm is a reference point only and plays no part in the gate. If the interval includes zero after 3 seeds, rerun with up to 6 seeds (24 pairs; 30 with 5 fixtures, 36 with 6). If it still includes zero, the change does not ship.

   Raw cells are committed under `bench/results/`. Each result gets a summary note in `docs/research/`.
9. `bench/README.md` documents usage and the Python requirement.

**Consequences:**

- Maintainers spend real API quota on each run. The harness must print an estimated cost before it starts.
- The harness can read the kit's hook scripts but never modifies them. Only the temp copy is patched.
- Fixture repos are pinned by SHA, so runs reproduce. Cloning needs network access per run.

**Source SRS:** none (repo uses `lineage-rules: exempt`).
