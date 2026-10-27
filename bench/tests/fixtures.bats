#!/usr/bin/env bats
# The real agentic fixtures under bench/fixtures/ (ADR 0008 decision 5). No
# network: the format, the pins and the plant patches are checked against
# local stand-ins. The live clone-and-test check is opt-in (BENCH_LIVE_FIXTURES=1).

load helpers

setup() {
  # The live check needs the real HOME: the uv cache lives there.
  export REAL_HOME="$HOME"
  bench_setup
  export FIXTURES_DIR="$BENCH_DIR/fixtures"
}
teardown() { bench_teardown; }

# Evaluates JS with the fixture module loaded as `fixtures` and the real
# fixture dir in `dir`.
fixture_assert() {
  node -e '
    const fs = require("fs");
    const path = require("path");
    const assert = require("assert");
    const fixtures = require(process.env.BENCH_DIR + "/lib/fixtures");
    const dir = process.env.FIXTURES_DIR;
    '"$1"'
  '
}

@test "real-fixtures-format: bench/fixtures holds adminalias, bigfile, noisylog, parallel, retryafter, reuse, rootcause, suitecheck, tierslot and each loads" {
  fixture_assert '
    assert.deepStrictEqual(fixtures.listFixtureNames(dir), ["adminalias", "bigfile", "noisylog", "parallel", "retryafter", "reuse", "rootcause", "suitecheck", "tierslot"]);
    for (const name of fixtures.listFixtureNames(dir)) {
      const f = fixtures.loadFixture(dir, name);
      assert.ok(f.prompt.length > 80, `${name}: prompt too short`);
      assert.ok(fs.statSync(f.plantPatch).size > 0, `${name}: empty plant patch`);
    }
  '
}

@test "real-fixtures-pins: each fixture pins a full 40-hex commit of its nj4x source repo" {
  fixture_assert '
    const expected = {
      adminalias: "https://github.com/nj4x/anthrouter.git",
      bigfile: "https://github.com/nj4x/anthrouter.git",
      rootcause: "https://github.com/nj4x/anthrouter.git",
      noisylog: "https://github.com/nj4x/anthrouter.git",
      parallel: "https://github.com/nj4x/anthrouter.git",
      reuse: "https://github.com/nj4x/skills-dev.git",
      suitecheck: "https://github.com/nj4x/anthrouter.git",
      retryafter: "https://github.com/nj4x/anthrouter.git",
      tierslot: "https://github.com/nj4x/anthrouter.git",
    };
    const shaBySource = {};
    for (const [name, source] of Object.entries(expected)) {
      const f = fixtures.loadFixture(dir, name);
      assert.strictEqual(f.source, source, name);
      assert.match(f.sha, /^[0-9a-f]{40}$/, `${name}: sha must be a full 40-hex commit`);
      // One pin per source repo, so the anthrouter fixtures test the same code.
      shaBySource[source] = shaBySource[source] || f.sha;
      assert.strictEqual(f.sha, shaBySource[source], `${name}: pins a different ${source} commit`);
    }
  '
}

@test "real-fixtures-hidden: each testCommand runs a hidden test shipped in hidden/, via pytest or uv, never a file the plant touches" {
  fixture_assert '
    for (const name of fixtures.listFixtureNames(dir)) {
      const f = fixtures.loadFixture(dir, name);
      const files = [...new Set(f.testCommand.match(/\S+\.py\b/g) || [])];
      assert.strictEqual(files.length, 1, `${name}: testCommand must name one test file`);
      assert.ok(fs.existsSync(path.join(f.hiddenDir, files[0])), `${name}: ${files[0]} missing from hidden/`);
      assert.ok(f.testCommand.includes("python3 -m pytest"), `${name}: no pytest branch`);
      assert.ok(f.testCommand.includes("uv run"), `${name}: no uv branch`);
      const touched = fs.readFileSync(f.plantPatch, "utf8").match(/^\+\+\+ b\/(.+)$/gm).map(l => l.slice(6));
      assert.ok(!touched.includes(files[0]), `${name}: plant patch touches the hidden test`);
    }
  '
}

