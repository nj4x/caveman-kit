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

@test "real-fixtures-format: bench/fixtures holds bigfile, noisylog, reuse, rootcause and each loads" {
  fixture_assert '
    assert.deepStrictEqual(fixtures.listFixtureNames(dir), ["bigfile", "noisylog", "reuse", "rootcause"]);
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
      bigfile: "https://github.com/nj4x/anthrouter.git",
      rootcause: "https://github.com/nj4x/anthrouter.git",
      noisylog: "https://github.com/nj4x/anthrouter.git",
      reuse: "https://github.com/nj4x/skills-dev.git",
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
  for name in bigfile noisylog reuse rootcause; do
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
      f.sha = execFileSync("git", ["-C", f.source, "rev-parse", "HEAD"], { encoding: "utf8" }).trim();
      const touched = fs.readFileSync(process.env.TEST_ROOT + "/" + process.env.NAME + ".touched", "utf8").trim().split("\n");
      for (const [plant, side] of [[true, "post"], [false, "pre"]]) {
        const work = path.join(process.env.TEST_ROOT, `${process.env.NAME}-${side}`);
        fs.mkdirSync(work);
        fixtures.prepareWorkDir(f, work, { plant });
        for (const file of touched) {
          assert.strictEqual(
            fs.readFileSync(path.join(work, file), "utf8"),
            fs.readFileSync(path.join(process.env.STANDIN, side, file), "utf8"),
            `${process.env.NAME}: ${file} (${side})`);
        }
      }
    '
  done
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
