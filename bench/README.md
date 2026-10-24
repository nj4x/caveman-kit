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
| `--research-dir <dir>` | `docs/research` | where the summary note is written |
| `--cell-timeout <s>` | `600` (agentic: `1800`) | seconds before one `claude` call is stopped (SIGTERM, SIGKILL 5 s later) and the cell fails |
| `--yes` | off | start without asking; required when there is no TTY |

Single-turn arms: `bare`, `bare-control`, `lite`, `full`, `ultra`,
`ultra-no-focus`, over the six prompts in `tasks/single-turn.js`. The bare
arms register the same hooks with the flag seeded to `off` and
`CAVEMAN_DEFAULT_MODE=off`.

`ultra-no-focus` measures the focus directive in the per-turn reminder
(commit `e11e665`). The runner copies `--kit-dir`'s `hooks/` into the temp
dir and removes the focus clause (the text after `— session ruleset applies.`)
from the copied `caveman-mode-tracker.js`; the arm runs that copy with the flag
seeded to `ultra`. The shipped hooks are only read. If the clause is not found,
the run exits non-zero before the cost estimate and before any `claude` call
(`lib/nofocus.js`).

## Agentic kind

`node bench/run.js --kind agentic --kit-dir <context-diet checkout>` runs arms
`bare`, `full` (`CAVEMAN_CONTEXT_DIET=0`) and `full-diet` (variable unset)
against fixture repos (needs `git`, `python3` and `pytest` or `uv` on the
machine; a run is budgeted at ~300k input + ~12k output tokens, see
`lib/estimate.js`). Per cell: clone at the pinned SHA, drop the clone's
history, apply the plant patch, record the tree as one root commit, run
`claude -p ... --output-format stream-json --verbose --permission-mode
bypassPermissions --max-turns 40` in the clone (only the throwaway work dir is
writable by intent, but the permission bypass is real: the agent could read or
edit files elsewhere, including `hidden/` and the hooks, by absolute path), and
only after it exits copy the hidden test in and run it. Cells use the same
format as single-turn cells (`kind: "agentic"`, `model`, `usage`; a cell from
another model or kind is stale and rerun). Each agentic cell also records
`hiddenTest.pass`, `hitMaxTurns` and `diagnostics` (`readChars`, `reReads`, `turns`,
`outputTokens`); the raw stream sits beside it as `<cell>.stream.jsonl`.
`ANTHROPIC_API_KEY` is redacted from the stream, `result`, `hiddenTest.tail`
and printed `FAIL` lines. Keys under 20 characters are not redacted, because
they match ordinary text; the run prints a warning at start. The agentic gate is described under "Agentic gate".

**Turn cap.** Each agent run is capped at 40 turns (`MAX_TURNS` in
`lib/agentic.js`); this cap is a harness choice, not in ADR 0008. The `claude` CLI
(not `bench/run.js`) exits non-zero when the cap stops a run. When the final result event has subtype
`error_max_turns` and carries `usage`, the harness still counts the run as a
completed cell: the hidden test runs and the record has `hitMaxTurns: true`
(otherwise `false`). A capped run usually leaves a half-edited tree, so its
hidden test tends to fail; the agentic gate reads `hitMaxTurns` and reports
capped cells per arm. Any other non-zero exit, error result or signal fails the
cell: no file is written and a rerun retries it.

Fixture format (`bench/fixtures/<name>/`, or the dir `--fixtures-dir` names):
`fixture.json` (`source`, `sha`, `testCommand`, optional `plantPatch`/`prompt`
file names), `plant.patch`, `prompt.md`, `hidden/` (copied over the repo root
after the run). Before any paid call each fixture's hidden test must pass twice
on the unpatched tree and fail twice on the planted tree (run with
`UV_OFFLINE=1`, `PIP_NO_INDEX=1`); otherwise the fixture is dropped and printed
as `DROPPED fixture ...`.
Preflight needs `<kit-dir>/hooks/caveman-context-diet.md`: its text (HTML
comments stripped) must appear in the `full-diet` context and not in `full`.

### Fixtures

Four real fixtures ship in `bench/fixtures/` (ADR 0008 decision 5). Each pins
one upstream commit, and the run clones it from GitHub:

