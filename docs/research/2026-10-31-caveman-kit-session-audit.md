# caveman-kit session audit, 2026-10-31

Scope: Claude Code traffic from 2026-11-01 00:50 to 03:56 UTC (2026-10-31 17:50 to 20:56 local). Sources:

- `~/.anthproxy/anthproxy.db`, table `requests`, read-only.
- The Claude Code transcripts for the same sessions under `~/.claude/projects/*/<session>.jsonl` and `<session>/subagents/*.jsonl`.

## Evidence limits

- In this window `requests.raw_request_body` and `raw_outbound_body` are NULL for all 4106 rows. `user_prompt_text` holds only the newest user block, which is either the typed text or the last `tool_result`. Hook `additionalContext` is rendered as a separate `<system-reminder>` block, so the proxy never stores it. For example, request 617227 (session `83b67ca8`, 02:53:33, first request of the session) contains no `CAVEMAN MODE ACTIVE` string, even though the transcript shows the injection was made. Injection checks therefore use the transcripts. The proxy supplies token counts, response text and system-prompt hashes (`prompt_store`).
- Recommendation: if this audit should be repeatable from the proxy alone, turn on raw body capture in anthproxy, or extract every `<system-reminder>` block.

## Sessions in window

| Session | Repo | Requests (proxy) | Real user turns | Subagents with SubagentStart injection |
|---|---|---|---|---|
| `14ef021a` | pro-trading | 2338 | 22 | 144 (83 Explore, 61 general-purpose) |
| `81ada703` | caveman-kit | 454 | 17 | 44 |
| `83b67ca8` | pro-trading | 1920 | 1 (plus 37 queued notifications) | 178 |
| `5a7c9726` | caveman-kit | 6+ | 1 | 1 |

Flag files: `~/.claude/.caveman-active` = `ultra`, `caveman-kit/.claude/.caveman-mode` = `ultra`, `pro-trading/.claude/.caveman-mode` = `ultra`. All flags agree, so whichever file wins resolution, the mode is `ultra`.

## Q1 findings

### Session start: OK

- Each main session has exactly one `SessionStart:startup` hook. It produced one `hook_additional_context` of 2815 to 2834 chars, starting with `CAVEMAN MODE ACTIVE — level: ultra` followed by `# ultracave`, which is the ultracave ruleset. Timestamps: `81ada703` 00:53:01, `83b67ca8` 02:53:26, `5a7c9726` 03:55:23.
- Header changed during the window. Sessions that started before 03:49 UTC got the older header without a suffix. `5a7c9726` (03:55) got `CAVEMAN MODE ACTIVE — level: ultra (rules: ultracave)`. The installed `~/.caveman-kit/hooks/caveman-activate.js` has mtime 20:49 local (03:49 UTC), which matches the `update.sh` run after PR #42 (header code at `hooks/caveman-activate.js:163`). This is expected drift, not a bug.
- Ruleset selection for ultra is in `hooks/caveman-activate.js:78-102`. The `ultracave` body was used every time, with no fallback.

### Each user turn: OK

- `hooks/caveman-mode-tracker.js:69-75` emits `CAVEMAN MODE ACTIVE (ultra) — session ruleset applies. ...` (263 chars). Every real user prompt in all four sessions is followed by exactly one such context, with the same timestamp. Examples from `81ada703`: 02:40:27 "are we ready to open pr ?", 02:41:09, 02:42:34, 03:32:30, 03:33:27 `/switch`. Turns where the reminder is missing: 0.
- Other command envelopes, such as `/implement-spec`, `/switch` and `/research`, still get the reminder. This is the `skipParse` path at `caveman-mode-tracker.js:32-44`.

### Duplicates: minor, by design

- Each task-notification or queued command fires its own UserPromptSubmit. In `83b67ca8`, 13 identical reminders landed at 03:10:38, 9 at 03:24:21 and 13 at 03:47:55, against a single typed prompt. That is 37 reminders × about 65 tokens, roughly 2.4k tokens, much of it in the same request. The cost is small and the reminders are appended after the cached prefix. A possible cheap fix is to skip the reminder when the prompt starts with `<task-notification>`. Severity: low.
- SessionStart was never injected twice.

### Subagents (ADR 0005): OK

- All 367 subagents started in the window got exactly one `SubagentStart` context with level `ultra` and the ultracave body. That covers both Explore and general-purpose types. None got UserPromptSubmit reminders, which is expected because subagents have no user turns. The hook is wired as `SubagentStart → caveman-activate.js` in `~/.claude/settings.json`.
- Cost: about 700 tokens per subagent, which is about 125k input tokens across the 178 subagents of `83b67ca8`. Most of it is cache-created once per subagent, and the prefix is identical across subagents.

