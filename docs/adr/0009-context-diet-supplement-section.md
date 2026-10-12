---
artifact-type: adr
lineage-rules: exempt
---

# ADR 0009: Context Diet as a kit-authored supplement, gated by benchmark

**Status**: Approved

Ships only after the gate in ADR 0008 passes.

**Context:**

Tool output is re-sent on every later request, and the largest part of it is whole-file `Read` results. No hook may compress `Read` output without breaking later edits, so the only lever is what the model reads. Chisle's ruleset has a "Context Diet" section for this (`Chisle:skills/chisle/SKILL.md:57-59`). Chisle's own data shows that rule text can backfire, so Context Diet has to be measured before it ships.

**Decision:**

1. Write the rules as a kit-authored file, `hooks/caveman-context-diet.md`, in caveman's voice. It credits Chisle in a comment. It is not a verbatim copy. Target: under 500 characters. Rules: grep for the symbol first, then `Read` with `offset`/`limit`. Narrow at the source (`ls dir`, `tail`, `head`). Builds and tests report failures and summary only. Never re-read an unchanged file. Before an edit, read every line the edit touches plus enough surrounding context to place it; a targeted `offset`/`limit` read that covers this is enough.
2. `caveman-activate.js` appends this file to the injected text, next to `caveman-examples.md`, on both SessionStart and SubagentStart. It applies to every mode except `off`. The text is the same in all modes. It is not filtered per mode.
3. Opt-out: environment variable `CAVEMAN_CONTEXT_DIET=0` disables the section. It is read at runtime only. There is no install-time flag, no backup, and no uninstall path. Same pattern as `CAVEMAN_DEFAULT_MODE`.
4. Missing file means no section, never a failure. The hook still exits 0.
5. The file is injected by `caveman-activate.js` only. The patch scripts and manifest are unchanged.

**Consequences:**

- Every SessionStart and SubagentStart adds roughly 300–500 characters, even when the section does nothing useful. This cost is why the gate exists.
- The section gates on ADR 0008 Decision 8, agentic harness. The 95% confidence interval of the paired difference (`full` + Context Diet minus `full`, paired by fixture and seed) in cache-weighted input cost must exclude zero in the good direction. The agentic hidden-test pass rate must not drop. Otherwise the file is not shipped.
- The `full` arm runs the same hooks with `CAVEMAN_CONTEXT_DIET=0`, the user-facing opt-out from Decision 3. No benchmark-only switch is added.
- The benchmark must measure the file actually injected by the hook, not a copy of it.
- Until the gate passes, `hooks/caveman-context-diet.md` and the `caveman-activate.js` change live only on a feature branch, at their final paths. The harness runs against that branch checkout. They merge to `master` only after the gate passes and its result note is committed. If the gate fails, the branch is not merged.
- The section does not change the caveman boundary rule that code is written normally.

**Source SRS:** none (repo uses `lineage-rules: exempt`).
