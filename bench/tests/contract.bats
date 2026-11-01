#!/usr/bin/env bats
# bench/contract.js and bench/lib/rules.js (ADR 0026 decision 3). The real
# hook runs; `npx` is a stub (stub-contract/npx) and the upstream remote is a
# local git repo, so no network and no API calls.

setup() {
  export KIT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
  TEST_ROOT="$(mktemp -d)"
  export TEST_ROOT
  export HOME="$TEST_ROOT/home"
  export TMPDIR="$TEST_ROOT/tmp"
  mkdir -p "$HOME" "$TMPDIR"
  export PATH="$KIT_DIR/bench/tests/stub-contract:$PATH"
  export STUB_NPX_LOG="$TEST_ROOT/npx.log"
  export STUB_SKILLS_SRC="$TEST_ROOT/upstream-skills"
  unset CLAUDE_CONFIG_DIR CLAUDE_PLUGIN_ROOT CAVEMAN_DEFAULT_MODE STUB_NPX_EXIT STUB_NPX_VERSION_EXIT STUB_BREAK_REMOTE

  # Upstream remote with release tags.
  export REMOTE="$TEST_ROOT/remote"
  git init -q "$REMOTE"
  git -C "$REMOTE" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
  git -C "$REMOTE" tag v3.1.0
  git -C "$REMOTE" tag v3.2.0
  export CAVEMAN_KIT_SKILL_REMOTE="$REMOTE"

  mkdir -p "$STUB_SKILLS_SRC/caveman" "$STUB_SKILLS_SRC/ultracave"
  cat > "$STUB_SKILLS_SRC/caveman/SKILL.md" <<'SKILL'
---
name: caveman
---

| **lite** | Lite row unique |

Respond terse like smart caveman.

Shared rule line.

- full: example full
- lite: example lite
SKILL
  cat > "$STUB_SKILLS_SRC/ultracave/SKILL.md" <<'SKILL'
---
name: ultracave
---

Shared rule line.

Ultracave strips grammar. Payload only.
SKILL
}

teardown() { rm -rf "$TEST_ROOT"; }

contract() { run node "$KIT_DIR/bench/contract.js" "$@" < /dev/null; }

leftover() { find "$TMPDIR" -maxdepth 1 -name 'caveman-contract-*' | wc -l | tr -d ' '; }

@test "rules: distinguishing lines skip hook-dropped lines and shared lines" {
  run node -e '
    const r = require(process.argv[1]);
    const c = r.readSkillBody(process.argv[2]), u = r.readSkillBody(process.argv[3]);
    const l = r.distinguishingLines(c, u);
    if (l.caveman !== "Respond terse like smart caveman.") throw new Error(l.caveman);
    if (l.ultracave !== "Ultracave strips grammar. Payload only.") throw new Error(l.ultracave);
  ' "$KIT_DIR/bench/lib/rules.js" "$STUB_SKILLS_SRC/caveman/SKILL.md" "$STUB_SKILLS_SRC/ultracave/SKILL.md"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "rules: a skill with no distinguishing line throws, naming it" {
  run node -e '
    const r = require(process.argv[1]);
    try { r.distinguishingLines("A\nB\n| **ultra** | x |\n", "A\nB\nC\n"); } catch (e) { console.log(e.message); process.exit(0); }
    process.exit(1);
  ' "$KIT_DIR/bench/lib/rules.js"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no distinguishing line for: caveman"* ]] || false
}

@test "rules: readSkillBody rejects unterminated frontmatter and an empty body" {
  printf -- '---\nname: x\n' > "$TEST_ROOT/unterm.md"
  printf -- '---\nname: x\n---\n\n  \n' > "$TEST_ROOT/empty.md"
  run node -e '
    const r = require(process.argv[1]);
    for (const f of process.argv.slice(2)) if (r.readSkillBody(f) !== null) throw new Error(f);
  ' "$KIT_DIR/bench/lib/rules.js" "$TEST_ROOT/unterm.md" "$TEST_ROOT/empty.md" "$TEST_ROOT/absent.md"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "contract: exit 0 at the newest tag, scrubbed env, caller CLAUDE_CONFIG_DIR untouched" {
  export CLAUDE_CONFIG_DIR="$TEST_ROOT/real-config"
  mkdir -p "$CLAUDE_CONFIG_DIR"
  export CAVEMAN_DEFAULT_MODE=off
  contract
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"tag: v3.2.0"* ]] || false
  [ -z "$(ls -A "$CLAUDE_CONFIG_DIR")" ]
  grep -q 'skills add JuliusBrussee/caveman@v3.2.0 --skill caveman --skill ultracave' "$STUB_NPX_LOG"
  grep -q "CCD=$TMPDIR/caveman-contract-[^/]*/home/.claude\$" "$STUB_NPX_LOG"
  grep -q "HOME=$TMPDIR/caveman-contract-[^/]*/home|" "$STUB_NPX_LOG"
  [ "$(leftover)" -eq 0 ]
}

