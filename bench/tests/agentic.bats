#!/usr/bin/env bats
# `node bench/run.js --kind agentic` with the stub `claude` on PATH and a tiny
# local git repo as the fixture clone source. No network, no API.

load helpers
load helpers_agentic

setup() {
  bench_setup
  make_diet_kit
  export KIT
  make_source_repo
  make_fixture tiny
  export FIXTURES
}
teardown() { bench_teardown; }

@test "agentic-arms: runs bare, full, full-diet per fixture and seed and records the hidden-test result per cell" {
  STUB_FIX_ARMS=full,full-diet run run_agentic --seeds 2
  [ "$status" -eq 0 ]
  [ "$(stub_calls)" -eq 6 ]

  # The stub fixes value.txt for full and full-diet only; bare leaves the planted bug.
  node -e '
    const fs = require("fs");
    const assert = require("assert");
    const read = (arm, seed) => JSON.parse(fs.readFileSync(process.argv[1] + "/" + arm + "--tiny--s" + seed + ".json", "utf8"));
    const dir = fs.readdirSync(process.env.RESULTS)[0];
    process.argv[1] = process.env.RESULTS + "/" + dir;
    for (const seed of [1, 2]) {
      assert.strictEqual(read("bare", seed).hiddenTest.pass, false);
      assert.strictEqual(read("full", seed).hiddenTest.pass, true);
      assert.strictEqual(read("full-diet", seed).hiddenTest.pass, true);
      assert.strictEqual(read("full", seed).kind, "agentic");
    }
  '
  echo "$output" | grep -E '^bare +2 +0/2 '
  echo "$output" | grep -E '^full +2 +2/2 '
  echo "$output" | grep -E '^full-diet +2 +2/2 '
}

@test "agentic-cli: stub is called with stream-json output and the fixture prompt in the cloned work dir" {
  run run_agentic --seeds 1
  [ "$status" -eq 0 ]

  log_assert '
    assert.strictEqual(entries.length, 3);
    for (const e of entries) {
      assert.ok(e.argv.includes("stream-json"), e.argv.join(" "));
      assert.strictEqual(e.argv[e.argv.indexOf("-p") + 1], "Fix the bug in value.txt.");
      assert.strictEqual(e.value, "bad\n", "plant patch applied in the work dir");
    }
  '
}

@test "agentic-diagnostics: canned stream-json yields the expected Read chars, re-reads, turns, output tokens" {
  run run_agentic --seeds 1
  [ "$status" -eq 0 ]

  node -e '
    const fs = require("fs");
    const assert = require("assert");
    const dir = process.env.RESULTS + "/" + fs.readdirSync(process.env.RESULTS)[0];
    // Reads: 100 + 100 (re-read) + 120 (after an Edit, fresh) + 30 + 20 (re-read of a covered range) = 370.
    // The 999-char Bash result is not a Read.
    const expected = { bare: 501, full: 301, "full-diet": 201 };
    for (const [arm, out] of Object.entries(expected)) {
      const cell = JSON.parse(fs.readFileSync(dir + "/" + arm + "--tiny--s1.json", "utf8"));
      assert.deepStrictEqual(cell.diagnostics, { readChars: 370, reReads: 2, turns: 7, outputTokens: out }, arm);
      assert.strictEqual(cell.usage.cache_read_input_tokens, arm === "full-diet" ? 1000 : 2000);
      assert.ok(fs.existsSync(dir + "/" + arm + "--tiny--s1.stream.jsonl"));
    }
  '
}

