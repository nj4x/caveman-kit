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
| `--kind single-turn\|agentic` | required | harness kind (`agentic` is not implemented yet) |
| `--seeds <n>` | `3` | repeats per arm × task; never passed to `claude` |
| `--model <id>` | `claude-sonnet-5-5` | passed to `claude --model` |
| `--kit-dir <path>` | repo root | kit checkout whose `hooks/` are measured |
| `--run-id <id>` | `<kind>-<model>-<kit-dir HEAD short SHA>` | results subdirectory |
| `--results-dir <dir>` | `bench/results` | parent of run directories |
| `--yes` | off | start without asking; required when there is no TTY |

Single-turn arms: `bare`, `bare-control`, `lite`, `full`, `ultra`, over the six
prompts in `tasks/single-turn.js`. The bare arms register the same hooks with
the flag seeded to `off` and `CAVEMAN_DEFAULT_MODE=off`.

## Resuming

Each successful call writes one file, `<results-dir>/<run-id>/<arm>--<task>--s<seed>.json`.
A rerun with the same run id skips cells that already have a file and retries
failed ones. The default run id depends only on the kit-dir's HEAD commit, so
uncommitted hook edits reuse the old id: pass `--run-id` to keep them apart.

## Isolation and auth

Each call gets a fresh temp config dir (`0700`, removed on exit, error and
SIGINT/SIGTERM/SIGHUP) holding only the kit's three hooks, the seeded flag, a copy of
the caveman `SKILL.md`, and auth. Your own `CLAUDE.md`, settings, plugins and
hooks are never used, and `claude` runs in an empty temp working directory.

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
