# Bench agentic: agentic-claude-sonnet-5-5-adminalias-calibration-1

Date: 2026-10-26

This note was written by hand. The maintainer declined the escalation to seeds 7-12 after the first 18 cells, so the runner did not generate its summary note. Cells are in `bench/results/agentic-claude-sonnet-5-5-adminalias-calibration-1/` (uncommitted).

## Run parameters

- Kind: agentic, fixture `adminalias` (ADR 0017), first prompt: the symptom only (a malformed `model_aliases` in `POST /admin/config` gets no response; it should answer 400).
- Model: claude-sonnet-5-5, 6 seeds, arms `bare`, `full`, `full-diet`; `--min-fixtures 1`, so no gate verdict is valid.

## Calibration result (issue #12, ADR 0012 decision 2, ADR 0017)

Target: `bare` passes roughly 50-80% of seeds. Result: `bare` passed 6 of 6; `full` and `full-diet` also passed 6 of 6. The fixture, with this prompt, does not meet the target.

What the streams show: all six `bare` agents grepped `model_aliases`, then read the admin block of `handle_post_config` and `_parse_model_aliases_str` in one call, and rewrote only the dict-field parsing block in `anthrouter/admin.py`. No agent edited `config.py`. The tempting edit (make the shared parsers raise) never came up, because the symptom pointed at the admin call site and the fix there is the natural one. Each agent ran the full suite and confirmed the pre-existing failures against a stash.

Next prompt (ADR 0017 decision 3): a bug report whose reporter blames the parser's `p.error()` exit, with no instruction to check other callers.