@test "contract: checkEnv rejects a plugin root that differs from the install target" {
  run node -e '
    const c = require(process.argv[1]);
    const env = c.buildEnv({ CLAUDE_CONFIG_DIR: "/real", CAVEMAN_X: "1", PATH: "/bin" }, "/t/home");
    if (env.CAVEMAN_X || env.CLAUDE_CONFIG_DIR !== "/t/home/.claude" || env.CLAUDE_PLUGIN_ROOT !== env.CLAUDE_CONFIG_DIR) throw new Error("scrub");
    if (c.checkEnv(env, "/t") !== null) throw new Error("same path rejected");
    if (!c.checkEnv(Object.assign({}, env, { CLAUDE_PLUGIN_ROOT: "/t/other" }), "/t")) throw new Error("differ accepted");
    if (!c.checkEnv(env, "/elsewhere")) throw new Error("outside accepted");
  ' "$KIT_DIR/bench/contract.js"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "contract: --tag invalid, absent upstream, or remote unreachable exits 2 naming the tag" {
  contract --tag v3.2
  [ "$status" -eq 2 ]; [[ "$output" == *'"v3.2"'* ]] || false
  contract --tag v9.9.9
  [ "$status" -eq 2 ]; [[ "$output" == *"v9.9.9 not found upstream"* ]] || false
  export CAVEMAN_KIT_SKILL_REMOTE="$TEST_ROOT/nowhere"
  contract --tag v3.1.0
  [ "$status" -eq 2 ]; [[ "$output" == *"v3.1.0: upstream remote unreachable"* ]] || false
  [ "$(leftover)" -eq 0 ]
  [ ! -f "$STUB_NPX_LOG" ]
}

@test "contract: failed tag lookup or failed CLI probe exits 2" {
  export CAVEMAN_KIT_SKILL_REMOTE="$TEST_ROOT/nowhere"
  contract
  [ "$status" -eq 2 ]; [[ "$output" == *"tag lookup failed"* ]] || false
  export CAVEMAN_KIT_SKILL_REMOTE="$REMOTE"
  export STUB_NPX_VERSION_EXIT=1
  contract --tag v3.1.0
  [ "$status" -eq 2 ]; [[ "$output" == *"npx skills --version failed"* ]] || false
  [ "$(leftover)" -eq 0 ]
}

@test "contract: one skill missing or unusable after install exits 1 naming it" {
  rm -r "$STUB_SKILLS_SRC/ultracave"
  contract
  [ "$status" -eq 1 ]; [[ "$output" == *"ultracave (missing)"* ]] || false
  mkdir -p "$STUB_SKILLS_SRC/ultracave"
  printf -- '---\nname: ultracave\n---\n\n' > "$STUB_SKILLS_SRC/ultracave/SKILL.md"
  contract
  [ "$status" -eq 1 ]; [[ "$output" == *"ultracave (unusable)"* ]] || false
  [ "$(leftover)" -eq 0 ]
}

@test "contract: neither skill present decides 1 or 2 by the exit code and a repeat lookup" {
  rm -r "$STUB_SKILLS_SRC"
  contract
  [ "$status" -eq 1 ]; [[ "$output" == *"exited 0"*"installed neither skill"* ]] || false
  export STUB_NPX_EXIT=3
  contract
  [ "$status" -eq 1 ]; [[ "$output" == *"upstream reachable"* ]] || false; [[ "$output" == *"clone error tail"* ]] || false
  export STUB_BREAK_REMOTE="$REMOTE"
  contract
  [ "$status" -eq 2 ]; [[ "$output" == *"repeat tag lookup failed"* ]] || false; [[ "$output" == *"clone error tail"* ]] || false
  [ "$(leftover)" -eq 0 ]
}

@test "contract: both usable with a non-zero install exit warns and continues" {
  export STUB_NPX_EXIT=5
  contract
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"warning: install_skills exited 5"* ]] || false
}

@test "contract: a context holding the other skill's line exits 1 naming the mode" {
  # The caveman line is also a kit example heading, which the hook appends to
  # the ultra context too.
  printf -- '---\nname: caveman\n---\n\nExample "How do you debug a race condition?"\n\nShared rule line.\n' > "$STUB_SKILLS_SRC/caveman/SKILL.md"
  contract
  [ "$status" -eq 1 ]
  [[ "$output" == *"ultra: contains caveman line"* ]] || { echo "$output"; false; }
  [[ "$output" != *"lite:"* ]] || false
  [ "$(leftover)" -eq 0 ]
}

@test "contract: a skill with no distinguishing line exits 1" {
  cp "$STUB_SKILLS_SRC/caveman/SKILL.md" "$STUB_SKILLS_SRC/ultracave/SKILL.md"
  contract
  [ "$status" -eq 1 ]; [[ "$output" == *"no distinguishing line for: caveman, ultracave"* ]] || false
}
