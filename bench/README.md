# bench — live benchmark harness (maintainer-only)

Runs the kit's real hooks against a headless `claude` in isolated config
directories and records billed tokens per arm (ADR 0008). `install.sh` and
`update.sh` never copy this directory, and CI never runs it. **Every run
spends real API quota.**

## Usage

```bash
node bench/run.js --kind single-turn            # asks for confirmation on a TTY
node bench/run.js --kind single-turn --yes      # unattended
```

| Flag | Default | Meaning |
|------|---------|---------|
| `--kind single-turn\|agentic` | required | harness kind |
| `--seeds <n>` | `3` | repeats per arm × task (or fixture); never passed to `claude` |
| `--fixtures <a,b>` | all | agentic only: fixture names to run |
| `--fixtures-dir <dir>` | `bench/fixtures` | agentic only: dir holding `<name>/fixture.json` |
| `--model <id>` | `claude-sonnet-5-5` | passed to `claude --model` |
| `--kit-dir <path>` | repo root | kit checkout whose `hooks/` are measured |
| `--run-id <id>` | `<kind>-<model>-<kit-dir HEAD short SHA>` | results subdirectory |
| `--results-dir <dir>` | `bench/results` | parent of run directories |
| `--yes` | off | start without asking; required when there is no TTY |

Single-turn arms: `bare`, `bare-control`, `lite`, `full`, `ultra`, over the six
prompts in `tasks/single-turn.js`. The bare arms register the same hooks with
the flag seeded to `off` and `CAVEMAN_DEFAULT_MODE=off`.

## Agentic kind

`node bench/run.js --kind agentic --kit-dir <context-diet checkout>` runs arms
`bare`, `full` (`CAVEMAN_CONTEXT_DIET=0`) and `full-diet` (variable unset)
against fixture repos (needs `git`, `python3` and `pytest` or `uv` on the
machine; a run is budgeted at ~300k input + ~12k output tokens, see
`lib/estimate.js`). Per cell: clone at the pinned SHA, drop the clone's
history, apply the plant patch, record the tree as one root commit, run `claude -p ... --output-format stream-json --verbose
--permission-mode bypassPermissions --max-turns 40` in the clone (only the
throwaway work dir is writable by intent, but the permission bypass is real:
the agent could read or edit files elsewhere, including `hidden/` and the
hooks, by absolute path),
and only after it exits copy the hidden test in and run it. Each cell file
records `hiddenTest.pass` and `diagnostics` (`readChars`, `reReads`, `turns`,
`outputTokens`); the raw stream sits beside it as `<cell>.stream.jsonl`.
`ANTHROPIC_API_KEY` is redacted from the stream, `result`, `hiddenTest.tail`
and printed `FAIL` lines. The gate is not computed here.

**Turn cap.** Each agent run is capped at 40 turns (`MAX_TURNS` in
`lib/agentic.js`); this cap is a harness choice, not in ADR 0008. The CLI exits
non-zero when the cap stops a run. When the final result event has subtype
`error_max_turns` and carries `usage`, the harness still counts the run as a
completed cell: the hidden test runs and the record has `hitMaxTurns: true`
(otherwise `false`). A capped run usually leaves a half-edited tree, so its
hidden test tends to fail; the agentic gate should read `hitMaxTurns` and report
capped cells per arm. Any other non-zero exit, error result or signal fails the
cell: no file is written and a rerun retries it.

Fixture format (`bench/fixtures/<name>/`; the real fixtures arrive with a later
ticket, so until then the default dir is empty and the run stops with "no
fixtures found" — point `--fixtures-dir` at your own fixtures): `fixture.json` (`source`, `sha`,
`testCommand`, optional `plantPatch`/`prompt` file names), `plant.patch`,
`prompt.md`, `hidden/` (copied over the repo root after the run). Before any
paid call each fixture's hidden test must pass twice on the unpatched tree and
fail twice on the planted tree (run with `UV_OFFLINE=1`, `PIP_NO_INDEX=1`);
otherwise the fixture is dropped and printed as `DROPPED fixture ...`.
Preflight needs `<kit-dir>/hooks/caveman-context-diet.md`: its text (HTML
comments stripped) must appear in the `full-diet` context and not in `full`.

## Resuming

Each successful call writes one file, `<results-dir>/<run-id>/<arm>--<task>--s<seed>.json`.
A rerun with the same run id skips cells that already have a file and retries
failed ones. The default run id depends only on the kit-dir's HEAD commit, so
uncommitted hook edits reuse the old id: pass `--run-id` to keep them apart.

## Isolation and auth

Each call gets a fresh temp config dir (`0700`, removed on exit, error and
SIGINT/SIGTERM/SIGHUP) holding only the kit's three hooks, the seeded flag, a copy of
the caveman `SKILL.md`, and auth. Your own `CLAUDE.md`, settings, plugins and
hooks are never used, and single-turn `claude` calls run in an empty temp
working directory (agentic calls run in a fixture clone, see above).

- Auth: `ANTHROPIC_API_KEY` from the environment; otherwise a readable
  `<config dir>/.credentials.json` is copied in; otherwise the run stops.
- Skill: `CAVEMAN_BENCH_SKILL_ROOT`, else the kit manifest's `pluginRoot`,
  else `~/.claude` — whichever first contains `skills/caveman/SKILL.md`.

Before any paid call the runner executes each arm's SessionStart hook once
(preflight; a mode arm with empty context aborts) and prints a rough cost
estimate (constants in `lib/estimate.js`).

## Tests

```bash
bats bench/tests/
```

Tests put a stub `claude` (`tests/stub/claude`) first on `PATH`; they never
call the API. `bats tests/` does not pick them up.
