---
artifact-type: adr
lineage-rules: exempt
---

# ADR 0013: A subagent fixture and a SubagentStart diagnostic

**Status**: Approved

**Context:**

ADR 0009 decision 2 injects the Context Diet on SessionStart and on SubagentStart. In the 8c90768 and b56c077 agentic runs only `SessionStart:startup` fired. No fixture led the agent to spawn a subagent, so the benchmark never measured the SubagentStart half of the injection (issue #13, `docs/research/2026-10-23-bench-compare-8c90768-vs-b56c077.md`, "Caveats").

Two harness facts also hid the hook. The agentic `claude -p` call did not pass `--include-hook-events`, so a stream carries no way to tell which hooks fired beyond what the CLI emits by default. And no diagnostic counted subagent spawns or fires.

**Decision:**

1. Add a sixth fixture, `parallel`, under the rules of ADR 0008 decision 5: the same pinned `nj4x/anthrouter` commit, a plant patch that is the `bigfile` and `noisylog` plants together (two independent bugs in two files), and an offline hidden test that checks both fixes. The prompt reports both symptoms and asks the agent to start one subagent per bug with the Task tool, then apply both fixes.
2. The agentic `claude` call passes `--include-hook-events`, so `hook_started` events for SubagentStart appear in the stream.
3. Each agentic cell records `diagnostics.subagentCalls` (Task or Agent tool calls) and `diagnostics.subagentStarts` (SubagentStart fires, one per `hook_id`; an event without one counts on its own). The per-arm table shows `subagent_start`, the cells with at least one fire out of the cells that record it (`n/a` for older cells). The summary note adds a line with the fires and the calls per arm. They are diagnostics only and play no part in the gate.
4. The default agentic fixture set becomes six fixtures, so that every gate run measures the SubagentStart injection that ADR 0009 ships; an opt-in fixture would leave the default gate as blind to it as before. The gate rule (ADR 0008 decision 8, ADR 0010) is unchanged, and `--fixtures bigfile,noisylog,reuse,rootcause,suitecheck` reproduces the earlier set. What SubagentStart injects is unchanged.
5. A cell's `usage` covers the whole session. The CLI ran the subagents in the background, and each time one reported back after the main thread had stopped, the stream got another `result` event: 2 or 3 per `parallel` cell. Each event's `usage` and `num_turns` cover only its own segment of the main thread; `modelUsage` on the last event is cumulative and includes the subagents. `subtype` and `is_error` come from the last event only, so a max-turns stop in an earlier segment is not seen. `stream.analyze` now returns the last event with `usage` set to the `modelUsage` sum (else the sum over the events, which covers the main thread only) and `num_turns` summed. In all 68 b56c077 streams that carry `modelUsage`, its sum equals `usage`, so earlier cells stay comparable.

**Evidence:**

A 3-seed run of `parallel` alone (`agentic-claude-sonnet-5-5-parallel-13`, `docs/research/2026-10-24-bench-agentic-claude-sonnet-5-5-parallel-13.md`, fixture floor lowered, so not a valid gate): SubagentStart fired in 3 of 3 cells in each of `bare`, `full` and `full-diet`, 6 fires per arm (two subagents per cell). In the `full-diet` streams the Context Diet text appears in the SessionStart and both SubagentStart hook outputs, and not in `full` or `bare`. Subagents therefore can be triggered reliably in headless `claude -p` when the prompt asks for them. All 9 cells passed the hidden test, scored by an earlier version of it with 3 tests; the committed one has 5 (the out-of-range, malformed and missing-header cases were restored after review), and the cells were not re-scored. The cells were first written with the last `result` event's usage only; they were re-derived from their stored streams after decision 5. Cache reads per cell rose from 117,656–186,196 to 258,412–363,433.

**Consequences:**

- An agentic run costs about 20% more: 54 runs instead of 45 at 3 seeds.
- The fixture asks for subagents by name, so it measures the cost of the SubagentStart injection when the agent delegates. It does not show how often an agent delegates unprompted.
- `parallel` reuses the `bigfile` and `noisylog` plants, so it is not independent of them. The gate's fixture floor still counts it as a fixture.
- Subagent messages in the stream are counted with the main thread's: `readChars`, `reReads` and `testRuns` include the subagents' tool calls.
- `parallel` is not calibrated for difficulty: all 9 cells passed in every arm, like the first four fixtures. It adds no power to the pass-rate guardrail.
- Streams recorded without `--include-hook-events` read `subagentStarts` 0 even when the hook ran. Earlier cells carry no `subagentStarts` field and show `n/a`.

**Source SRS:** none (repo uses `lineage-rules: exempt`).
