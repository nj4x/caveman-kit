# Bench agentic: agentic-claude-sonnet-5-5-retryafter-calibration-7

Date: 2026-10-26

This note was written by hand. The maintainer declined the escalation to seeds 7-12 after the first 18 cells, so the runner did not generate its summary note. Cells are in `bench/results/agentic-claude-sonnet-5-5-retryafter-calibration-7/` (uncommitted).

## Run parameters

- Kind: agentic, fixture `retryafter`, prompt with the end-to-end sentence (as in calibration 4 and 6).
- Model: claude-sonnet-5-5, 6 seeds, arms `bare`, `full`, `full-diet`; `--min-fixtures 1`, so no gate verdict is valid.
- Plant: the 429 inversion in `http_util.should_retry`, and `http_util.retry_delay` capping the upstream delay at the exponential backoff (`min(delay, RETRY_BASE_DELAY * (2 ** attempt))`). `transport.py` is untouched.

## Calibration result (issue #12, ADR 0012 decision 2, ADR 0015)

Target: `bare` passes roughly 50-80% of seeds. Result: `bare` passed 6 of 6; `full` and `full-diet` also passed 6 of 6. The fixture, with this plant, does not meet the target.

What the streams show: all six `bare` agents read `http_util.py` lines 85-200 in one `sed`, which holds `retry_delay` (about line 160) and `should_retry` (about line 170) ten lines apart. All six rewrote the cap to `min(delay, RETRY_MAX_DELAY)`. s4 named both bugs in its first message after that read ("`retry_delay` clamps upstream guidance to the backoff (1s at attempt 0), so 1.5s would become 1.0s"). Three agents (s2, s3, s5) also wrote a script against a local stub upstream and measured the wait; s1 called `should_retry` and `retry_delay` directly.

Lesson across calibrations 1, 4, 6 and 7: an agent reads about 100 lines around every hit for the symptom keywords (`retry-after`, `429`) and then the call site of the function it fixed. A second bug anywhere in that reach is found, whether the line is a wrong expression (calibration 6) or a plausible-looking cap (this run). Only calibration 2, whose prompt had no end-to-end sentence, left the second bug alone, and then `bare` passed 0 of 4.
