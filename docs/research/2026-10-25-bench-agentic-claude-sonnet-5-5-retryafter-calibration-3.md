# Bench agentic: agentic-claude-sonnet-5-5-retryafter-calibration-3

Date: 2026-10-25

This note was written by hand. The maintainer declined the escalation to seeds 7-12, so the runner did not generate its summary note. Cells are in `bench/results/agentic-claude-sonnet-5-5-retryafter-calibration-3/` (18 cells, uncommitted).

## Run parameters

- Kind: agentic, fixture `retryafter` (second design, softened prompt: "It should wait the 1.5 seconds the upstream asked for, then retry ... Check both whether it retries and how long it waits.")
- Model: claude-sonnet-5-5
- Seeds: 6, three arms (`bare`, `full`, `full-diet`)
- Command used `--min-fixtures 1`

## Calibration result (issue #12, ADR 0012 decision 2, ADR 0015)

Target: `bare` passes roughly 50-80% of seeds. Result: `bare` passed 6 of 6, `full` 6 of 6, `full-diet` 6 of 6. The fixture is too easy with this prompt.

In every cell a test run executed (`tests_executed` 6/6 in each arm). In all 6 `bare` streams the agent opened `transport.py`. The prompt's last sentence names the length of the wait, so each agent checked it.

Across the three `retryafter` prompts the `bare` pass rate went from 12 of 12 (design 1) to 0 of 4 (design 2, prompt "honor that delay") to 6 of 6 (design 2, prompt with an explicit check of the wait). The prompt wording acts as a switch, not a dial. Follow-up: one wording between the last two, which asks for an end-to-end check without naming the wait (ADR 0015).
