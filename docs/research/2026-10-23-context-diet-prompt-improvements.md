# Context Diet: where the tokens go, and how to revise the prompt

Date: 2026-10-23

Question: how can the Context Diet supplement (`hooks/caveman-context-diet.md`, injected by `hooks/caveman-activate.js` on SessionStart and SubagentStart, governed by `docs/adr/0009-context-diet-supplement-section.md`) be improved, given that two live agentic runs found no measurable cost effect?

Evidence base:

- R1 = `bench/results/agentic-claude-sonnet-5-5-8c90768/` (72 cells + 72 streams)
- R2 = `bench/results/agentic-claude-sonnet-5-5-b56c077/` (72 cells + 72 streams)
- `docs/research/2026-10-23-bench-compare-8c90768-vs-b56c077.md` (pooled gate analysis)
- `docs/research/2026-10-21-bench-agentic-claude-sonnet-5-5-b56c077.md` (R2 note)
- Harness: `bench/lib/stream.js` (diagnostics), `bench/lib/stats.js` (cost formula), `bench/README.md`, `docs/adr/0008-live-benchmark-harness-in-bench.md`

No `node bench/run.js` call was made. All numbers below were recomputed from the R1 and R2 cell and stream files with throwaway Python scripts. Both runs have an identical configuration (see the comparison note), so the 48 cells per arm are pooled unless a run is named. 50 stream lines across the 144 stream files fail to parse and were skipped (probably the API-key redaction corruption described in the comparison note's caveats; not verified line by line). Usage figures come from the cell files and are unaffected.

## Summary

1. **The diet does what it says, but it pulls a small lever.** Pooled, it cuts total tool-result characters per cell by 1,596 (-15.8%, 95% CI ±944). This is the first diet effect whose interval excludes zero. All tool results together are only about 11% of the harness cost metric (about 4.5k of 40k cost units per cell). The diet's saving is worth about 770 cost units (about 2%). Its own text costs about 170 units per session. The expected net effect is about -1.5%, and the harness cannot resolve that at N=48.
2. **Cost is driven by the number of API round trips and by a fixed 17k-token prefix, not by file reads.** Every request re-reads a 17,156-token cached prefix (Claude Code system prompt plus tool definitions). Pooled regression: about +2.7k cost units per extra API call. A one-call reduction is worth more than the diet's whole Read saving. Only 15 to 19% of requests carry more than one tool call.
3. **The gate's noise is mostly a harness artifact.** In 13 of 48 gate pairs, one cell started with a cold prompt cache and the other with a warm one. A cold start adds about 15k cost units. The two R1 outlier pairs the comparison note names (noisylog s3 -28175, bigfile s1 -23212) are both "full cold, full-diet warm". Normalizing the cold start cuts the paired SD from 11,731 to 7,035.
4. **Two diet rules are ignored or gamed, and two are redundant.** In 3 of 12 `reuse` cells, the diet arm dumped the 13k-character file with `cat` through Bash. That bypasses `Read`, and the `readChars` diagnostic does not see it. In `rootcause`, the diet arm passes `limit: 220` or `230` for a file of about 220 lines, which is a whole-file read with an offset/limit label. "Never re-read" and "grep first" describe what every arm, bare included, already does.
5. **Top revision: target round trips.** Ask for batched independent calls and chained shell steps, allow one whole Read for small files, close the `cat` loophole, and guard against the diet suppressing verification. Proposed wording is in "Candidate revisions". The harness needs a cold-start-adjusted cost and a larger N to test any of these.

## What the harness measures

- Cost metric: `input + 0.1 x cache_read + 1.25 x cache_creation` tokens per cell (`bench/README.md`, "Gate and report"; ADR 0008 decision 7). Output tokens are excluded. They are recorded only as a diagnostic.
- `readChars` counts only characters returned by the `Read` tool. `reReads` counts `Read` calls whose range an earlier `Read` of the same path already covered (`bench/lib/stream.js`, header comment). File contents fetched through `Bash` (`cat`, `sed -n`, `head`) are counted by neither.
- The CLI-reported `totalCostUsd` in every R1/R2 cell matches `$2/M input, $0.20/M cache read, $2.50/M cache write, $10/M output` exactly (mean absolute error about 1e-17 USD over 144 cells). So the CLI prices cache reads at 0.1x. The current Anthropic pricing page lists Sonnet 5.5 cache hits at $0.10/M, which is 0.05x ([pricing](https://platform.claude.com/docs/en/about-claude/pricing), footnote 2; [prompt caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)). If the page is right, the harness and the CLI both over-weight cache reads by 2x. That makes the "re-sent every turn" share of cost even smaller than shown below.
- At list output price ($10/M = 5x input), output is about 8.3k input-equivalent units per cell (1,650 tokens x 5). That is about 17% of true cost, and the gate metric does not include it. The diet does not move output: pooled diff +23 tokens [-121, +167] (comparison note).

## Where the tokens go

### Cost decomposition per arm (pooled, 48 cells each)

Cost units are the harness metric. "First CW" is the cache write on the first request of the cell.

| Arm | Cost | First CW (x1.25) | Later CW (x1.25) | Cache read (x0.1) | API requests | Output tokens |
| --- | --- | --- | --- | --- | --- | --- |
| bare | 39,815 | 12,898 (32%) | 8,448 (21%) | 18,455 (46%) | 7.2 | 1,876 |
| full | 40,346 | 15,099 (37%) | 7,492 (19%) | 17,742 (44%) | 6.5 | 1,641 |
| full-diet | 39,842 | 14,827 (37%) | 7,090 (18%) | 17,911 (45%) | 6.7 | 1,664 |

Source: `usage` in every R1/R2 cell file, plus per-request `message.usage` in the streams.

- Uncached input is 13 to 14 tokens per cell, so it plays no role.
- Every warm first request reads exactly 17,156 tokens from cache (17,133 in a few bare cells). That is the Claude Code system prompt plus about 20 tool definitions (stream `init.tools`), identical in all arms. At 0.1x, each request pays about 1.7k units for this prefix before any task content. Over 6.5 to 7.2 requests per cell, that is about 11 to 12k units, or roughly 30% of cost. The kit cannot change it.
- Pooled across all 144 cells, cost correlates with API requests (r = 0.60) and turns (r = 0.61) far more than with Read chars (r = 0.21) or total tool-result chars (r = 0.35). The least-squares slope is +2,677 units per API request and +2,823 per turn.

### Cold-start cache misses dominate the noise

The first request of a cell is either warm (reads 17,156 from cache) or cold (reads 0 and writes the whole prefix). Cells ran one after another, 1 to 2 s apart (`finishedAt` and `durationMs`). Cold starts cluster at fixture switches (`bigfile s1`, `reuse s1`, R1 and R2) but also occur mid-run, which fits the caching docs' warning that hits require an identical prefix and that a cache entry becomes available only after the first response starts ([prompt caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)).

| Arm | Cold cells | Cold mean cost | Warm mean cost |
| --- | --- | --- | --- |
| bare | 9/48 | 50,614 | 37,323 |
| full | 9/48 | 53,715 | 37,261 |
| full-diet | 8/48 | 52,062 | 37,398 |

In 13 of 48 gate pairs, warmth differs between `full` and `full-diet`. Normalizing each cold cell by `-(1.25 - 0.1) x 17,156` gives:

| Paired full-diet - full | Mean | 95% CI | Paired SD |
| --- | --- | --- | --- |
| R1 raw | -3,711 | [-8,985, +1,564] | 12,489 |
| R1 cold-adjusted | -1,245 | [-3,464, +975] | 5,255 |
| R2 raw | +2,703 | [-1,600, +7,006] | 10,188 |
| R2 cold-adjusted | +1,059 | [-2,493, +4,611] | 8,411 |
| Pooled raw | -504 | [-3,911, +2,903] | 11,731 |
| Pooled cold-adjusted | -93 | [-2,136, +1,950] | 7,035 |

The sign flip between R1 and R2 shrinks from 6.4k to 2.3k after adjustment. Most of the swing the comparison note attributes to "full-diet low in R1, high in R2" is cache warmth. Mid-session cache misses are rare: 2 in 144 cells.

### Tool results: chars and attributed cost

Mean characters per cell returned by each tool, pooled (stream `tool_result` blocks; Bash split by command):

| Arm | Total | Read | Bash grep | Bash test (pytest) | Bash view (sed/cat/head/tail) | Bash other | Edit |
| --- | --- | --- | --- | --- | --- | --- | --- |
| bare | 10,272 | 6,539 | 1,444 | 1,360 | 374 | 182 | 331 |
| full | 10,113 | 6,106 | 1,630 | 1,226 | 672 | 121 | 329 |
| full-diet | 8,517 | 4,776 | 1,947 | 593 | 228 | 655 | 217 |

Attributed cost uses chars/3.5 as tokens, 1.25x for the write, plus 0.1x for each later request. Per cell this gives 4,780 units for bare, 4,555 for full and 3,788 for full-diet. Read accounts for 3,084, 2,762 and 2,158 of those. About 80 to 90% of a result's cost is its one-time cache write. The re-reads on later turns are the minor part, because sessions are short (median about 7 requests). The diet text's premise, "Tool output gets re-sent every turn", is therefore not the main cost mechanism on these fixtures. Paying for a result once, when it lands, is.

Paired full-diet minus full, pooled 48 pairs:

| Metric | Full mean | Diff | 95% CI half-width |
| --- | --- | --- | --- |
| Total tool-result chars | 10,113 | -1,596 (-15.8%) | ±944 |
| File-content chars (Read + Bash view + `cat`) | 6,778 | -1,257 (-18.5%) | ±1,061 |
| API requests | 6.5 | +0.2 | ±0.6 |
| Cold-adjusted cost | 36,647 | -93 | ±2,043 |

### Per fixture

Pooled means, 12 cells per arm (R1 + R2):

| Fixture | Arm | Cost | Turns | Requests | Result chars | Read | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| bigfile | full | 35,973 | 6.5 | 5.6 | 4,635 | 1,321 | 195 |
| bigfile | full-diet | 31,873 | 6.2 | 5.3 | 4,419 | 1,930 | 65 |
| noisylog | full | 37,394 | 8.7 | 7.1 | 6,471 | 910 | 3,671 |
| noisylog | full-diet | 39,339 | 9.8 | 8.4 | 4,990 | 651 | 1,478 |
| reuse | full | 35,767 | 7.6 | 4.0 | 15,406 | 13,407 | 0 |
| reuse | full-diet | 39,849 | 7.2 | 4.7 | 11,145 | 5,871 | 0 |
| rootcause | full | 52,250 | 10.7 | 9.5 | 13,942 | 8,788 | 1,037 |
| rootcause | full-diet | 48,307 | 9.5 | 8.4 | 13,514 | 10,653 | 830 |

- `noisylog`: the diet cut test output by 60%, yet cost rose. The diet arm made 1.3 more requests per cell. At about 2.7k per request, that outweighs the roughly 900 units saved on test output.
- `reuse`: Read chars fell 56%, but requests rose from 4.0 to 4.7. Six diet cells read `critic_ledger.py` in two windows (lines 1-66, then 228-end) instead of one whole Read (`full-diet--reuse--s{1..5}.stream.jsonl` across R1 and R2). Four diet cells also cold-started (`full-diet--reuse--s1/s5` R1, `s2/s4` R2).
- `bigfile`, the diet's intended case (2,100-line `model_router.py`), is already handled well by every arm: grep, then a narrow window. `full` reads only 1.3k chars here.

## Rule-by-rule: followed, ignored, redundant

| Rule (current text) | Evidence | Verdict |
| --- | --- | --- |
| "Grep symbol first." | All arms average 1.7 to 1.8 Bash grep calls per cell, usually as the first call. This CLI build has no Grep or Glob tool (stream `init.tools`), so "Grep" names a tool that does not exist. The model uses `grep` through Bash. | Redundant with baseline behavior. Capitalized tool name is misleading. |
| "Then Read with offset/limit, not whole file." | Read calls with no offset or limit: bare 24/47, full 22/38, full-diet 11/47. Whole-file Read chars: 285k, 264k, 124k. Letter-only compliance: `limit: 220`/`230` on the ~220-line `request_text.py` returns all 10,545 chars (`full-diet--rootcause--s5/s6`, R2; `s6`, R1). | Followed, partly in letter only. |
| (same rule, other channel) | `cd ... && cat critic_ledger.py` returned 12.2k chars in `full-diet--reuse--s1`, `s6` (R1) and `s3` (R2). `readChars` does not count it. No `full` cell did this. | Gamed. The diet shifts whole-file dumps from Read to Bash. Part of the 16-27% `readChars` drop the comparison note reports is this shift. |
| "Narrow at source: `ls dir`, `head`, `tail`." | Every arm already pipes pytest through `tail`/`grep`. Bash `ls` output is under 30 chars per cell in all arms. | Mostly redundant. |
| "Build/test: show failures + summary only." | noisylog test output per cell: bare 3,785, full 3,671, full-diet 1,478. Largest single test result: full 5,151, full-diet 768. | Followed. The clearest behavioral effect, but small in cost. |
| "Never re-read unchanged file." | `reReads` = 0 in all 144 cells, bare included (cell `diagnostics`). The only repeated same-file Reads are the diet's non-overlapping windows in `reuse`. | Redundant. |
| "Before edit: read every line edit touches..." | No errored `Edit` result in any arm (stream `is_error`). | Harmless. No measurable effect. |

**Possible side effect on verification.** On `bigfile`, the diet arm ran no test at all in 9 of 12 cells, against 5 of 12 for `full` and 7 of 12 for bare. Some final answers say "I haven't run the tests" (for example `full-diet--bigfile--s1.json`, R2). Every hidden test passed, so this cannot be seen in the guardrail (ceiling noted in the comparison note). With N=12 it may be chance. Still, "Read less" can generalize to "check less". Anthropic's Sonnet 5.5 guide treats skipped verification as a known failure mode to prompt against ([Prompting Claude Sonnet 5.5, Verification on coding tasks](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#verification-on-coding-tasks)).

## What the primary sources say

- **Context is the main constraint, and every file read costs.** "Claude's context window holds your entire conversation, including every message, every file Claude reads, and every command output." ([Claude Code best practices](https://code.claude.com/docs/en/best-practices)). The costs page explains why usage climbs: "each time Claude uses tools it sends another request carrying that batch of tool results", re-read at the cached rate ([Manage costs](https://code.claude.com/docs/en/costs#why-usage-climbs-in-a-long-session)). Requests, not just bytes, drive cost. This matches the regression above.
- **Parallel tool calls are steerable.** Anthropic gives a sample prompt: "If you intend to call multiple tools and there are no dependencies between the tool calls, make all of the independent tool calls in parallel... For example, when reading 3 files, run 3 tool calls in parallel..." It says this boosts parallel calling "to about 100 percent" ([Prompting best practices, Optimize parallel tool calling](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices)). The R1/R2 streams show only 15 to 19% of requests carry more than one tool call.
- **Deterministic filtering beats advice.** The costs page recommends a PreToolUse hook that rewrites test commands to `... 2>&1 | grep -A 5 -E '(FAIL|ERROR|error:)' | head -100` ([Manage costs, Offload processing to hooks and skills](https://code.claude.com/docs/en/costs#offload-processing-to-hooks-and-skills)). The best-practices page says: "Unlike CLAUDE.md instructions which are advisory, hooks are deterministic". It also says to delete rules Claude already follows: "If Claude already does something correctly without the instruction, delete it or convert it to a hook." ([best practices](https://code.claude.com/docs/en/best-practices)).
- **Explain why, and say what to do rather than what not to do.** "Providing context or motivation behind your instructions... can give Claude more information about your goals". "Tell Claude what to do instead of what not to do" ([Prompting best practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices)). Anthropic also warns that tool-discouraging language ("minimize tool calls") can make Sonnet 5.5 skip useful tool use ([Prompting Claude Sonnet 5.5, Tool use in chat](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#tool-use-in-chat-and-knowledge-work)). A diet rule should therefore ask for batching, not for fewer checks.
- **Caching mechanics.** 5-minute writes cost 1.25x, reads 0.1x (0.05x on Sonnet 5.5 and Opus 5.5). The cache lifetime is 5 minutes from the start of the request. Hits require "100 percent identical prompt segments", and the prefix order is tools, system, messages ([prompt caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)). In short sessions, a tool result's cost is mostly its one-time 1.25x write.
- **Tool result clearing exists server-side but does not apply here.** `clear_tool_uses_20250919` clears old results past a trigger (default 100,000 input tokens). It "invalidates cached prompt prefixes when content is cleared" ([context editing](https://platform.claude.com/docs/en/build-with-claude/context-editing)). The fixture sessions peak around 30k tokens, far below the default trigger. Claude Code manages compaction and clearing itself, and a hook cannot turn it on per session. This lever belongs to long sessions, not to the four fixtures.

## Candidate revisions

Ranked by expected cost impact on the harness metric. Each needs its own gate run.

### Fixed cost of the text

Current section: 324 characters after comment stripping, 334 more injected than `full` (comparison note). That is about 90 tokens. Cost per session is about 1.25 x 90 + 0.1 x 90 x 6 later requests, roughly 170 units (0.4% of a 40k cell). Each extra 100 characters adds about 50 units per session, plus the same again per SubagentStart. A rule must save more than this to pay for itself.

### C1. Batch round trips (highest expected impact)

Proposed line:

```
- Batch independent calls in one turn. Chain related shell steps in one command.
```

- Evidence: about 2.7k units per request (pooled regression). Only 15 to 19% multi-tool requests (streams). Diet `noisylog` and `reuse` lost their char savings to +0.7 to +1.3 extra requests.
- Source: Anthropic's parallel-tool-calls prompt (above).
- Expected: one fewer request per cell is about -2.7k (-7%). Risk: speculative parallel reads may add chars. The 80 characters add about 40 units.

### C2. Allow one whole Read for small files

Proposed replacement for the grep/offset rule:

```
- Find with `grep -n`, then one Read with offset/limit around the hit. File under ~300 lines: one whole Read.
```

- Evidence: in `reuse`, six diet cells split a 13k-char file into two windows and averaged +0.7 requests. In `rootcause`, the model already passes `limit` at or above the file length. The rule then costs a call and saves nothing. Also replaces the nonexistent "Grep" tool name with `grep -n`, which is what the model runs.
- Expected: removes the extra windowing call on small files, about -1 to -2k on `reuse`-like tasks. It may raise Read chars on mid-size files, so watch `readChars`.

### C3. Close the `cat` loophole

```
- `cat`/`sed` dumps count as reads.
```

- Evidence: 3 diet `reuse` cells dumped 12.2k chars through `cat`. That is 3.5k tokens written at 1.25x, about 4.4k units per occurrence.
- Expected: small on average (about -300 units per cell), large on the affected cells. It also makes `readChars` honest.

### C4. Make the test rule concrete, and keep verification

```
- Tests: narrowest target first (`file::test`, `-k`), piped to failures + summary. Still run one.
```

- Evidence: the diet already cut test output 60% on `noisylog`. The remaining large test results came from broad `-k "rate or limit"` runs (up to 5,151 chars in `full--noisylog--s1`, R2). "Still run one" guards the bigfile no-test pattern (9/12 vs 5/12) and follows Anthropic's Sonnet 5.5 verification guidance.
- Expected: about neutral on cost (a test run is about 2.7k for the call; filtered output is small). Protects quality the hidden tests cannot see.

### C5. Drop redundant rules

Remove "Never re-read unchanged file." (`reReads` = 0 in all 144 cells, bare included) and "Narrow at source: `ls dir`, `head`, `tail`." (all arms already pipe through `tail`/`grep`; `ls` output is negligible). This follows the best-practices advice to delete rules Claude already follows.

- Expected: saves about 80 characters, about -40 units per session. Risk: on other models or longer sessions, the re-read rule may matter. Keep it if the target population includes long sessions where re-reads occur.

### C6. Correct the motivation line

```
Every tool call re-bills the whole context. Every result is billed when it lands. Fewer calls, smaller results.
```

- Evidence: in these sessions, 80 to 90% of a result's cost is its one-time write, and each request re-reads the whole prefix. "Re-sent every turn" names only the minor mechanism and says nothing about call count. Anthropic recommends giving the reason behind an instruction.
- Expected: no direct saving. It frames C1 to C4.

### Combined proposal

The current text with C1 to C6 applied is 499 bytes, within ADR 0009's 500-character target:

```
## Context Diet

Every tool call re-bills the whole context. Every result is billed when it lands. Fewer calls, smaller results.
- Batch independent calls in one turn. Chain related shell steps in one command.
- Find with `grep -n`, then one Read with offset/limit around the hit. File under ~300 lines: one whole Read.
- `cat`/`sed` dumps count as reads.
- Tests: narrowest target first (`file::test`, `-k`), piped to failures + summary. Still run one.
- Before edit: read every line edit touches.
```

This is 175 characters longer than today, about +85 units per session. It pays off if C1 saves a fraction of one request per cell.

### Outside the prompt (higher certainty, for a separate decision)

- **Deterministic test-output filtering** via a PreToolUse `updatedInput` hook, as in the Claude Code costs page. It would make C4 unnecessary and cost zero context. This is a new install-time mutation, so CLAUDE.md requires a backup, a manifest field, an uninstall path and a new ADR.
- **Longer-session fixtures.** The re-send share of cost grows with session length. The four fixtures average about 7 requests, which is where the diet's premise is weakest. A fixture of 25+ requests would test the case ADR 0009 was written for. SubagentStart delivery is also untested (no SubagentStart fired in 144 cells, comparison note).

## How to test the candidates with the existing harness

### Harness fixes first (no hook changes)

1. **Cold-start adjustment.** Report `cost - 1.15 x first_request_cache_read_deficit` or cost excluding the first request, next to raw cost. Better still, run a one-turn warm-up `claude -p` call with the same config before each cell, so every cell starts warm. Adjustment cuts paired SD from 11,731 to 7,035 and the needed N by about 2.8x. This changes the gate metric, so it needs an ADR 0008 amendment.
2. **Count every file ingest.** Add total tool-result chars, Bash file-dump chars and API request count to `diagnostics` (`bench/lib/stream.js`). Today a `cat` dump scores as a `readChars` win.
3. **Fix the redaction guard** (comparison note caveat). It probably accounts for the 50 unparseable stream lines skipped here.

### Arms and pairing

- One arm per candidate, measured as the real `hooks/caveman-context-diet.md` on a branch worktree via `--kit-dir`, with `--run-id` per candidate. This is the ADR 0009 pattern. Gate each candidate as `full-diet` (candidate text) minus `full`.
- "Seed" is a repeat index, not a model RNG seed (`bench/README.md`: never passed to `claude`). Pairing by seed therefore adds no variance reduction beyond blocking by fixture. Under that design, the 48 existing `full` cells from R1 and R2 (byte-identical injected context) could serve as the reference arm for fixture-blocked comparisons, which halves the quota per candidate. The trade-off is day-to-day drift: bare and full reproduced within ±3% between R1 and R2. Using them outside the per-run gate needs an ADR 0008 change.
- Recommended order: C1 alone first (largest expected effect, cleanest mechanism), then the combined text.

### Sample size

Pooled paired SDs from R1 + R2 (pairs needed for 80% power at two-sided 95%: `n = (2.8 x SD / effect)^2`):

| Metric | Paired SD | Effect 5% of full | Pairs for 80% power |
| --- | --- | --- | --- |
| Raw cost | 11,731 | 2,017 | 266 |
| Cold-adjusted cost | 7,035 | 1,832 | 116 |
| Cold-adjusted cost, effect = one request (2.7k) | 7,035 | 2,700 | 53 |
| Total tool-result chars (diagnostic) | 3,252 | 506 | 325 |
| Total tool-result chars, effect = observed -1,596 | 3,252 | 1,596 | 33 |

- The current gate caps at 6 seeds (24 pairs). At that N, the 95% half-width on raw cost is about ±5k (12%). That cannot resolve the current diet (expected about -1.5%) or any single rule here except a large C1 effect.
- To resolve a C1-sized effect (about 7%) on cold-adjusted cost: about 53 pairs, which is 13 to 14 seeds per fixture. To resolve 5%: about 116 pairs (29 seeds per fixture).
- Quota: the CLI reported $0.09 to $0.10 per agentic cell (`totalCostUsd`, R1/R2), far below `lib/estimate.js`'s $1.08 budget. 53 pairs is about 106 cells, roughly $11. 116 pairs is roughly $23, or about half that if existing `full` cells are reused.
- These N exceed ADR 0008's 6-seed cap. Raising the cap, or adopting the cold-adjusted metric, needs a new ADR. Without it, any revision of the diet will again end `no-ship` by construction.

## Caveats

- Attributed per-tool cost uses chars/3.5 as tokens and ignores tokenizer variation. It is an estimate of the cost structure, not a billed figure.
- The cold-start adjustment assumes the missed prefix is the 17,156-token warm read seen in every warm cell.
- The verification side effect (bigfile 9/12 vs 5/12 no-test cells) rests on 12 cells per arm and may be chance.
- Pricing: the CLI and the harness use 0.1x for cache reads, and the pricing page says 0.05x for Sonnet 5.5. This changes the shares, not the ranking: under 0.05x, request count and cache writes dominate even more.