@test "real-fixtures-plant: each plant patch applies through prepareWorkDir to a local stand-in and yields the planted tree" {
  for name in adminalias bigfile noisylog parallel retryafter reuse rootcause suitecheck tierslot; do
    standin="$TEST_ROOT/standin-$name"
    node "$BENCH_DIR/tests/patch_standin.js" "$FIXTURES_DIR/$name/plant.patch" "$standin" > "$TEST_ROOT/$name.touched"
    [ -s "$TEST_ROOT/$name.touched" ]
    git -C "$standin/pre" init -q
    git -C "$standin/pre" add -A
    git -C "$standin/pre" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm pre

    NAME="$name" STANDIN="$standin" fixture_assert '
      const { execFileSync } = require("child_process");
      const f = fixtures.loadFixture(dir, process.env.NAME);
      f.source = path.join(process.env.STANDIN, "pre");
      f.basePatch = null; // the stand-in pre-image is already the base-applied tree
      f.sha = execFileSync("git", ["-C", f.source, "rev-parse", "HEAD"], { encoding: "utf8" }).trim();
      const touched = fs.readFileSync(process.env.TEST_ROOT + "/" + process.env.NAME + ".touched", "utf8").trim().split("\n");
      const deleted = [...fs.readFileSync(f.plantPatch, "utf8").matchAll(/^--- a\/(.+)\n\+\+\+ \/dev\/null$/gm)].map(m => m[1]);
      for (const [plant, side] of [[true, "post"], [false, "pre"]]) {
        const work = path.join(process.env.TEST_ROOT, `${process.env.NAME}-${side}`);
        fs.mkdirSync(work);
        fixtures.prepareWorkDir(f, work, { plant });
        for (const file of touched) {
          // A file the patch deletes (`+++ /dev/null`) has no post-image: it must be gone.
          if (side === "post" && deleted.includes(file)) {
            assert.ok(!fs.existsSync(path.join(work, file)), `${process.env.NAME}: ${file} (${side}) should be deleted`);
            continue;
          }
          assert.strictEqual(
            fs.readFileSync(path.join(work, file), "utf8"),
            fs.readFileSync(path.join(process.env.STANDIN, side, file), "utf8"),
            `${process.env.NAME}: ${file} (${side})`);
        }
      }
    '
  done
}

@test "real-fixtures-parallel: the parallel fixture plants two bugs in two files and asks for one subagent per bug (issue #13)" {
  fixture_assert '
    const f = fixtures.loadFixture(dir, "parallel");
    const touched = fs.readFileSync(f.plantPatch, "utf8").match(/^\+\+\+ b\/(.+)$/gm).map(l => l.slice(6)).sort();
    assert.deepStrictEqual(touched, ["anthrouter/http_util.py", "anthrouter/model_router.py"]);
    assert.match(f.prompt, /\bTask\b/);
    assert.match(f.prompt, /subagent/i);
  '
}

@test "real-fixtures-live: with BENCH_LIVE_FIXTURES=1, every pinned fixture passes the offline reliability check (network)" {
  if [ "${BENCH_LIVE_FIXTURES:-}" != 1 ]; then
    skip "set BENCH_LIVE_FIXTURES=1 to clone the pinned repos (network) and run the hidden tests"
  fi
  fixture_assert '
    for (const name of fixtures.listFixtureNames(dir)) {
      const res = fixtures.checkReliability(fixtures.loadFixture(dir, name), { ...process.env, HOME: process.env.REAL_HOME });
      assert.deepStrictEqual(res, { ok: true }, `${name}: ${res.reason}`);
    }
  '
}

