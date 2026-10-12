# Extra helpers for bench/tests/agentic.bats (load after `load helpers`).

# A kit-dir for agentic runs: stub hooks that inject a stub Context Diet file,
# so tests do not depend on the real hooks. Sets KIT. The stub activate hook
# honours CAVEMAN_CONTEXT_DIET=0 unless INJECT_DIET=always (then it always
# injects) or INJECT_DIET=never.
make_diet_kit() {
  KIT="$TEST_ROOT/diet-kit"
  mkdir -p "$KIT/hooks"
  cat > "$KIT/hooks/caveman-context-diet.md" <<'DIET'
<!-- credit: test comment that must never be injected -->
STUB-DIET: grep first, read a range.
DIET
  printf '%s\n' "process.exit(0);" > "$KIT/hooks/caveman-mode-tracker.js"
  cat > "$KIT/hooks/caveman-activate.js" <<'HOOK'
const fs = require('fs');
const path = require('path');
let mode = 'off';
try { mode = fs.readFileSync(path.join(process.env.CLAUDE_CONFIG_DIR, '.caveman-active'), 'utf8').trim(); } catch (e) {}
if (mode === 'off') process.exit(0);
let ctx = `CAVEMAN MODE ACTIVE — level: ${mode}\nstub rules`;
const inject = process.env.INJECT_DIET || 'env';
if (inject === 'always' || (inject === 'env' && process.env.CAVEMAN_CONTEXT_DIET !== '0')) {
  try { ctx += '\n' + fs.readFileSync(path.join(__dirname, 'caveman-context-diet.md'), 'utf8').replace(/<!--[\s\S]*?-->/g, '').trim(); } catch (e) {}
}
console.log(JSON.stringify({ hookSpecificOutput: { hookEventName: 'SessionStart', additionalContext: ctx } }));
HOOK
}

# A tiny local git repo (no network): commit 1 has value.txt = good, commit 2
# adds later.txt. SRC_SHA is commit 1, the pinned one. PLANT turns good to bad.
make_source_repo() {
  SRC="$TEST_ROOT/src"
  mkdir -p "$SRC"
  git -C "$SRC" init -q
  git -C "$SRC" config user.name t
  git -C "$SRC" config user.email t@t
  git -C "$SRC" config commit.gpgsign false
  echo good > "$SRC/value.txt"
  git -C "$SRC" add -A
  git -C "$SRC" commit -qm first
  SRC_SHA="$(git -C "$SRC" rev-parse HEAD)"
  echo later > "$SRC/later.txt"
  git -C "$SRC" add -A
  git -C "$SRC" commit -qm second
  echo bad > "$SRC/value.txt"
  PLANT="$TEST_ROOT/plant.patch"
  git -C "$SRC" diff > "$PLANT"
  git -C "$SRC" checkout -q -- value.txt
}

# make_fixture <name> [hidden check script body]: fixture under $FIXTURES.
make_fixture() {
  FIXTURES="$TEST_ROOT/fixtures"
  local dir="$FIXTURES/$1"
  mkdir -p "$dir/hidden"
  cp "$PLANT" "$dir/plant.patch"
  echo "Fix the bug in value.txt." > "$dir/prompt.md"
  printf '%s\n' "${2:-grep -qx good value.txt}" > "$dir/hidden/check.sh"
  printf '{"source": "%s", "sha": "%s", "testCommand": "sh check.sh"}\n' "$SRC" "$SRC_SHA" > "$dir/fixture.json"
}

# Cell file for <arm> <fixture> <seed> in the only run dir under $RESULTS.
agentic_cell() {
  echo "$(ls -d "$RESULTS"/agentic-*)/$1--$2--s$3.json"
}

run_agentic() {
  run_bench --kind agentic --fixtures-dir "$FIXTURES" --kit-dir "$KIT" --min-fixtures 1 --no-escalate --yes "$@"
}

# make_fixtures <names...>: one valid fixture dir per name under $FIXTURES.
make_fixtures() {
  make_source_repo
  local name
  for name in "$@"; do make_fixture "$name"; done
  export FIXTURES
}

# Writes canned agentic cell files under $RESULTS/<run-id> (model and kind
# match the runner defaults, so the runner reuses them).
# $2 is JSON: {"fixtures": [...], "seeds": [1,2,3], "arms": {"<arm>":
# {"input": n, "noise": k, "pass": true|false, "capped": true|false}}}.
# input_tokens = input + shared(fixture, seed) + noise * e, e deterministic in
# [-1, 1] per (arm, fixture, seed); shared() is the same for every arm.
write_agentic_cells() {
  RUN_ID="$1" SPEC="$2" node -e '
    const path = require("path");
    const cells = require(process.env.BENCH_DIR + "/lib/cells");
    const spec = JSON.parse(process.env.SPEC);
    const runDir = path.join(process.env.RESULTS, process.env.RUN_ID);
    const rand = key => {
      let h = 2166136261;
      for (const ch of key) h = Math.imul(h ^ ch.charCodeAt(0), 16777619) >>> 0;
      return (h % 2001) / 1000 - 1;
    };
    for (const [arm, a] of Object.entries(spec.arms)) {
      spec.fixtures.forEach((task, fi) => {
        for (const seed of spec.seeds) {
          const shared = 50 * fi + 20 * seed;
          cells.writeJsonAtomic(cells.cellPath(runDir, { arm, task, seed }), {
            runId: process.env.RUN_ID, kind: "agentic", model: cells.DEFAULT_MODEL, arm, task, seed, totalCostUsd: 0.5,
            usage: {
              input_tokens: Math.round(a.input + shared + (a.noise || 0) * rand(`i|${arm}|${task}|${seed}`)),
              cache_read_input_tokens: 2000, cache_creation_input_tokens: 1000, output_tokens: 300,
            },
            hitMaxTurns: Boolean(a.capped),
            hiddenTest: { pass: Boolean(a.pass), exitCode: a.pass ? 0 : 1, timedOut: false, tail: "" },
            diagnostics: { readChars: 100, reReads: 1, turns: 7, outputTokens: 300 },
          });
        }
      });
    }
  '
}

# canned_arms <bare input> <full input> <diet input> <full pass> <diet pass>
canned_arms() {
  printf '{"bare":{"input":%s,"noise":20,"pass":false},"full":{"input":%s,"noise":20,"pass":%s},"full-diet":{"input":%s,"noise":20,"pass":%s}}' \
    "$1" "$2" "$4" "$3" "$5"
}
