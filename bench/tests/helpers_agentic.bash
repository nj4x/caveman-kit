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
  run_bench --kind agentic --fixtures-dir "$FIXTURES" --kit-dir "$KIT" --yes "$@"
}
