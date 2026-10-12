#!/usr/bin/env bats
# The ultra-no-focus arm (ticket 03): a temp copy of the hooks with the focus
# clause stripped from the per-turn reminder. The shipped hooks are only read.

load helpers

setup() { bench_setup; }
teardown() { bench_teardown; }

shipped_sums() {
  shasum "$KIT_DIR"/hooks/*
}

# Copies the kit hooks to $TEST_ROOT/fake-kit/hooks for a broken-tracker test.
fake_kit() {
  FAKE_KIT="$TEST_ROOT/fake-kit"
  mkdir -p "$FAKE_KIT/hooks"
  cp "$KIT_DIR"/hooks/* "$FAKE_KIT/hooks/"
}

@test "nofocus-patch: the copied reminder lacks the focus clause but otherwise equals ultra; shipped hooks unchanged" {
  before="$(shipped_sums)"
  export CFG="$TEST_ROOT/cfg" WORK="$TEST_ROOT/work"
  mkdir -p "$CFG" "$WORK"
  printf ultra > "$CFG/.caveman-active"

  node_assert '
    const { spawnSync } = require("child_process");
    const nofocus = require(process.env.BENCH_DIR + "/lib/nofocus");
    const shipped = path.join(process.env.KIT_DIR, "hooks");
    const { hooksDir, clause } = nofocus.patchNoFocus(shipped, isolation.createTempRoot());
    assert.ok(clause.startsWith("Answer only what was asked:"), clause);
    assert.notStrictEqual(hooksDir, shipped);
    assert.deepStrictEqual(fs.readdirSync(hooksDir).sort(), fs.readdirSync(shipped).sort());

    const env = { PATH: process.env.PATH, HOME: process.env.HOME, CLAUDE_CONFIG_DIR: process.env.CFG, CLAUDE_PLUGIN_ROOT: process.env.HOME + "/.claude" };
    const hook = (dir, script, input) => {
      const res = spawnSync("node", [path.join(dir, script)], { input: JSON.stringify(input), env, cwd: process.env.WORK, encoding: "utf8" });
      assert.strictEqual(res.status, 0, res.stderr);
      return JSON.parse(res.stdout).hookSpecificOutput.additionalContext;
    };
    const prompt = { prompt: "hello", cwd: process.env.WORK };
    const ultra = hook(shipped, "caveman-mode-tracker.js", prompt);
    const noFocus = hook(hooksDir, "caveman-mode-tracker.js", prompt);
    assert.ok(ultra.includes(clause), ultra);
    assert.ok(!noFocus.includes(clause), noFocus);
    assert.ok(!noFocus.includes("Answer only what was asked"), noFocus);
    assert.strictEqual(noFocus, "CAVEMAN MODE ACTIVE (ultra) — session ruleset applies.");
    assert.strictEqual(noFocus + " " + clause, ultra);

    // SessionStart context is untouched: same ruleset as ultra.
    const start = { source: "startup", hook_event_name: "SessionStart", cwd: process.env.WORK };
    assert.strictEqual(hook(hooksDir, "caveman-activate.js", start), hook(shipped, "caveman-activate.js", start));
  '

  [ "$(shipped_sums)" = "$before" ]
}

@test "nofocus-arm: the runner builds ultra-no-focus from the patched copy with flag ultra; shipped hooks unchanged" {
  before="$(shipped_sums)"

  run run_bench --kind single-turn --seeds 1 --yes
  [ "$status" -eq 0 ]

  log_assert '
    const nf = entries.filter(e => e.arm === "ultra-no-focus");
    assert.strictEqual(nf.length, 6);
    for (const e of nf) {
      assert.strictEqual(e.flag, "ultra");
      assert.strictEqual(e.env.CAVEMAN_DEFAULT_MODE, undefined);
      const s = JSON.parse(e.settings);
      for (const ev of ["SessionStart", "SubagentStart", "UserPromptSubmit"]) {
        const cmd = s.hooks[ev][0].hooks[0].command;
        assert.ok(cmd.includes("/hooks-no-focus/"), cmd);
        assert.ok(!cmd.includes(process.env.KIT_DIR + "/hooks/"), cmd);
        assert.ok(cmd.includes(process.env.TMPDIR), cmd);
      }
    }
  '
  [ "$(shipped_sums)" = "$before" ]
  [ "$(leftover_temp_dirs)" -eq 0 ]
}

@test "nofocus-abort: a --kit-dir whose tracker lacks the focus clause aborts before the estimate; claude never called" {
  fake_kit
  perl -i -pe 's/ session ruleset applies\.[^`]*`/ session ruleset applies.`/' "$FAKE_KIT/hooks/caveman-mode-tracker.js"
  grep -qF 'session ruleset applies.`' "$FAKE_KIT/hooks/caveman-mode-tracker.js"

  run run_bench --kind single-turn --seeds 1 --yes --kit-dir "$FAKE_KIT"

  [ "$status" -ne 0 ]
  [[ "$output" == *"ultra-no-focus: focus clause not found"* ]]
  [[ "$output" != *"Estimated cost"* ]]
  [ "$(stub_calls)" -eq 0 ]
  [ "$(leftover_temp_dirs)" -eq 0 ]
}

@test "nofocus-abort: a tracker without the reminder anchor aborts too" {
  fake_kit
  perl -i -pe 's/ — session ruleset applies\./ ruleset on./' "$FAKE_KIT/hooks/caveman-mode-tracker.js"

  run run_bench --kind single-turn --seeds 1 --yes --kit-dir "$FAKE_KIT"

  [ "$status" -ne 0 ]
  [[ "$output" == *"ultra-no-focus: focus clause not found"* ]]
  [[ "$output" != *"Estimated cost"* ]]
  [ "$(stub_calls)" -eq 0 ]
}