@test "fixture-base-patch: base.patch applies to the unpatched and the planted tree, plant.patch on top of it (adminalias, ADR 0017)" {
  src="$TEST_ROOT/src"
  mkdir -p "$src" "$TEST_ROOT/fx/demo/hidden"
  printf 'one\nbug\nthree\n' > "$src/f.txt"
  git -C "$src" init -q
  git -C "$src" add -A
  git -C "$src" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm pre
  sha="$(git -C "$src" rev-parse HEAD)"
  printf '{"source":"%s","sha":"%s","testCommand":"true"}\n' "$src" "$sha" > "$TEST_ROOT/fx/demo/fixture.json"
  echo 'prompt text that is long enough to load as a prompt for a demo fixture' > "$TEST_ROOT/fx/demo/prompt.md"
  echo x > "$TEST_ROOT/fx/demo/hidden/t.py"
  cat > "$TEST_ROOT/fx/demo/base.patch" <<'PATCH'
diff --git a/f.txt b/f.txt
--- a/f.txt
+++ b/f.txt
@@ -1,3 +1,3 @@
 one
-bug
+fixed
 three
PATCH
  cat > "$TEST_ROOT/fx/demo/plant.patch" <<'PATCH'
diff --git a/f.txt b/f.txt
--- a/f.txt
+++ b/f.txt
@@ -1,3 +1,3 @@
 one
-fixed
+bug
 three
PATCH
  node -e '
    const fs = require("fs");
    const assert = require("assert");
    const fixtures = require(process.env.BENCH_DIR + "/lib/fixtures");
    const f = fixtures.loadFixture(process.env.TEST_ROOT + "/fx", "demo");
    assert.ok(f.basePatch.endsWith("base.patch"));
    for (const [plant, want] of [[false, "one\nfixed\nthree\n"], [true, "one\nbug\nthree\n"]]) {
      const work = process.env.TEST_ROOT + "/work-" + plant;
      fs.mkdirSync(work);
      fixtures.prepareWorkDir(f, work, { plant });
      assert.strictEqual(fs.readFileSync(work + "/f.txt", "utf8"), want, `plant=${plant}`);
    }
  '
}

@test "real-fixtures-adminalias: base.patch fixes admin.py and routes the dict options through a registry in config.py, plant.patch reverts the admin fix and drops the one visible test that pins the parser exit" {
  fixture_assert '
    const f = fixtures.loadFixture(dir, "adminalias");
    assert.ok(f.basePatch, "adminalias needs base.patch");
    const files = p => fs.readFileSync(p, "utf8").match(/^\+\+\+ b\/(.+)$/gm).map(l => l.slice(6)).sort();
    assert.deepStrictEqual(files(f.basePatch), ["anthrouter/admin.py", "anthrouter/config.py"]);
    assert.deepStrictEqual(files(f.plantPatch), ["anthrouter/admin.py", "tests/test_config.py"]);
    // The prompt points at the shared parser (the tempting edit) and never at
    // its command-line caller, which the hidden test also checks (ADR 0017).
    assert.match(f.prompt, /_parse_model_aliases_str/);
    assert.doesNotMatch(f.prompt, /parse_args|command.line|\bCLI\b/i);
  '
}

@test "real-fixtures-tierslot: plant.patch keys the tier cache by the conversation alone and removes ADR-0012 and its tests; the prompt names the symptom, not the cache key (ADR 0018)" {
  fixture_assert '
    const f = fixtures.loadFixture(dir, "tierslot");
    assert.strictEqual(f.basePatch, null);
    const patch = fs.readFileSync(f.plantPatch, "utf8");
    const files = patch.match(/^diff --git a\/(\S+)/gm).map(l => l.slice(13)).sort();
    assert.deepStrictEqual(files, [
      "anthrouter/handlers.py", "anthrouter/session_state.py",
      "docs/adr/0012-tier-cache-key-includes-requested-tier.md", "tests/test_handlers.py",
    ]);
    assert.match(patch, /^deleted file mode .*\n.*\n--- a\/docs\/adr\/0012-/m);
    assert.match(patch, /^-def _requested_tier\(/m);
    assert.match(patch, /^\+        tier_key = ctx_key$/m);
    // No reason code: it is the grep key to the comment that explains the replay.
    assert.doesNotMatch(f.prompt, /session_cached|walkback|tool.result|tier_key|_requested_tier|\bADR\b|downgrade|end to end/i);
  '
}

@test "fixture-default-set: retryafter, adminalias and tierslot are off the default set; every other real fixture is on it (ADR 0017, ADR 0018)" {
  fixture_assert '
    const all = fixtures.listFixtureNames(dir);
    const def = fixtures.defaultFixtureNames(dir);
    assert.deepStrictEqual(all.filter(n => !def.includes(n)), ["adminalias", "retryafter", "tierslot"]);
    assert.ok(def.includes("suitecheck") && def.includes("parallel"));
  '
}