@test "agentic-stream: analyze handles array content, missing num_turns and junk lines" {
  node -e '
    const assert = require("assert");
    const { analyze } = require(process.env.BENCH_DIR + "/lib/stream");
    const lines = [
      "not json",
      JSON.stringify({ type: "assistant", message: { id: "a", content: [{ type: "tool_use", id: "1", name: "Read", input: { file_path: "/x" } }] } }),
      JSON.stringify({ type: "user", message: { content: [{ type: "tool_result", tool_use_id: "1", content: [{ type: "text", text: "abcd" }] }] } }),
      JSON.stringify({ type: "assistant", message: { id: "b", content: [{ type: "tool_use", id: "2", name: "Read", input: { file_path: "/x" } }] } }),
      JSON.stringify({ type: "user", message: { content: [{ type: "tool_result", tool_use_id: "2", content: "ef" }] } }),
      JSON.stringify({ type: "result", is_error: false, usage: { output_tokens: 9 } }),
    ].join("\n");
    assert.deepStrictEqual(analyze(lines).diagnostics, { readChars: 6, reReads: 1, turns: 2, outputTokens: 9 });
    assert.deepStrictEqual(analyze("").diagnostics, { readChars: 0, reReads: 0, turns: 0, outputTokens: 0 });

    // An errored whole-file Read covers nothing; a Read with no limit covers
    // only the first 2000 lines.
    const use = (id, input) => JSON.stringify({ type: "assistant", message: { id, content: [{ type: "tool_use", id, name: "Read", input }] } });
    const res = (id, extra) => JSON.stringify({ type: "user", message: { content: [{ type: "tool_result", tool_use_id: id, content: "e", ...extra }] } });
    const stream = [
      use("1", { file_path: "/y" }), res("1", { is_error: true }),
      use("2", { file_path: "/y", offset: 5, limit: 3 }), res("2"),
      use("3", { file_path: "/z" }), res("3"),
      use("4", { file_path: "/z", offset: 2001, limit: 10 }), res("4"),
      use("5", { file_path: "/z", offset: null, limit: 50 }), res("5"),
    ].join("\n");
    assert.strictEqual(analyze(stream).diagnostics.reReads, 1);
  '
}

@test "preflight-diet-in-full: diet text present in the full arm aborts non-zero before any stub call" {
  INJECT_DIET=always run run_agentic --seeds 1

  [ "$status" -ne 0 ]
  [[ "$output" == *"preflight full: context contains forbidden text"* ]] || false
  [[ "$output" == *"STUB-DIET"* ]] || false
  [[ "$output" != *"credit: test comment"* ]] || false
  [[ "$output" != *"Estimated cost"* ]] || false
  [ "$(stub_calls)" -eq 0 ]
}

@test "preflight-diet-missing-in-full-diet: absent diet text in full-diet aborts before any stub call" {
  INJECT_DIET=never run run_agentic --seeds 1

  [ "$status" -ne 0 ]
  [[ "$output" == *"preflight full-diet: context lacks required text"* ]] || false
  [ "$(stub_calls)" -eq 0 ]
}

@test "preflight-diet-file-missing: a kit-dir without the diet file aborts before any stub call" {
  rm "$KIT/hooks/caveman-context-diet.md"

  run run_agentic --seeds 1

  [ "$status" -ne 0 ]
  [[ "$output" == *"Context Diet file missing or unreadable"* ]] || false
  [[ "$output" != *"Estimated cost"* ]] || false
  [ "$(stub_calls)" -eq 0 ]
}

@test "diet-env: the stub sees CAVEMAN_CONTEXT_DIET=0 for full only" {
  # A value in the caller's environment must not leak into the arms.
  CAVEMAN_CONTEXT_DIET=1 run run_agentic --seeds 1
  [ "$status" -eq 0 ]

  log_assert '
    const byArm = Object.fromEntries(entries.map(e => [e.arm, e.env.CAVEMAN_CONTEXT_DIET]));
    assert.deepStrictEqual(byArm, { bare: undefined, full: "0", "full-diet": undefined });
    const modes = Object.fromEntries(entries.map(e => [e.arm, e.flag]));
    assert.deepStrictEqual(modes, { bare: "off", full: "full", "full-diet": "full" });
    assert.strictEqual(entries.find(e => e.arm === "bare").env.CAVEMAN_DEFAULT_MODE, "off");
  '
}

@test "hidden-test-absent: the hidden test is not in the work dir while the stub runs, and runs afterwards" {
  STUB_ABSENT=check.sh STUB_FIX_ARMS=full run run_agentic --seeds 1
  [ "$status" -eq 0 ]

  log_assert '
    assert.strictEqual(entries.length, 3);
    for (const e of entries) assert.strictEqual(e.present["check.sh"], false, e.arm);
  '
  # The hidden test did run after the agent: full (fixed by the stub) passes.
  grep -q '"pass": true' "$(agentic_cell full tiny 1)"
  grep -q '"pass": false' "$(agentic_cell bare tiny 1)"
}

