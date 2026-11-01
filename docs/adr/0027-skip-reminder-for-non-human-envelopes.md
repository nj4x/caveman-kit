---
artifact-type: adr
lineage-rules: exempt
---

# ADR 0027: Skip the per-turn reminder for non-human envelopes

**Status:** Accepted. Amends ADR 0004 decision 6: the per-prompt reminder path no longer reads or emits for non-human envelopes.

**Context:**

`caveman-mode-tracker.js` (UserPromptSubmit) re-asserts the mode reminder on every prompt. Claude Code also fires UserPromptSubmit for queued background-task notifications, so one typed prompt produced many identical reminders. Session 83b67ca8 got 37 reminders for one typed prompt, about 2.4k tokens (audit: `docs/research/2026-10-31-caveman-kit-session-audit.md`). The same envelopes also reach mode parsing, so text inside a notification such as `/caveman off` could change the mode.

**Decision:**

1. Prompts starting with an allowlisted non-human prefix get no reminder and no mode parsing. The allowlist is `<task-notification>`, `<side-sessions-event>`, `<ci-monitor-event>` (`hooks/caveman-mode-tracker.js`). The hook returns before any other work, so a skipped prompt also never writes or clears the flag file. The three prefixes are the envelopes seen in the audit; no upstream spec lists them.
2. Each prefix has a bats case in `tests/caveman-mode-tracker.bats`.
3. Unknown envelopes keep today's behaviour. New non-human envelopes are added to the allowlist, not detected generically.

**Consequences:**

- Reminder tokens per background event drop to zero.
- Mode can no longer be changed from notification text.
- A new harness envelope that a human does not type needs an allowlist entry and a test, or it gets a reminder again.
