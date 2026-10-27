---
artifact-type: adr
lineage-rules: exempt
---

# ADR 0017: An adminalias fixture whose tempting fix breaks a second caller

**Status**: Accepted as a fixture outside the default set; the calibration target (ADR 0012 decision 2) is not met. See Outcome.

**Context:**

ADR 0012 decision 2 requires a fixture where the bare arm fails some seeds, so that the hidden-test guardrail can detect a drop. Four designs of `retryafter` (ADR 0015, calibrations 1, 4, 6 and 7) did not reach it: `bare` passed 6 of 6 or 12 of 12 each time, except the one design whose prompt had no end-to-end sentence (0 of 4). The streams show why. An agent reads about 100 lines around every hit for the symptom keywords and then the call site of the function it fixed, so a second bug within that reach is found whether it is a wrong expression or a plausible-looking cap (`docs/research/2026-10-26-bench-agentic-claude-sonnet-5-5-retryafter-calibration-7.md`).

A different failure was tried. `config._parse_model_aliases_str` and `_parse_classification_str` report bad input through `p.error()`, which exits with `SystemExit(2)`. That is right for the command line (`config.parse_args`). `admin.handle_post_config` called both parsers with a throwaway `ArgumentParser`, so a malformed value in a POST body raised `SystemExit` inside the request thread. The bug is live at the pinned commit. The design aimed the tempting fix at the shared helper: make the parsers raise `ValueError`, which fixes the admin path and breaks the command line.

**Decision:**

1. Add an eighth fixture, `adminalias`, under the rules of ADR 0008 decision 5: the same pinned `nj4x/anthrouter` commit, a patch, and an offline hidden test.
2. The bug is live at the pin, so the unpatched tree (the one the hidden test must pass on) needs the fix. The loader gains an optional `base.patch`, applied to both the unpatched and the planted tree before `plant.patch`. For `adminalias`:
   - `base.patch` moves the dict-valued options into a `_DICT_OPTIONS` registry in `config.py`, with `parse_args` calling each `_parse_<kind>_str`. The parsers raise `ValueError`; `parse_args` converts it back to `p.error()`. `admin.handle_post_config` catches `ValueError` and returns 400.
   - `plant.patch` reverts `admin.py` to the pinned code and deletes `test_classification_unknown_label_rejected`, the one visible test that pins the parser exit. Without that deletion, an agent that changes both parsers sees a red test and corrects itself.
3. The prompt reads as a bug report whose reporter has traced the hang into the shared parser: `POST /admin/config` gets no response, the request dies inside `_parse_model_aliases_str` because it calls `p.error()`, a config parser should report bad input as an error its caller can turn into a message, and the endpoint should answer 400. It does not name `parse_args` or the command line, and it has no instruction to check other callers or to test end to end (that sentence decided `retryafter`, ADR 0015).
4. The hidden test checks both callers: the admin POST answers 400 for four malformed aliases and three malformed classification values and does not apply the config; a well-formed POST answers 200; `parse_args` exits with code 2 and names the option in the usage message for the same values. Any fix that keeps both behaviors passes.
5. `adminalias` is outside the default `--fixtures` set: its `fixture.json` sets `"inDefaultSet": false`, and `bench/run.js` uses `fixtures.defaultFixtureNames`. It runs when named with `--fixtures adminalias`. This supersedes the earlier plan to include it in the default set.

**Consequences:**

- Checked on the pinned clone with the registry `base.patch`: the hidden test passes 15 of 15 on the unpatched tree and fails 7 of 15 on the planted tree. The wrong fix (parsers raise `ValueError`, admin catches it, `parse_args` untouched) fails 7 of 15 hidden tests, all on the command line. A fix that changes only the admin block (`plant.patch` reversed) passes 15 of 15. The visible suite is at 165 passed and 1 failed in every variant; that one failure, `test_editable_fields_live_editable_fields`, also fails on the unpatched pinned tree.
- The patches were built by hand against the pin. If the pin moves, `base.patch` and `plant.patch` must be regenerated.
- The fixture measures whether the agent checks the other callers of the helper it is tempted to change. It does not measure whether the agent finds a second bug.

**Source SRS:** none (repo uses `lineage-rules: exempt`).

## Outcome

Calibration 1 (symptom-only prompt, `docs/research/2026-10-26-bench-agentic-claude-sonnet-5-5-adminalias-calibration-1.md`) gave `bare` 6 of 6. Every agent edited only the admin block, so the tempting edit never came up.

Calibration 2 (the bug-report prompt above, `docs/research/2026-10-27-bench-agentic-claude-sonnet-5-5-adminalias-calibration-2.md`) also gave `bare` 6 of 6. All six agents edited both parsers and the `parse_args` call site, so they checked the command line too.

A pilot of four subagents on the registry design (run outside the bench, with the same task prompt) passed the hidden test 4 of 4. The registry design gives the agent a second caller to find, and it found it every time. The target is not met, and no further design was tried. The fixture is kept in `bench/fixtures/` and out of the default set.
