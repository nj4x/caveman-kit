---
artifact-type: adr
lineage-rules: exempt
---

# ADR 0015: A retryafter fixture for the hidden-test guardrail

**Status**: Accepted as a fixture outside the default set; the calibration target (ADR 0012 decision 2) is not met. See Outcome.

**Context:**

ADR 0012 decision 2 requires a fixture where the bare arm fails some seeds. `suitecheck` did not meet this: `bare` passed 6 of 6 seeds in the second calibration run, because the repo's own suite exposes the planted bug and agents ran it (`docs/research/2026-10-24-bench-agentic-claude-sonnet-5-5-suitecheck-calibration-2.md`). Issue #12 asks for a harder fixture whose failure the repo suite does not show.

A first design of `retryafter` planted both bugs in `anthrouter/http_util.py`: the 429 inversion in `should_retry` and a dropped `/ 1000.0` in `parse_retry_after`. Its calibration run (`docs/research/2026-10-25-bench-agentic-claude-sonnet-5-5-retryafter-calibration-1.md`) gave `bare` 12 of 12 hidden-test passes over 12 seeds. In the streams read, the agent's first step was `grep -i "retry-after\|retry_after" anthrouter`, because the prompt names `retry-after-ms`. That led to `http_util.py`, and the agent read lines ~80-200, which hold both bugs. The second plant sat inside the window the prompt's own keyword opens.

The second design (plants in two files) was calibrated next (`docs/research/2026-10-25-bench-agentic-claude-sonnet-5-5-retryafter-calibration-2.md`, stopped after four cells): `bare` passed 0 of 4. All four fixed the inversion, saw a green suite and left the `transport.py` delay bug, so the fixture was now too hard. Its prompt said only that the delay should be honored.

With the end-to-end sentence added to the prompt (decision 3), the fourth calibration (`docs/research/2026-10-25-bench-agentic-claude-sonnet-5-5-retryafter-calibration-4.md`, stopped after 8 cells) gave `bare` 6 of 6. A fifth run (`calibration-5`, stopped after 7 cells, not recorded as a note) ran from the main checkout and so used the old plant, not the one this ADR describes; its `bare` result was again 6 of 6. A plant that drops the `retry_delay` import and definition (`calibration-6`, `docs/research/2026-10-26-bench-agentic-claude-sonnet-5-5-retryafter-calibration-6.md`) also gave `bare` 6 of 6. In all six streams of that run the agent fixed the inversion, then opened the retry block in `transport.py` (the `should_retry` call site, found by grepping `should_retry` or `parse_retry_after`) and rewrote the one line that computed the delay from the exponential backoff. The end-to-end sentence sends the agent to the call site, and a wrong delay computation next to the call is visible on reading it. Removing the helper did not hide it.

The seventh calibration (`docs/research/2026-10-26-bench-agentic-claude-sonnet-5-5-retryafter-calibration-7.md`, 18 cells, escalation declined) moved the bug into `retry_delay` as a cap on the guided delay, so the call site read correctly: `bare` passed 6 of 6 again. All six agents had read `http_util.py` lines 85-200, which holds `retry_delay` and `should_retry` ten lines apart, in one `sed`. A second bug within the reach of the keyword greps is found; the `retryafter` family (calibrations 1, 4, 6, 7) does not reach the target. Calibration 2 shows the other extreme.

**Decision:**

1. Add a seventh fixture, `retryafter`, under the rules of ADR 0008 decision 5: the same pinned `nj4x/anthrouter` commit as the other anthrouter fixtures, a planted patch, and an offline hidden test.
2. The patch plants two bugs, in the Decision 2 wording of the first design. The final plant (calibrations 6 and 7) touches only `anthrouter/http_util.py`, as Consequences explain. Original wording, superseded:
   - `http_util.should_retry` inverts the 429 check, so a 429 with timing guidance is surfaced and one without is retried. `tests/test_transport.py` catches this (`test_429_without_timing_guidance_surfaces_immediately`).
   - `http_util.retry_delay`, which `transport._send_with_retries` calls correctly, caps the upstream delay at the exponential backoff (`min(delay, RETRY_BASE_DELAY * 2 ** attempt)`), so a `retry-after-ms: 1500` waits 1.0 s on the first retry. The call site reads correctly and the helper reads plausibly: the docstring says "upstream guidance, else backoff". No repo test records how long a retry waits (the one retry test uses `retry-after-ms: 0`, and `min(0, ...)` is 0), so the repo suite passes with this bug alone.
3. The prompt names the symptom (a 429 with `retry-after-ms: 1500` is returned to the client), says the delay should be honored, and tells the agent to check the fix end to end, not only in the function it changes. The prompt does not name the file, the delay computation or the length of the wait. Two earlier wordings bracket this one: without the end-to-end sentence `bare` passed 0 of 4 (calibration 2); naming the wait ("wait the 1.5 seconds ... check both whether it retries and how long it waits") gave 18 of 18 in all three arms (calibration 3, `docs/research/2026-10-25-bench-agentic-claude-sonnet-5-5-retryafter-calibration-3.md`). An agent that fixes the inversion and runs the suite sees green; only an agent that checks the wait finds the second bug. The hidden test records the `time.sleep` argument through a local stub upstream, so it fails unless the retry also waits the guided delay.
4. The fixture joins the default `--fixtures` set, which is every directory in `bench/fixtures/`. See Consequences.

**Consequences:**

- The hidden test passes on the unpatched tree (6 of 6) and fails on the planted tree (4 of 6). With the inversion fixed and the cap left in place, the hidden test fails 2 of 6 (the two sleep assertions) and `tests/test_transport.py` passes in full, so the repo suite does not show the remaining bug. Three tests fail on the unpatched pinned tree and are unrelated: two in `tests/test_handlers.py` and `tests/test_config.py::test_editable_fields_live_editable_fields`.
- The plant touches only `http_util.py`. The cap sits in a helper the agent reaches by one more hop from the call site; the agent finds it by reading `retry_delay` and judging the `min(...)` wrong, or by running a retry and measuring the wait (one `bare` agent in calibration 6 wrote such a script). Calibration 7 measured this plant: `bare` passed 6 of 6, so the target is not met and the fixture needs a different design before it is useful for the guardrail. Calibration runs 1 to 6 used the earlier plants and prompts described in Context; their cells are not comparable with run 7.
- (Superseded by the Outcome section: `retryafter` is outside the default `--fixtures` set.) The original plan included `retryafter` in the default set and moved the gate baseline from six fixtures to seven.

**Source SRS:** none (repo uses `lineage-rules: exempt`).

## Outcome

Calibrations 6 and 7 (the `retry_delay` cap plant, with the end-to-end prompt) gave `bare` 6 of 6, so the target is not met. Consequence 4 (the default set includes `retryafter`) is superseded: the fixture has `"inDefaultSet": false` in `fixture.json` and runs only when named with `--fixtures retryafter`. See ADR 0017 and ADR 0012 Outcome.
