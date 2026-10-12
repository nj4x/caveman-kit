#!/usr/bin/env bats
# Unit tests of the config-isolation module: buildArmConfig and preflight
# options (hooksDir, env, requireText, forbidText).

load helpers

setup() { bench_setup; }
teardown() { bench_teardown; }

@test "preflight-options: buildArmConfig defaults hooks to <kitDir>/hooks" {
  node_assert '
    const c = isolation.buildArmConfig({ name: "full", mode: "full" }, { kitDir: process.env.KIT_DIR });
    assert.strictEqual(c.hooksDir, path.join(process.env.KIT_DIR, "hooks"));
    const s = JSON.parse(fs.readFileSync(c.settingsPath, "utf8"));
    assert.ok(s.hooks.SessionStart[0].hooks[0].command.includes(c.hooksDir + "/caveman-activate.js"));
    assert.strictEqual(fs.readFileSync(c.flagPath, "utf8"), "full");
    assert.strictEqual(fs.statSync(path.dirname(c.dir)).mode & 0o777, 0o700);
  '
}

@test "preflight-options: hooksDir overrides the kit hooks in every hook command" {
  alt="$TEST_ROOT/alt-hooks"
  mkdir -p "$alt"
  cp "$KIT_DIR"/hooks/* "$alt/"
  export ALT_HOOKS="$alt"

  node_assert '
    const c = isolation.buildArmConfig({ name: "ultra", mode: "ultra" }, { kitDir: process.env.KIT_DIR, hooksDir: process.env.ALT_HOOKS });
    const s = JSON.parse(fs.readFileSync(c.settingsPath, "utf8"));
    for (const ev of ["SessionStart", "SubagentStart", "UserPromptSubmit"]) {
      const cmd = s.hooks[ev][0].hooks[0].command;
      assert.ok(cmd.includes(process.env.ALT_HOOKS + "/"), cmd);
      assert.ok(!cmd.includes(process.env.KIT_DIR + "/hooks/"), cmd);
    }
    assert.ok(isolation.preflight(c).context.includes("CAVEMAN MODE ACTIVE — level: ultra"));
  '
}

@test "preflight-options: buildArmConfig rejects a hooksDir missing a kit hook" {
  mkdir -p "$TEST_ROOT/empty-hooks"
  export EMPTY_HOOKS="$TEST_ROOT/empty-hooks"

  node_assert '
    assert.throws(() => isolation.buildArmConfig({ name: "full", mode: "full" }, { hooksDir: process.env.EMPTY_HOOKS }), /hook script missing/);
  '
}

@test "preflight-options: env option is the base env; CAVEMAN_* is dropped, arm env applied" {
  node_assert '
    const env = { PATH: process.env.PATH, HOME: process.env.HOME, ANTHROPIC_API_KEY: "k", CAVEMAN_CONTEXT_DIET: "1", CAVEMAN_DEFAULT_MODE: "ultra", CLAUDE_CONFIG_DIR: "/real", KEEP_ME: "yes" };
    const skillRoot = process.env.HOME + "/.claude";
    const c = isolation.buildArmConfig({ name: "full", mode: "full", env: { CAVEMAN_CONTEXT_DIET: "0" } }, { kitDir: process.env.KIT_DIR, env, skillRoot });
    assert.strictEqual(c.env.KEEP_ME, "yes");
    assert.strictEqual(c.env.ANTHROPIC_API_KEY, "k");
    assert.strictEqual(c.env.CAVEMAN_CONTEXT_DIET, "0");
    assert.strictEqual(c.env.CAVEMAN_DEFAULT_MODE, undefined);
    assert.strictEqual(c.env.CLAUDE_CONFIG_DIR, c.configDir);
    assert.strictEqual(c.env.CLAUDE_PLUGIN_ROOT, c.pluginRoot);
    const bare = isolation.buildArmConfig({ name: "bare", mode: "off" }, { kitDir: process.env.KIT_DIR, env, skillRoot });
    assert.strictEqual(bare.env.CAVEMAN_DEFAULT_MODE, "off");
    assert.strictEqual(fs.readFileSync(bare.flagPath, "utf8"), "off");
  '
}

@test "preflight-options: requireText passes when present and aborts when absent" {
  node_assert '
    const c = isolation.buildArmConfig({ name: "full", mode: "full" }, { kitDir: process.env.KIT_DIR });
    assert.ok(isolation.preflight(c, { requireText: "level: full" }).context);
    assert.ok(isolation.preflight(c, { requireText: ["level: full", "Respond terse"] }).context);
    assert.throws(() => isolation.preflight(c, { requireText: ["level: full", "CONTEXT DIET"] }), /lacks required text: "CONTEXT DIET"/);
  '
}

@test "preflight-options: forbidText aborts when present and passes when absent" {
  node_assert '
    const c = isolation.buildArmConfig({ name: "full", mode: "full" }, { kitDir: process.env.KIT_DIR });
    assert.ok(isolation.preflight(c, { forbidText: "CONTEXT DIET" }).context);
    assert.throws(() => isolation.preflight(c, { forbidText: ["CONTEXT DIET", "level: full"] }), /contains forbidden text: "level: full"/);
  '
}

@test "preflight: bare arm injects nothing and keeps its seeded off flag" {
  node_assert '
    const c = isolation.buildArmConfig({ name: "bare", mode: "off" }, { kitDir: process.env.KIT_DIR });
    assert.strictEqual(isolation.preflight(c).context, "");
    assert.strictEqual(fs.readFileSync(c.flagPath, "utf8"), "off");
  '
}

@test "preflight-empty: a mode arm with empty context throws" {
  hooks="$TEST_ROOT/silent-hooks"
  mkdir -p "$hooks"
  cp "$KIT_DIR"/hooks/*.js "$hooks/"
  printf '%s\n' "process.exit(0);" > "$hooks/caveman-activate.js"
  export SILENT_HOOKS="$hooks"

  node_assert '
    const c = isolation.buildArmConfig({ name: "lite", mode: "lite" }, { hooksDir: process.env.SILENT_HOOKS });
    assert.throws(() => isolation.preflight(c), /preflight lite: mode lite injected empty context/);
  '
}

@test "preflight: a mode arm whose context names another level aborts" {
  hooks="$TEST_ROOT/wrong-level-hooks"
  mkdir -p "$hooks"
  cp "$KIT_DIR"/hooks/*.js "$hooks/"
  printf '%s\n' 'process.stdout.write(JSON.stringify({hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:"CAVEMAN MODE ACTIVE — level: ultra"}}));' > "$hooks/caveman-activate.js"
  export WRONG_HOOKS="$hooks"

  node_assert '
    const c = isolation.buildArmConfig({ name: "lite", mode: "lite" }, { hooksDir: process.env.WRONG_HOOKS });
    assert.throws(() => isolation.preflight(c), /preflight lite: context is not for mode lite/);
  '
}

@test "estimate-confirm: on a TTY y/yes proceed; n, empty and end of input abort" {
  node -e '
    const { PassThrough } = require("stream");
    const assert = require("assert");
    const { confirm } = require(process.env.BENCH_DIR + "/lib/estimate");
    const ask = (answer, end) => {
      const stdin = new PassThrough();
      stdin.isTTY = true;
      const p = confirm({ yes: false, stdin, stderr: new PassThrough() });
      if (end) stdin.end(); else stdin.write(answer + "\n");
      return p;
    };
    // An unsettled promise lets node exit 0 silently; require the sentinel.
    let done = false;
    process.on("exit", code => { if (!done && code === 0) { console.error("confirm test did not finish"); process.exitCode = 1; } });
    (async () => {
      assert.strictEqual((await ask("y")).proceed, true);
      assert.strictEqual((await ask("YES")).proceed, true);
      assert.deepStrictEqual(await ask("n"), { proceed: false, reason: "aborted by user" });
      assert.strictEqual((await ask("")).proceed, false);
      assert.strictEqual((await ask(null, true)).proceed, false);
      assert.strictEqual((await confirm({ yes: true })).proceed, true);
      const noTty = await confirm({ yes: false, stdin: { isTTY: false } });
      assert.strictEqual(noTty.proceed, false);
      assert.match(noTty.reason, /--yes/);
      done = true;
    })().catch(e => { console.error(e); process.exit(1); });
  '
}

@test "auth: API key first, then a readable credentials file, else an error naming both" {
  node_assert '
    const home = process.env.HOME;
    assert.deepStrictEqual(isolation.resolveAuth({ HOME: home, ANTHROPIC_API_KEY: "k" }), { kind: "api-key" });
    assert.throws(() => isolation.resolveAuth({ HOME: home }), e => /ANTHROPIC_API_KEY/.test(e.message) && /\.credentials\.json/.test(e.message));
    fs.writeFileSync(home + "/.claude/.credentials.json", "{}");
    assert.deepStrictEqual(isolation.resolveAuth({ HOME: home }), { kind: "credentials", path: home + "/.claude/.credentials.json" });
    fs.chmodSync(home + "/.claude/.credentials.json", 0);
    if (process.getuid() !== 0) assert.throws(() => isolation.resolveAuth({ HOME: home }), /ANTHROPIC_API_KEY/);
  '
}

@test "skill root: CAVEMAN_BENCH_SKILL_ROOT, then manifest pluginRoot, then the real config dir" {
  mkdir -p "$TEST_ROOT/override/skills/caveman" "$TEST_ROOT/manifest-root/skills/caveman" "$HOME/.caveman-kit"
  touch "$TEST_ROOT/override/skills/caveman/SKILL.md" "$TEST_ROOT/manifest-root/skills/caveman/SKILL.md"

  node_assert '
    const home = process.env.HOME, root = process.env.TEST_ROOT;
    assert.strictEqual(isolation.resolveSkillRoot({ HOME: home }), home + "/.claude");
    fs.writeFileSync(home + "/.caveman-kit/manifest.json", JSON.stringify({ pluginRoot: root + "/manifest-root" }));
    assert.strictEqual(isolation.resolveSkillRoot({ HOME: home }), root + "/manifest-root");
    assert.strictEqual(isolation.resolveSkillRoot({ HOME: home, CAVEMAN_BENCH_SKILL_ROOT: root + "/override" }), root + "/override");
    assert.throws(() => isolation.resolveSkillRoot({ HOME: root + "/nohome" }), /SKILL.md not found/);
  '
}

@test "temp roots are removed by cleanupTempRoots and on process exit" {
  node_assert '
    const c = isolation.buildArmConfig({ name: "full", mode: "full" }, { kitDir: process.env.KIT_DIR });
    const root = path.dirname(c.dir);
    assert.ok(fs.existsSync(root));
    isolation.cleanupTempRoots();
    assert.ok(!fs.existsSync(root));
    isolation.buildArmConfig({ name: "full", mode: "full" }, { kitDir: process.env.KIT_DIR });
  '
  [ "$(leftover_temp_dirs)" -eq 0 ]
}
