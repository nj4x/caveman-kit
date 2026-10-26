# Bench agentic: agentic-claude-sonnet-5-5-retryafter-calibration-4

Date: 2026-10-25

This note was written by hand. The maintainer stopped the run after 8 cells, so the runner did not generate its summary note. Cells are in `bench/results/agentic-claude-sonnet-5-5-retryafter-calibration-4/` (uncommitted).

## Run parameters

- Kind: agentic, fixture `retryafter`, prompt with the end-to-end sentence ("Check the fix end to end, not only in the function you change.").
- Model: claude-sonnet-5-5, 6 seeds planned, arms `bare`, `full`, `full-diet`
- Command used `--min-fixtures 1`

## Calibration result (issue #12, ADR 0012 decision 2, ADR 0015)

Target: `bare` passes roughly 50-80% of seeds. Result: `bare` passed 6 of 6. The fixture is too easy with this prompt. Partial: `full` 2 cells (both passed), `full-diet` not run.

The prediction in the previous turn was wrong: the end-to-end wording was expected to land below the target, and it did not. Across the four `retryafter` prompts the `bare` pass rate was 12/12, 0/4, 6/6 (named wait) and 6/6 (end-to-end). The fixture is not calibrated, and this design is not recommended for further paid runs.

Follow-up: the gate-rule issue (see issue #12 and the critic review of the guardrail rule in `bench/lib/stats.js`).