@test "fixture-clone: work dir is checked out at the pinned SHA with no remote" {
  run node -e '
    const fx = require(process.env.BENCH_DIR + "/lib/fixtures");
    const fs = require("fs");
    const { spawnSync } = require("child_process");
    const f = fx.loadFixture(process.env.FIXTURES, "tiny");
    const dir = fs.mkdtempSync(process.env.TMPDIR + "/wd-");
    fx.prepareWorkDir(f, dir);
    const git = (...a) => spawnSync("git", ["-C", dir, ...a], { encoding: "utf8" }).stdout.trim();
    const assert = require("assert");
    assert.strictEqual(fs.readFileSync(dir + "/value.txt", "utf8"), "bad\n");
    assert.ok(!fs.existsSync(dir + "/later.txt"), "second commit must not be present");
    assert.strictEqual(git("remote"), "");
    assert.strictEqual(git("status", "--porcelain"), "");
    // One root commit: neither the plant nor the upstream history is visible.
    assert.strictEqual(git("rev-list", "--all", "--count"), "1");
    assert.strictEqual(git("log", "--all", "--format=%s"), "initial");
    assert.ok(!fs.existsSync(dir + "/check.sh"));
  '
  [ "$status" -eq 0 ]
}

@test "fixture-flaky: a fixture whose hidden test is unreliable is dropped and listed before any paid call" {
  export FLAKY_FILE="$TEST_ROOT/flaky-state"
  make_fixture flaky 'grep -qx good value.txt || exit 1; [ ! -e "$FLAKY_FILE" ] || exit 1; : > "$FLAKY_FILE"'

  run run_agentic --seeds 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"DROPPED fixture flaky: hidden test fails on the unpatched tree"* ]] || false
  # Only the tiny fixture ran: 3 arms x 1 fixture x 1 seed.
  [ "$(stub_calls)" -eq 3 ]
  [[ "$output" == *"3 arms x 1 fixtures x 1 seeds"* ]] || false
  [ ! -e "$(agentic_cell bare flaky 1)" ]
}

@test "fixture-broken-plant: a hidden test that passes on the planted tree is dropped" {
  make_fixture vacuous 'true'

  run run_agentic --seeds 1 --fixtures tiny,vacuous
  [ "$status" -eq 0 ]
  [[ "$output" == *"DROPPED fixture vacuous: hidden test passes on the planted tree"* ]] || false
  [ "$(stub_calls)" -eq 3 ]
}

@test "fixture-all-dropped: no usable fixture left exits non-zero without a stub call" {
  rm -rf "$FIXTURES/tiny"
  make_fixture vacuous 'true'

  run run_agentic --seeds 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"no usable fixtures left"* ]] || false
  [ "$(stub_calls)" -eq 0 ]
}

@test "agentic-fixtures-flag: --fixtures selects by name and an unknown name aborts" {
  make_fixture second

  run run_agentic --seeds 1 --fixtures second
  [ "$status" -eq 0 ]
  [ "$(stub_calls)" -eq 3 ]
  [ -e "$(agentic_cell bare second 1)" ]
  [ ! -e "$(agentic_cell bare tiny 1)" ]

  run run_agentic --seeds 1 --fixtures nosuch --run-id other
  [ "$status" -ne 0 ]
  [[ "$output" == *"fixture nosuch: cannot read"* ]] || false
  [ "$(stub_calls)" -eq 3 ]
}

@test "agentic-kit-dir: the hooks measured come from --kit-dir" {
  run run_agentic --seeds 1
  [ "$status" -eq 0 ]

  log_assert '
    for (const e of entries) {
      const cmd = JSON.parse(e.settings).hooks.SessionStart[0].hooks[0].command;
      assert.ok(cmd.includes(process.env.KIT + "/hooks/caveman-activate.js"), cmd);
    }
  '
}

@test "agentic-estimate: the cost estimate prints before the first stub call" {
  export STUB_MARK="$TEST_ROOT/combined.log"

  node "$BENCH_DIR/run.js" --results-dir "$RESULTS" --kind agentic --fixtures-dir "$FIXTURES" --kit-dir "$KIT" --research-dir "$RESEARCH" --min-fixtures 1 --no-escalate --seeds 1 --yes < /dev/null >> "$STUB_MARK"

  estimate_line="$(grep -n 'Estimated cost: 3 call(s)' "$STUB_MARK" | head -1 | cut -d: -f1)"
  first_call="$(grep -n 'STUB CALL' "$STUB_MARK" | head -1 | cut -d: -f1)"
  [ -n "$estimate_line" ]
  [ -n "$first_call" ]
  [ "$estimate_line" -lt "$first_call" ]
}

