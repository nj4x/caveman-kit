---
artifact-type: adr
lineage-rules: exempt
---

# ADR 0006: Drop wenyan mode support from the kit

**Status:** Accepted

**Context:**

The kit auto-wires the upstream caveman skill, which defines seven intensity modes. The kit currently mirrors all of them: `lite`, `full`, `ultra`, `wenyan-lite`, `wenyan-full`, `wenyan-ultra`, plus `off`. Every mode must be carried in the valid-modes whitelist, the statusline badge case list, hook examples, the bats suite, and docs — parity maintenance across all of these for three classical-Chinese modes that see little use.

**Decision:**

Drop the three `wenyan-*` modes from the kit. The upstream skill remains installed locally, so users who want wenyan can invoke it directly or re-enable the modes by hand. The kit focuses its example coverage on English compression (`lite`/`full`/`ultra`).

**Consequences:**

- Kit supports 4 modes: `lite`, `full`, `ultra`, `off`.
- Valid-modes list, statusline case list, examples, tests, and docs all shrink.
- New worked-example topics (debugging, auth, data structures) need 3 variants each instead of 6 — faster iteration on subagent style compliance.
- `/caveman wenyan-*` no longer works after kit install unless the user manually edits `~/.caveman-kit/hooks/caveman-config.js` (unsupported).
