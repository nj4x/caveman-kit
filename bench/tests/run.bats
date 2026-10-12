#!/usr/bin/env bats
# End-to-end tests of `node bench/run.js` with the stub `claude` on PATH.

load helpers

setup() { bench_setup; }
teardown() { bench_teardown; }

@test "arm-config: each arm's config registers the three kit hooks and seeds its flag" {
  run run_bench --kind single-turn --seeds 1 --yes
  [ "$status" -eq 0 ]
  [ "$(stub_calls)" -eq 30 ]

  log_assert '
    const modes = { bare: "off", "bare-control": "off", lite: "lite", full: "full", ultra: "ultra" };
    assert.deepStrictEqual([...new Set(entries.map(e => e.arm))].sort(), Object.keys(modes).sort());
    for (const e of entries) {
      const s = JSON.parse(e.settings);
      assert.deepStrictEqual(Object.keys(s).sort(), ["hooks"]);
      assert.deepStrictEqual(Object.keys(s.hooks).sort(), ["SessionStart", "SubagentStart", "UserPromptSubmit"]);
      const cmd = ev => { assert.strictEqual(s.hooks[ev].length, 1); return s.hooks[ev][0].hooks[0].command; };
      const hooks = process.env.KIT_DIR + "/hooks/";
      assert.ok(cmd("SessionStart").includes(hooks + "caveman-activate.js"), cmd("SessionStart"));
      assert.ok(cmd("SubagentStart").includes(hooks + "caveman-activate.js"));
      assert.ok(cmd("UserPromptSubmit").includes(hooks + "caveman-mode-tracker.js"));
      assert.strictEqual(e.flag, modes[e.arm], e.arm);
      if (modes[e.arm] === "off") assert.strictEqual(e.env.CAVEMAN_DEFAULT_MODE, "off", e.arm);
      else assert.strictEqual(e.env.CAVEMAN_DEFAULT_MODE, undefined, e.arm);
    }
  '
}

@test "plugin-root: hook commands and env set CLAUDE_PLUGIN_ROOT to a dir holding SKILL.md" {
  run run_bench --kind single-turn --seeds 1 --yes
  [ "$status" -eq 0 ]

  log_assert '
    for (const e of entries) {
      const root = e.env.CLAUDE_PLUGIN_ROOT;
      assert.ok(root, "env CLAUDE_PLUGIN_ROOT unset");
      assert.ok(e.skill && e.skill.includes("Respond terse"), "SKILL.md missing under " + root);
      const s = JSON.parse(e.settings);
      for (const ev of ["SessionStart", "SubagentStart", "UserPromptSubmit"]) {
        assert.ok(s.hooks[ev][0].hooks[0].command.startsWith("CLAUDE_PLUGIN_ROOT=\x27" + root + "\x27 node "), ev);
      }
    }
  '
}