| Fixture | Source repo | Pinned SHA | Planted bug / task |
|---------|-------------|------------|--------------------|
| `bigfile` | `nj4x/anthrouter` | `8a94cf6f6134bc61c02f350baf257e1127443843` | off-by-one in `parse_classifier_score` inside the 2,100-line `anthrouter/model_router.py`: a score of 100 is rejected |
| `rootcause` | `nj4x/anthrouter` | `8a94cf6f6134bc61c02f350baf257e1127443843` | `request_text.strip_reminders` stops trimming whitespace; the prompt names one symptom, the hidden test checks the helper and three call sites |
| `noisylog` | `nj4x/anthrouter` | `8a94cf6f6134bc61c02f350baf257e1127443843` | misspelt rate-limit header in `http_util`; the prompt sends the agent through the full suite (1,100+ tests, a few minutes, some unrelated failures) |
| `reuse` | `nj4x/skills-dev` | `41193d1541fe3af0f821869c326870d97f75e008` | the `flagged` subcommand of `skills/planning/critic/scripts/critic_ledger.py` is removed; the existing `_load_json` helper already does the fence-tolerant loading it needs |

`noisylog` uses anthrouter because its test suite is the longer one that runs
offline: at the pinned commits anthrouter's suite ran 1,125 passing tests in
about 130 s, and skills-dev's (`mcp/mcp-vectors`) ran 599 in about 35 s.

Each `testCommand` runs one pytest file from `hidden/`: with `python3 -m pytest`
when `python3` can import `pytest`, otherwise with
`uv run --no-project --with pytest`. The hidden tests use only the standard
library and the repo's own code. Because tests run with `UV_OFFLINE=1`, the uv
branch needs `pytest` already in the uv cache: run any `uv run --with pytest`
once online, or install `pytest` for `python3`.

To move a pin, set the new `sha` in each affected `fixture.json`, regenerate
`plant.patch` against that commit if it no longer applies, and rerun the live
check:

```bash
BENCH_LIVE_FIXTURES=1 bats -f real-fixtures-live bench/tests/fixtures.bats
```

It clones each pinned commit (network, no API quota) and runs the offline
reliability check above. A fixture it drops must be fixed before a paid run.

### Measuring the Context Diet branch

The agentic gate measures the hooks of the checkout `--kit-dir` names, so point
it at a worktree of the `context-diet` branch and run from this checkout:

```bash
git worktree add ../caveman-kit-context-diet context-diet
node bench/run.js --kind agentic --kit-dir ../caveman-kit-context-diet
git worktree remove ../caveman-kit-context-diet   # when done
```

