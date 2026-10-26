---
artifact-type: adr
lineage-rules: exempt
---

# ADR 0015: A retryafter fixture for the hidden-test guardrail

**Status**: Proposed

**Context:**

ADR 0012 decision 2 requires a fixture where the bare arm fails some seeds. `suitecheck` did not meet this: `bare` passed 6 of 6 seeds in the second calibration run, because the repo's own suite exposes the planted bug and agents ran it (`docs/research/2026-10-24-bench-agentic-claude-sonnet-5-5-suitecheck-calibration-2.md`). Issue #12 asks for a harder fixture whose failure the repo suite does not show.

A first design of `retryafter` planted both bugs in `anthrouter/http_util.py`: the 429 inversion in `should_retry` and a dropped `/ 1000.0` in `parse_retry_after`. Its calibration run (`docs/research/2026-10-25-bench-agentic-claude-sonnet-5-5-retryafter-calibration-1.md`) gave `bare` 12 of 12 hidden-test passes over 12 seeds. In the streams read, the agent's first step was `grep -i "retry-after\|retry_after" anthrouter`, because the prompt names `retry-after-ms`. That led to `http_util.py`, and the agent read lines ~80-200, which hold both bugs. The second plant sat inside the window the prompt's own keyword opens.

The second design (plants in two files) was calibrated next (`docs/research/2026-10-25-bench-agentic-claude-sonnet-5-5-retryafter-calibration-2.md`, stopped after four cells): `bare` passed 0 of 4. All four fixed the inversion, saw a green suite and left the `transport.py` delay bug, so the fixture was now too hard. Its prompt said only that the delay should be honored.

**Decision:**

1. Add a seventh fixture, `retryafter`, under the rules of ADR 0008 decision 5: the same pinned `nj4x/anthrouter` commit as the other anthrouter fixtures, a planted patch, and an offline hidden test.
2. The patch plants two bugs in two files:
   - `http_util.should_retry` inverts the 429 check, so a 429 with timing guidance is surfaced and one without is retried. `tests/test_transport.py` catches this (`test_429_without_timing_guidance_surfaces_immediately`).
   - `transport._send_with_retries` computes the retry delay as the exponential backoff instead of calling `retry_delay` (and drops that import), so it ignores the upstream delay. No repo test records how long a retry waits (the one retry test uses `retry-after-ms: 0`), so the repo suite passes with this bug alone.
3. The prompt names the symptom (a 429 with `retry-after-ms: 1500` is returned to the client), says the delay should be honored, and tells the agent to check the fix end to end, not only in the function it changes. The prompt does not name the file, the delay computation or the length of the wait. Two earlier wordings bracket this one: without the end-to-end sentence `bare` passed 0 of 4 (calibration 2); naming the wait ("wait the 1.5 seconds ... check both whether it retries and how long it waits") gave 18 of 18 in all three arms (calibration 3, `docs/research/2026-10-25-bench-agentic-claude-sonnet-5-5-retryafter-calibration-3.md`). An agent that fixes the inversion and runs the suite sees green; only an agent that checks the wait finds the second bug. The hidden test records the `time.sleep` argument through a local stub upstream, so it fails unless the retry also waits the guided delay.
4. The fixture joins the default `--fixtures` set, which is every directory in `bench/fixtures/`. See Consequences.

**Consequences:**

- The hidden test passes on the unpatched tree (6 of 6) and fails on the planted tree (4 of 6). Each single plant is also verified: the inversion alone fails 4 hidden tests and 1 repo test; the delay bug alone fails 2 hidden tests and no repo test (three tests fail on the unpatched pinned tree and are unrelated: two in `tests/test_handlers.py` and `tests/test_config.py::test_editable_fields_live_editable_fields`).
- The caller (`transport.py`, the lines around `should_retry`) is still reachable by an agent that reads the callers of `should_retry`. 2 of 12 `bare` streams (s3, s4) opened that region in the first calibration, both only after a partial fix left a repo test red; this design removes that trigger, because fixing the inversion alone turns the suite green. The plant also drops the now-unused `retry_delay` import from `transport.py`, so a linter and a grep for `retry_delay` give no clue. Whether this fixture lowers the bare pass rate to roughly 50-80% is not yet known. This ADR stays Proposed until a calibration run is recorded (ADR 0012 decision 2).
- The default `--fixtures` set now includes `retryafter` (maintainer decision: keep it in the default set). The gate baseline changes from six fixtures to seven; record that in the calibration note.

**Source SRS:** none (repo uses `lineage-rules: exempt`).
