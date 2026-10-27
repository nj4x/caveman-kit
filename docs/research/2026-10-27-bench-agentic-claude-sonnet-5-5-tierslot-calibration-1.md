# Bench agentic: agentic-claude-sonnet-5-5-tireslot-calibarion-1

Date: 2026-10-27

This note was written by hand from the cell files. The run id has two typos (`tireslot`, `calibarion`); the directory under `bench/results/` keeps it as typed. The run ended during the `bare` arm after seed 5, so the runner wrote no note. No `full` or `full-diet` cell exists, and the `bare` seed 6 cell is missing (only its warmup file exists).

## Run parameters

- Kind: agentic, fixture `tierslot` (ADR 0018), first version of the hidden test: five cases, including `test_locked_baseline_scopes_the_slot_by_the_lock`.
- Model: claude-sonnet-5-5
- Seeds planned: 6; seeds run: `bare` 1-5
- Warmup before each cell (ADR 0010): on
- Raw cells: `bench/results/agentic-claude-sonnet-5-5-tireslot-calibarion-1`
- Kit dir and commit: not recorded

## Result

`bare` passed 1 of 5 cells (seed 5). Failing tests per cell, from the stored output tail of each hidden-test run:

| seed | hidden test | failing cases |
| --- | --- | --- |
| 1 | fail | `alias_and_full_id_of_one_tier_share_the_slot`, `locked_baseline_scopes_the_slot_by_the_lock` |
| 2 | fail | `alias_and_full_id_of_one_tier_share_the_slot`, `locked_baseline_scopes_the_slot_by_the_lock` |
| 3 | fail | `locked_baseline_scopes_the_slot_by_the_lock` |
| 4 | fail | `locked_baseline_scopes_the_slot_by_the_lock` |
| 5 | pass | none |

Every failing agent fixed the opus symptom and passed the same-tier and higher-tier cases. The lock case failed in seeds 1 to 4. The prompt never names `lock_requested_model`, and the plant deletes the only text that says the slot follows the lock, so that case measured a missing requirement, not a missed behavior. The lock case was dropped (ADR 0018 decision 4), and calibration 2 ran against the four-case test.

## Diagnostics per arm

| arm | cells | hidden_pass | max_turns | ran_tests | tests_executed | subagent_start | read_chars | re_reads | turns | output |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| bare | 5 | 1/5 | 0 | 5/5 | 4/5 | 0/5 | 12904 | 0 | 86 | 17228 |
| full | 0 | 0/0 | 0 | n/a | n/a | n/a | 0 | 0 | 0 | 0 |
| full-diet | 0 | 0/0 | 0 | n/a | n/a | n/a | 0 | 0 | 0 | 0 |
