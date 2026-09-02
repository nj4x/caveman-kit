---
artifact-type: adr
lineage-rules: exempt
---

# ADR 0005: Deliver caveman mode ruleset to subagents via SubagentStart hook

**Status:** Accepted

**Context:**

caveman-kit registers `caveman-activate.js` under `SessionStart` only (`lib/settings-patch.js`). Subagents spawned during a session run as separate Claude Code sessions with their own transcript — they never see the parent's `SessionStart` hook, so a subagent inherits no caveman ruleset even when the parent session has `/caveman full` (or any other mode) active. The user reasonably expects delegated work to keep the same response style as the session that delegated it.

The sibling kit peer-agent-kit hit the identical problem for its own mode and solved it (ADR-0079, commit 3e19e18): register the same activation script under `SubagentStart` as well as `SessionStart`, since Claude Code passes `cwd` in both events' stdin payload (per the official hook docs — SubagentStart input carries `session_id`, `cwd`, `hook_event_name`, `agent_id`, `agent_type`; verified working in peer-agent-kit's bats test "honors the repo-scoped mode flag via cwd under SubagentStart"), letting repo-scoped mode resolution work unchanged for a subagent.

peer-agent-kit's first attempt (3e19e18) registered `SubagentStart` but reused the hook script unmodified — at the time it wrote a plain string to stdout. That shipped broken: `SubagentStart`'s hook contract only recognizes a JSON `hookSpecificOutput.additionalContext` field, not raw stdout, so subagents were silently getting no context at all. The fix (91270b4) rewrote the script to emit that JSON envelope, echoing back whichever `hook_event_name` fired (`SessionStart` or `SubagentStart`) so the same script serves both events correctly. A separate, unrelated bug in the same area (9b7afc8) was peer-agent's own SKILL.md ruleset text containing forward references ("everything in lite") that broke once per-mode filtering stripped the referenced content — checked and confirmed **not present** in caveman's SKILL.md, whose mode table rows and examples are already fully self-contained per mode, so no ruleset-content rewrite is needed here.

**Decision:**

1. Register `caveman-activate.js` under `SubagentStart` in `lib/settings-patch.js`, using the same marker (`'caveman-activate.js'`) as the existing `SessionStart` registration so install/uninstall stay coupled. Mirror the removal in `lib/settings-unpatch.js`.
2. Rewrite `hooks/caveman-activate.js`'s output from today's plain `process.stdout.write(string)` to a JSON `hookSpecificOutput` envelope carrying `hookEventName` (defaulting to `'SessionStart'`, echoed from stdin's `hook_event_name` field when present) and `additionalContext` — required, not cosmetic, since `SubagentStart` ignores plain stdout entirely. Mirror only the envelope and `hookEventName` echo from peer-agent-activate.js's current (post-91270b4) implementation; caveman's existing exact-match per-mode filtering stays unchanged — do not adopt peer-agent's rank-based cumulative `modeRank`/`exampleRank` filtering, which exists only to serve peer-agent's cumulative mode semantics.
3. Add three tests to caveman-kit's bats suite covering `caveman-activate.js`, mirroring peer-agent-activate.bats: default `hookEventName` to `SessionStart` when input omits it; echo `hook_event_name` back for `SubagentStart`; honor the repo-scoped mode flag via `cwd` under `SubagentStart`.
4. Update `install.sh`, `uninstall.sh`, and `README.md` docstrings to list `SubagentStart` alongside `SessionStart`/`UserPromptSubmit`; likewise the header comments of `lib/settings-patch.js` and `lib/settings-unpatch.js`, and add the matching `SubagentStart hook: added/removed` console log lines next to the existing SessionStart/UserPromptSubmit ones.

**Consequences:**

- Existing tests asserting on `caveman-activate.js`'s raw stdout string break and must be updated to extract `additionalContext` from the JSON envelope (same backward-compat extraction pattern peer-agent-activate.bats uses).
- The output-format change is internal to the hook's stdout contract; Claude Code accepts the JSON envelope for `SessionStart` as well, so no user-visible behavior changes for the existing `SessionStart` path.
- No change to `caveman-config.js` mode resolution — `cwd`-based repo-scoped flag lookup already worked from any `cwd`, subagent or not.
- When mode is `off`, `caveman-activate.js` exits 0 with no stdout under both events; Claude Code treats empty hook output as no additional context, so a subagent receives no ruleset — consistent with `off` semantics.
