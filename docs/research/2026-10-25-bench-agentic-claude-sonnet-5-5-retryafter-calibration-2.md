# Bench agentic: agentic-claude-sonnet-5-5-retryafter-calibration-2

Date: 2026-10-25

This note was written by hand. The run was stopped by the maintainer after four `bare` cells, so the runner did not generate its summary note. Cells are in `bench/results/agentic-claude-sonnet-5-5-retryafter-calibration-2/` (`bare--retryafter--s1` to `s4`, uncommitted).

## Run parameters

- Kind: agentic, fixture `retryafter` (second design: plants in `http_util.should_retry` and `transport._send_with_retries`, ADR 0015)
- Model: claude-sonnet-5-5
- Seeds planned: 6 (stopped after 4 `bare` cells; no `full` or `full-diet` cell ran)
- Command used `--min-fixtures 1 --yes`

## Calibration result (issue #12, ADR 0012 decision 2, ADR 0015)

Target: `bare` passes roughly 50-80% of seeds. Result: `bare` passed 0 of 4. The fixture is now too hard, where the first design was too easy (`...retryafter-calibration-1`).

All four cells failed the same two hidden tests, `test_429_with_retry_after_ms_waits_that_long_then_retries` and `test_429_with_retry_after_seconds_waits_that_long_then_retries`; the other four hidden tests passed. So every agent fixed the `should_retry` inversion, saw the repo suite go green, and left the `transport.py` delay bug in place, which is the trap as designed. The hidden test is not at fault: it fails only on the two delay assertions, and a critic review before the run found no correct alternative fix that it rejects once its `should_retry` assertions were loosened. Each cell recorded 4-5 test-runner calls, of which 1-2 were executed runs (`tests_executed`).

The run was stopped because a 0 of 6 result would not change the conclusion, and `--yes` would have escalated to 12 seeds (about $21 more).

Follow-up: soften the prompt so it points at the length of the wait, as well as the retry decision (ADR 0015).