@test "agentic-resume: existing cells are skipped on rerun" {
  run run_agentic --seeds 1 --run-id r1
  [ "$status" -eq 0 ]
  [ "$(stub_calls)" -eq 3 ]

  run run_agentic --seeds 1 --run-id r1
  [ "$status" -eq 0 ]
  [ "$(stub_calls)" -eq 3 ]

  # Cells carry kind and model; a cell from another model is stale and rerun.
  grep -q '"kind": "agentic"' "$RESULTS/r1/bare--tiny--s1.json"
  grep -q '"model": "claude-sonnet-5-5"' "$RESULTS/r1/bare--tiny--s1.json"
  run run_agentic --seeds 1 --run-id r1 --model claude-opus-5-5
  [ "$status" -eq 0 ]
  [ "$(stub_calls)" -eq 6 ]
  grep -q '"model": "claude-opus-5-5"' "$RESULTS/r1/bare--tiny--s1.json"
}

@test "agentic-cell-timeout: a hung agent is killed after --cell-timeout and the cell fails" {
  STUB_SLEEP=60 STUB_IGNORE_TERM=1 run run_agentic --seeds 1 --run-id hung --cell-timeout 1 --fixtures tiny
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL bare--tiny--s1: timed out after 1s"* ]] || false
  [ ! -e "$RESULTS/hung/bare--tiny--s1.json" ]
  [ "$(leftover_temp_dirs)" -eq 0 ]
}

@test "agentic-failed-cell: a failing stub leaves no cell file and exits non-zero; temp dir is removed" {
  STUB_FAIL_ARM=full run run_agentic --seeds 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL full--tiny--s1"* ]] || false
  [ ! -e "$(agentic_cell full tiny 1)" ]
  [ -e "$(agentic_cell bare tiny 1)" ]
  [ "$(leftover_temp_dirs)" -eq 0 ]
}

@test "agentic-no-fixtures: an empty fixtures dir aborts non-zero before any stub call" {
  mkdir -p "$TEST_ROOT/empty"

  run run_bench --kind agentic --fixtures-dir "$TEST_ROOT/empty" --kit-dir "$KIT" --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"no fixtures found"* ]] || false
  [ "$(stub_calls)" -eq 0 ]
}

@test "agentic-max-turns: a run that hits the turn cap is a completed cell, hidden test still runs" {
  STUB_MAX_TURNS=1 STUB_FIX_ARMS=full run run_agentic --seeds 1
  [ "$status" -eq 0 ]
  [ "$(stub_calls)" -eq 3 ]
  # The stub exits 1 on a max-turns stop, like the real CLI.
  grep -q '"hitMaxTurns": true' "$(agentic_cell full tiny 1)"
  grep -q '"pass": true' "$(agentic_cell full tiny 1)"
  grep -q '"pass": false' "$(agentic_cell bare tiny 1)"
}

@test "agentic-nonzero-exit: a non-zero exit with a success or other error stream writes no cell file" {
  STUB_EXIT=3 run run_agentic --seeds 1 --run-id exit-success
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL full--tiny--s1: exit 3"* ]] || false
  [ ! -e "$RESULTS/exit-success/full--tiny--s1.json" ]
  [ ! -e "$RESULTS/exit-success/full--tiny--s1.stream.jsonl" ]

  STUB_RESULT_ERROR=1 STUB_EXIT=1 run run_agentic --seeds 1 --run-id exit-error
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL bare--tiny--s1: exit 1"* ]] || false
  [ ! -e "$RESULTS/exit-error/bare--tiny--s1.json" ]

  # is_error with exit 0 and a subtype other than error_max_turns also fails.
  STUB_RESULT_ERROR=1 run run_agentic --seeds 1 --run-id result-error
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL bare--tiny--s1: no usable result event"* ]] || false
  [ ! -e "$RESULTS/result-error/bare--tiny--s1.json" ]
}