@test "preflight-empty: a mode arm with empty injected context aborts before any claude call" {
  fake_kit="$TEST_ROOT/fake-kit"
  mkdir -p "$fake_kit/hooks"
  cp "$KIT_DIR"/hooks/*.js "$fake_kit/hooks/"
  printf '%s\n' "process.exit(0);" > "$fake_kit/hooks/caveman-activate.js"

  run run_bench --kind single-turn --seeds 1 --yes --kit-dir "$fake_kit"

  [ "$status" -ne 0 ]
  [[ "$output" == *"preflight lite: mode lite injected empty context"* ]]
  [[ "$output" != *"Estimated cost"* ]]
  [ "$(stub_calls)" -eq 0 ]
}

@test "auth-missing: no API key and no credentials file exits non-zero naming both, before estimate" {
  unset ANTHROPIC_API_KEY

  run run_bench --kind single-turn --seeds 1 --yes

  [ "$status" -ne 0 ]
  [[ "$output" == *"ANTHROPIC_API_KEY"* ]]
  [[ "$output" == *"$HOME/.claude/.credentials.json"* ]]
  [[ "$output" != *"Estimated cost"* ]]
  [ "$(stub_calls)" -eq 0 ]
}

@test "auth-credentials: without an API key a readable credentials file is copied into each arm" {
  unset ANTHROPIC_API_KEY
  echo '{"token":"x"}' > "$HOME/.claude/.credentials.json"

  run run_bench --kind single-turn --seeds 1 --yes

  [ "$status" -eq 0 ]
  log_assert '
    for (const e of entries) {
      assert.strictEqual(e.credentialsCopied, true);
      assert.strictEqual(e.env.ANTHROPIC_API_KEY, undefined);
    }
  '
}

@test "auth-api-key: the API key wins and no credentials file is copied" {
  echo '{"token":"x"}' > "$HOME/.claude/.credentials.json"

  run run_bench --kind single-turn --seeds 1 --yes

  [ "$status" -eq 0 ]
  log_assert '
    for (const e of entries) {
      assert.strictEqual(e.credentialsCopied, false);
      assert.strictEqual(e.env.ANTHROPIC_API_KEY, "test-key");
    }
  '
}

@test "no-tty: without --yes and no TTY the run refuses and never calls claude" {
  run run_bench --kind single-turn --seeds 1

  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing to start"* ]]
  [[ "$output" == *"--yes"* ]]
  [ "$(stub_calls)" -eq 0 ]
}

@test "real-config-hidden: the user's real config dir never reaches claude" {
  echo '{"token":"x"}' > "$HOME/.claude/.credentials.json"
  export CAVEMAN_CONTEXT_DIET=1
  unset ANTHROPIC_API_KEY

  run run_bench --kind single-turn --seeds 1 --yes
  [ "$status" -eq 0 ]

  ! grep -qF "$HOME/.claude" "$STUB_LOG" || false
  ! grep -qF "REAL USER CLAUDE.md" "$STUB_LOG" || false
  ! grep -qF "real-user-hook" "$STUB_LOG" || false
  log_assert '
    for (const e of entries) {
      assert.ok(e.configDir.startsWith(process.env.TMPDIR), e.configDir);
      assert.ok(e.cwd.startsWith(fs.realpathSync(process.env.TMPDIR)) || e.cwd.startsWith(process.env.TMPDIR), e.cwd);
      assert.strictEqual(e.env.CAVEMAN_CONTEXT_DIET, undefined);
    }
  '
}

@test "real-config-hidden: an explicit CLAUDE_CONFIG_DIR is replaced, never passed through" {
  export CLAUDE_CONFIG_DIR="$TEST_ROOT/custom-config"
  mkdir -p "$CLAUDE_CONFIG_DIR/skills/caveman"
  cp "$HOME/.claude/skills/caveman/SKILL.md" "$CLAUDE_CONFIG_DIR/skills/caveman/"

  run run_bench --kind single-turn --seeds 1 --yes
  [ "$status" -eq 0 ]

  ! grep -qF "$CLAUDE_CONFIG_DIR" "$STUB_LOG" || false
}

@test "estimate-first: the cost estimate prints before the first claude call" {
  export STUB_MARK="$TEST_ROOT/combined.log"

  node "$BENCH_DIR/run.js" --results-dir "$RESULTS" --research-dir "$RESEARCH" --kind single-turn --seeds 1 --yes < /dev/null >> "$STUB_MARK"

  estimate_line="$(grep -n 'Estimated cost' "$STUB_MARK" | head -1 | cut -d: -f1)"
  first_call="$(grep -n 'STUB CALL' "$STUB_MARK" | head -1 | cut -d: -f1)"
  [ -n "$estimate_line" ]
  [ -n "$first_call" ]
  [ "$estimate_line" -lt "$first_call" ]
}

@test "resume: existing cells are skipped on rerun and failed cells are retried" {
  STUB_FAIL_ARM=lite run run_bench --kind single-turn --seeds 1 --yes --run-id resume-test
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL lite--"* ]]
  [[ "$output" == *"rerun with --run-id resume-test"* ]]
  [ "$(find "$RESULTS/resume-test" -name '*.json' | wc -l | tr -d ' ')" -eq 24 ]
  [ "$(find "$RESULTS/resume-test" -name 'lite--*' | wc -l | tr -d ' ')" -eq 0 ]

  rm "$STUB_LOG"
  run run_bench --kind single-turn --seeds 1 --yes --run-id resume-test
  [ "$status" -eq 0 ]
  [ "$(stub_calls)" -eq 6 ]
  log_assert 'assert.ok(entries.every(e => e.arm === "lite"));'
  [ "$(find "$RESULTS/resume-test" -name '*.json' | wc -l | tr -d ' ')" -eq 30 ]

  rm "$STUB_LOG"
  run run_bench --kind single-turn --seeds 1 --run-id resume-test
  [ "$status" -eq 0 ]
  [ "$(stub_calls)" -eq 0 ]
}

@test "report: a rerun with fewer seeds reports only its own planned cells" {
  run run_bench --kind single-turn --seeds 2 --yes --run-id seeds-test
  [ "$status" -eq 0 ]

  run run_bench --kind single-turn --seeds 1 --run-id seeds-test
  [ "$status" -eq 0 ]
  echo "$output" | grep -E '^bare +6 '
}

@test "cells: one file per arm x task x seed, written atomically with usage" {
  run run_bench --kind single-turn --seeds 2 --yes --run-id cells-test
  [ "$status" -eq 0 ]
  [ "$(stub_calls)" -eq 60 ]
  [ "$(find "$RESULTS/cells-test" -type f | wc -l | tr -d ' ')" -eq 60 ]
  [ "$(find "$RESULTS/cells-test" -name '.*' | wc -l | tr -d ' ')" -eq 0 ]
  [ -f "$RESULTS/cells-test/ultra--design-cache--s2.json" ]

  node -e '
    const c = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const assert = require("assert");
    assert.strictEqual(c.arm, "ultra");
    assert.strictEqual(c.task, "design-cache");
    assert.strictEqual(c.seed, 2);
    assert.strictEqual(c.model, "claude-sonnet-5-5");
    assert.strictEqual(typeof c.usage.output_tokens, "number");
  ' "$RESULTS/cells-test/ultra--design-cache--s2.json"
}

@test "cli: claude gets -p, JSON output and the model; the seed is never passed" {
  run run_bench --kind single-turn --seeds 1 --yes --model claude-opus-5-5
  [ "$status" -eq 0 ]

  log_assert '
    for (const e of entries) {
      assert.strictEqual(e.argv[0], "-p");
      assert.deepStrictEqual(e.argv.slice(2), ["--output-format", "json", "--model", "claude-opus-5-5"]);
    }
  '
}

@test "cli: run id defaults to <kind>-<model>-<kit-dir HEAD short SHA>" {
  sha="$(/usr/bin/git -C "$KIT_DIR" rev-parse --short HEAD)"

  run run_bench --kind single-turn --seeds 1 --yes

  [ "$status" -eq 0 ]
  [ -d "$RESULTS/single-turn-claude-sonnet-5-5-$sha" ]
}

@test "cli: --kind is required, agentic is not implemented, bad flags are rejected" {
  run run_bench --seeds 1 --yes
  [ "$status" -eq 2 ]
  [[ "$output" == *"--kind is required"* ]]

  run run_bench --kind agentic --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"not implemented"* ]]

  run run_bench --kind single-turn --seeds 0 --yes
  [ "$status" -eq 2 ]

  run run_bench --kind single-turn --bogus --yes
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown option: --bogus"* ]]

  run run_bench --kind single-turn --run-id .. --yes
  [ "$status" -eq 2 ]
  [[ "$output" == *"--run-id must start with a letter or digit"* ]]

  run run_bench --kind single-turn --run-id --yes
  [ "$status" -eq 2 ]
  [[ "$output" == *"--run-id needs a value"* ]]

  run run_bench --kind single-turn --yes=no
  [ "$status" -eq 2 ]

  [ "$(stub_calls)" -eq 0 ]
}

@test "report: prints a per-arm table of raw output and usage totals" {
  run run_bench --kind single-turn --seeds 1 --yes
  [ "$status" -eq 0 ]

  # Stub output_tokens for bare = 500 + call count (1..6): 3021 in total.
  [[ "$output" == *"output"*"cache_read"*"cache_write"* ]]
  echo "$output" | grep -E '^bare +6 +3021 +60 +12000 +6000 '
  echo "$output" | grep -E '^ultra +6 +1221 '
}

@test "six single-turn tasks are defined with unique ids" {
  node -e '
    const tasks = require(process.env.BENCH_DIR + "/tasks/single-turn");
    const assert = require("assert");
    assert.strictEqual(tasks.length, 6);
    assert.strictEqual(new Set(tasks.map(t => t.id)).size, 6);
    for (const t of tasks) assert.ok(t.prompt && t.prompt.length > 20, t.id);
  '
}

@test "bats-isolation: bats tests/ does not pick up bench tests" {
  expected="$(cat "$KIT_DIR"/tests/*.bats | grep -c '^@test')"

  [ "$(bats --count "$KIT_DIR/tests")" -eq "$expected" ]
  [ "$(bats --count "$KIT_DIR/tests")" -lt "$(bats --count "$KIT_DIR/tests" "$BENCH_DIR/tests")" ]
}