### Mode switches, compaction, resume: not exercised

- The window has no `/caveman <mode>` prompt, no `compact_boundary`, and no `SessionStart:compact` or `SessionStart:resume`. Continuity after compaction and switch handling could not be verified from logs. They remain covered only by bats tests.

### Prompt cache: OK

- The SessionStart context sits in the first user message, and the reminders are appended to the newest message. Both strings are byte-stable within a session (constant 263 and 2815 chars), so no prefix is invalidated. Proxy rows show steady cache reads, for example `81ada703` request 617171 cr=86077, through 618505 cr=105754 with small `cache_creation` values (230 to 1505).

### Terse output: partial

- Main-session replies are short but in grammatical prose, not ultracave fragments. Examples:
  - 617183: "PR is open: ... It's a regular PR, not a draft, and it's mergeable with no CI checks configured."
  - 618494: "Working tree is clean. Deleted the bench results directory and the summary note." (26 output tokens)
- Subagent reports in `83b67ca8`, such as 617941, 618023 and 618412, are full sentences with headed sections. They average 293 chars of final text and 673 output tokens per request, including tool calls.
- Brevity holds, but "Drop articles, copulas" (ultracave rule 1) is mostly not followed. The likely cause is the much larger Claude Code system prompt plus the harness's communication guidance. The kit cannot fix this, and the delivery side works. To measure it, use `bench/`, not this log.

### Housekeeping: low

- `~/.caveman-kit/hooks/caveman-context-diet.md` (Oct 20) is not in the repo's `hooks/` and nothing references it. It is a leftover that `update.sh` does not prune. It is harmless.
- `~/.claude/settings.json` also wires a separate tool, `~/.caveman/bin/caveman-proxy native-hook` (@caveman-ai/cli), to SessionStart, SubagentStart, UserPromptSubmit and the tool and compact events. In `83b67ca8` it produced no `hook_additional_context`, so it adds no duplicate ruleset, but it is a second "caveman" in the hook chain and adds latency on every event.

## Q2: `~/.claude/CLAUDE.md` interaction

1. **Redundant with the kit.** The line "Report in caveman style (terse fragments, every technical fact kept) ... Commits, PRs, issues, docs, and memory files stay normal prose" repeats two things the injected ruleset already says: rule 1 (fragments) and "When to break the rules: anything persisted outside chat". It costs about 40 tokens. The whole file, bash/zsh notes included, is about 450 tokens. It is sent in every main and subagent request (request 617227 `user_prompt_text` line 6, and this audit's own subagent prompt). After the first request it is cache-read, so the cost is low.
2. **Conflicts with `off`.** "until the user turns it off" is not tied to the kit's flag. After `/caveman off`, the tracker clears the flag and stops the reminder (`caveman-mode-tracker.js:56-58,66`), but CLAUDE.md still tells the model to use caveman style. Mode `off` therefore does not fully turn off terse output, and `lite` gets "terse fragments", which is stricter than lite's rules. Severity: medium (a correctness bug for `off` and `lite`, though not in the kit code). Fix: delete the line and let the kit own the style, or reword it to "Follow the caveman-kit mode; when it is off, write normal prose."
3. **Concise output style.** Every turn carries "Concise output style is active. Be concise: lead with the result, skip preamble..." in the same reminder block as the caveman reminder (104 occurrences in `81ada703`). It points the same way as the kit, with about 25 tokens per turn of overlap. It does not conflict, but it is a third brevity instruction, and it stays active under `off` too.
4. **Bash/zsh notes** are unrelated to caveman and do not interfere.

## Severity summary

| Item | Severity |
|---|---|
| SessionStart, UserPromptSubmit and SubagentStart delivery, mode consistency, cache stability | OK |
| CLAUDE.md caveman line overrides `/caveman off` and tightens `lite` | Medium (config, not kit code) |
| Repeated reminder per queued task-notification (37 in `83b67ca8`) | Low |
| Ultra grammar rules weakly followed; replies brief but prose | Low/observation |
| Stale `caveman-context-diet.md` in install dir; second caveman-proxy hook chain | Low |
| Proxy cannot see hook injections (raw bodies NULL) | Tooling gap |
| Compaction, resume and `/caveman` switches | Not exercised in window |