@test "agentic-signal: a run killed by a signal fails even after a max-turns stream" {
  STUB_MAX_TURNS=1 STUB_SELF_KILL=1 run run_agentic --seeds 1 --run-id killed
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL full--tiny--s1: killed by SIGKILL"* ]] || false
  [ ! -e "$RESULTS/killed/full--tiny--s1.json" ]
}

@test "agentic-fixtures-names: duplicates collapse and unsafe names are rejected" {
  run run_agentic --seeds 1 --fixtures tiny,tiny
  [ "$status" -eq 0 ]
  [ "$(stub_calls)" -eq 3 ]

  run run_agentic --seeds 1 --fixtures ../tiny --run-id other
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid fixture name"* ]] || false
}

@test "agentic-stream-redaction: neither the raw stream, the cell file nor a FAIL line contains the API key" {
  # The hidden test prints a file the agent wrote holding the key.
  printf '%s\n' 'cat leak.txt; grep -qx good value.txt' > "$FIXTURES/tiny/hidden/check.sh"

  STUB_LEAK=1 run run_agentic --seeds 1
  [ "$status" -eq 0 ]
  ! grep -q 'test-key' "$(agentic_cell bare tiny 1)" || false
  grep -q 'leaked \[redacted\]' "$(agentic_cell bare tiny 1)"
  node -e '
    const cell = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    if (!cell.hiddenTest.tail.includes("[redacted]")) throw new Error("tail: " + cell.hiddenTest.tail);
  ' "$(agentic_cell bare tiny 1)"

  STUB_LEAK=1 STUB_EXIT=2 run run_agentic --seeds 1 --run-id leak-fail
  [ "$status" -ne 0 ]
  [[ "$output" == *"stub stderr [redacted]"* ]] || false
  [[ "$output" != *"test-key"* ]] || false

  # The 500-char cut falls inside the key: redaction must happen first, so no
  # fragment ("t-key") survives.
  STUB_LEAK=1 STUB_EXIT=2 STUB_STDERR_PAD=495 run run_agentic --seeds 1 --run-id leak-cut
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL bare--tiny--s1: exit 2: cted]ppp"* ]] || false
  [[ "$output" != *"t-keyppp"* ]] || false

  stream="$(ls -d "$RESULTS"/agentic-*)/bare--tiny--s1.stream.jsonl"
  grep -q '\[redacted\]' "$stream"
  ! grep -q 'test-key' "$stream" || false
}

@test "fixture-relative-source: a relative source resolves against the fixture dir" {
  mkdir -p "$FIXTURES/rel"
  cp -R "$FIXTURES/tiny/." "$FIXTURES/rel/"
  ln -s "$SRC" "$FIXTURES/rel/repo"
  node -e '
    const fs = require("fs");
    const f = process.env.FIXTURES + "/rel/fixture.json";
    const j = JSON.parse(fs.readFileSync(f, "utf8"));
    j.source = "repo";
    fs.writeFileSync(f, JSON.stringify(j));
  '

  run run_agentic --seeds 1 --fixtures rel
  [ "$status" -eq 0 ]
  [ "$(stub_calls)" -eq 3 ]
}

@test "hidden-copy-failure: an uncopyable hidden test is a failed test, not a crashed run" {
  # A file in hidden/ where the repo has a directory of the same name.
  mkdir -p "$SRC/blocked"
  : > "$SRC/blocked/keep"
  git -C "$SRC" add -A
  git -C "$SRC" commit -qm third
  sha="$(git -C "$SRC" rev-parse HEAD)"
  node -e '
    const fs = require("fs");
    const f = process.env.FIXTURES + "/tiny/fixture.json";
    const j = JSON.parse(fs.readFileSync(f, "utf8"));
    j.sha = process.argv[1];
    fs.writeFileSync(f, JSON.stringify(j));
  ' "$sha"
  node -e '
    const fx = require(process.env.BENCH_DIR + "/lib/fixtures");
    const assert = require("assert");
    const fs = require("fs");
    const f = fx.loadFixture(process.env.FIXTURES, "tiny");
    fs.writeFileSync(f.hiddenDir + "/blocked", "file");
    const dir = fs.mkdtempSync(process.env.TMPDIR + "/wd-");
    fx.prepareWorkDir(f, dir);
    const res = fx.runHiddenTest(f, dir);
    assert.strictEqual(res.pass, false);
    assert.ok(res.tail.includes("could not copy hidden test"), res.tail);
  '
}