The run id carries that worktree's HEAD short SHA, so a run on a new
`context-diet` commit starts fresh cells. Agentic gate (spec #1): the paired
difference `full-diet` minus `full` by fixture and seed passes when the 95%
interval of cache-weighted input cost lies below zero and the `full-diet`
hidden-test pass rate is not lower than `full`'s. An interval that includes
zero after 3 seeds earns one rerun with up to 6 seeds, then `no-ship`. Fewer
than 3 fixtures left after drops is `inconclusive`; `bare` is reference only.
The runner does not compute this gate or escalate seeds by itself: read the
paired cells yourself, and to escalate rerun with `--seeds 6` and the same
`--run-id` (cells for seeds 1-3 are reused).

## Cost

Every run spends real quota; the runner prints an estimate before the first
call. One full run is 108 single-turn calls (6 arms x 6 tasks x 3 seeds) and 36
agentic runs (3 arms x 4 fixtures x 3 seeds), 72 when the agentic gate
escalates to 6 seeds. At the `lib/estimate.js` assumptions and Sonnet list
price, that is at most about $10 for the single-turn kind (~$0.09 per call) and
about $39 to $78 for the agentic kind (~$1.08 per run). Prompt caching usually
makes the real bill lower. `--model claude-opus-5-5` costs about 1.7x as much.

## Requirements

- `node` and `git`
- `claude` on `PATH` (the runner calls it headless)
- agentic kind: `python3` 3.10 or newer (anthrouter requires it) plus
  `pytest`, or `uv` with `pytest` in its cache (see Fixtures)
- `bats` for the tests
- auth: `ANTHROPIC_API_KEY`, or a readable credentials file (see below)

## Resuming

Each successful call writes one file, `<results-dir>/<run-id>/<arm>--<task>--s<seed>.json`.
A rerun with the same run id skips cells that already have a file and retries
failed ones. A cell recorded with a different `--model` or `--kind` is stale:
it is rerun and overwritten, never reused. The default run id depends only on
the kit-dir's HEAD commit, so uncommitted hook edits reuse the old id: pass
`--run-id` to keep them apart. The summary note marks such a commit `-dirty`.

## Gate and report

After the calls the runner prints raw per-arm totals, then the gate table
(`lib/stats.js`). Two co-primary metrics, lower is better for both:
cache-weighted input cost (`input + 0.1 x cache read + 1.25 x cache write`
tokens) and billed output tokens. The 0.1x cache-read weight matches the CLI's
reported USD. Anthropic's pricing page lists 0.05x for Sonnet 5.5; the formula
is kept at 0.1x so results stay comparable with the 8c90768 and b56c077 runs
(see `docs/research/2026-10-23-context-diet-prompt-improvements.md`). Each candidate is paired with its reference
by task and seed: `lite`, `full`, `ultra` against `bare`, and
`ultra-no-focus` against `ultra`. Every candidate gets a row; one with fewer
than 2 pairs has an infinite interval and is no-ship. The table shows both
means, the mean paired difference and its 95% t-interval per metric, and the
verdict:

- `ship`: one interval excludes zero below and the other does not exclude
  zero above.
- `no-ship`: either interval excludes zero above, or both include zero.
- `inconclusive`: the noise baseline (`bare` against `bare-control`) excludes
  zero on either metric, or has fewer than 2 pairs, so every verdict in the
  run is void. Counts as no-ship.

Cells without a partner are left out of the intervals and listed under the
table. The single-turn harness never runs more than `--seeds` seeds.

When every planned cell exists, the runner writes
`<research-dir>/<YYYY-MM-DD>-bench-<run-id>.md` with the run parameters
(model, seeds, kit-dir commit), the gate table and the raw totals. Commit it
with the run's cells under `bench/results/<run-id>/`.

### Agentic gate

For `--kind agentic` the gate judges `full-diet` against `full` on
cache-weighted input cost (lower is better), with the hidden-test pass rate as
a guardrail (ADR 0008, ADR 0009). The `bare` arm is reported for reference and
feeds no verdict.

- Pairing: by fixture and seed. A pair counts only when both cells completed
  (usage and a hidden-test result). Unpaired cells (a failed cell, an
  incomplete cell file, or cells of a fixture dropped after some were paid for)
  are excluded and listed in the report. Pass rates use paired cells only, so
  both arms share a denominator.
- `ship`: the 95% t-interval of the paired cost difference excludes zero below
  and the `full-diet` pass rate is not lower than `full`'s.
- `no-ship` at once: the interval excludes zero above, or the pass rate is
  lower. No extra seeds are run.
- Escalation: if the interval includes zero after `--seeds` N seeds (default
  3), the runner prints a new estimate, asks again (unless `--yes`) and runs
  seeds N+1..2N, skipping cells that exist, then recomputes. If the interval
  still includes zero the verdict is `no-ship`. This happens at most once; a
  rerun with the same run id re-derives the same verdict without new calls.
  `--no-escalate` skips it. Failed cells block escalation and make the run
  exit non-zero; an interval that includes zero then stays `pending` (no note)
  until a rerun retries them. A resumed run runs the offline reliability check
  for escalation seeds too, before the first paid call.
- `inconclusive` (counts as no-ship): fewer than 3 fixtures remain. Checked
  after the offline reliability check, before the estimate and any paid call
  (exit 1), and again on the paired data. `--min-fixtures <n>` lowers the floor
  for tests only; a gate run that way is not valid.
- Turn cap: capped cells (`hitMaxTurns`) are counted per arm in the report.
- Output: raw per-arm table (hidden-test passes, capped cells, Read chars,
  re-reads, turns, output tokens), then the gate lines and a `Verdict:` line.
  Once all planned cells exist, the summary note goes to `docs/research/` as
  for single-turn.

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
call the API and need no network: agentic tests clone a tiny local git repo,
and `tests/fixtures.bats` checks the real fixtures' format, pins and plant
patches against local stand-ins (its live check is skipped unless
`BENCH_LIVE_FIXTURES=1`). `bats tests/` does not pick them up, and CI does not
run them.
