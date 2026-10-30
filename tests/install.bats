#!/usr/bin/env bats
# caveman-kit install.bats
#
# Tests for install.sh: fresh install, re-run blocking, rollback on failure, uninstall cleanup.

setup_file() {
  # Create a bare git clone for bootstrap tests to use
  export TEST_BARE_REPO="$BATS_TMPDIR/caveman-kit-bare.git"
  git init --bare "$TEST_BARE_REPO"
  git -C "$BATS_TEST_DIRNAME/.." push "$TEST_BARE_REPO" main:main 2>/dev/null || true
}

teardown_file() {
  rm -rf "$TEST_BARE_REPO"
}

load helpers/skills

setup() {
  # Isolate each test with a fresh HOME
  export TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  export CAVEMAN_KIT_INSTALL_DIR="$BATS_TMPDIR/caveman-kit-install"
  
  # Create minimal Claude Code config structure
  mkdir -p "$CLAUDE_CONFIG_DIR"
  mkdir -p "$CLAUDE_CONFIG_DIR/skills"
  
  # Create a minimal settings.json with hooks array
  cat > "$CLAUDE_CONFIG_DIR/settings.json" <<'SETTINGS'
{
  "hooks": {}
}
SETTINGS

  # Create a minimal statusline.sh
  cat > "$CLAUDE_CONFIG_DIR/statusline.sh" <<'STATUSLINE'
#!/usr/bin/env bash
echo "statusline"
STATUSLINE
  chmod +x "$CLAUDE_CONFIG_DIR/statusline.sh"

  # Hermetic skills: a fake upstream with release tags and a stub npx.
  export KIT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  make_upstream v3.0.0 v4.0.0 v4.0.1 v5.0.0-rc1
  install_npx_stub
}

teardown() {
  rm -rf "$TEST_HOME"
  rm -rf "$CAVEMAN_KIT_INSTALL_DIR"
  rm -rf "$HOME/.caveman-kit"
}

@test "fresh install creates manifest.json with completed: true" {
  # Pre-seed the caveman skill so we skip the npx call
  mkdir -p "$CLAUDE_CONFIG_DIR/skills/caveman"
  cat > "$CLAUDE_CONFIG_DIR/skills/caveman/SKILL.md" <<'SKILL'
---
name: caveman
---
# Caveman Skill
SKILL

  # Run install from the copy in CAVEMAN_KIT_INSTALL_DIR
  mkdir -p "$CAVEMAN_KIT_INSTALL_DIR"
  cp -r "$BATS_TEST_DIRNAME/.."/* "$CAVEMAN_KIT_INSTALL_DIR/"
  bash "$CAVEMAN_KIT_INSTALL_DIR/install.sh"

  # Verify manifest exists and has completed: true
  [ -f "$HOME/.caveman-kit/manifest.json" ]
  
  # Check completed field
  run node -e "console.log(JSON.parse(require('fs').readFileSync('$HOME/.caveman-kit/manifest.json', 'utf8')).completed)"
  [ "$output" = "true" ]
  
  # Check key fields exist
  run node -e "const m=JSON.parse(require('fs').readFileSync('$HOME/.caveman-kit/manifest.json','utf8')); console.log(m.settingsBackup !== undefined)"
  [ "$output" = "true" ]
}

@test "re-run after successful install fails with already installed" {
  # Pre-seed the caveman skill
  mkdir -p "$CLAUDE_CONFIG_DIR/skills/caveman"
  cat > "$CLAUDE_CONFIG_DIR/skills/caveman/SKILL.md" <<'SKILL'
---
name: caveman
---
# Caveman Skill
SKILL

  # First install
  mkdir -p "$CAVEMAN_KIT_INSTALL_DIR"
  cp -r "$BATS_TEST_DIRNAME/.."/* "$CAVEMAN_KIT_INSTALL_DIR/"
  bash "$CAVEMAN_KIT_INSTALL_DIR/install.sh"
  
  # Second install should fail
  run bash "$CAVEMAN_KIT_INSTALL_DIR/install.sh" 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"already installed"* ]] || false
}

@test "simulated mid-install failure leaves NO KIT_HOME behind (rollback)" {
  # Pre-seed the caveman skill
  mkdir -p "$CLAUDE_CONFIG_DIR/skills/caveman"
  cat > "$CLAUDE_CONFIG_DIR/skills/caveman/SKILL.md" <<'SKILL'
---
name: caveman
---
# Caveman Skill
SKILL

  # Create install dir
  mkdir -p "$CAVEMAN_KIT_INSTALL_DIR"
  cp -r "$BATS_TEST_DIRNAME/.."/* "$CAVEMAN_KIT_INSTALL_DIR/"
  
  # Patch install.sh to fail mid-way (after mkdir, before manifest write)
  # We'll simulate by making settings-patch.js fail
  cat > "$CAVEMAN_KIT_INSTALL_DIR/lib/settings-patch.js" <<'PATCHJS'
// Simulated failure
process.exit(1);
PATCHJS

  # Run install - should fail and rollback
  run bash "$CAVEMAN_KIT_INSTALL_DIR/install.sh" 2>&1 || true
  
  # Verify KIT_HOME was cleaned up (rollback worked)
  [ ! -d "$HOME/.caveman-kit" ]
}

@test "uninstall.sh with missing manifest does best-effort cleanup" {
  mkdir -p "$CAVEMAN_KIT_INSTALL_DIR"
  cp -r "$BATS_TEST_DIRNAME/.."/* "$CAVEMAN_KIT_INSTALL_DIR/"

  # Simulate a partial install: KIT_HOME exists with no manifest.json
  mkdir -p "$HOME/.caveman-kit/hooks"

  run bash "$CAVEMAN_KIT_INSTALL_DIR/uninstall.sh" 2>&1

  [[ "$output" == *"warning"* ]] || [[ "$output" == *"best-effort"* ]] || false
  [ ! -d "$HOME/.caveman-kit" ]
}

@test "uninstall.sh removes KIT_HOME and strips settings.json markers" {
  # Pre-seed the caveman skill
  mkdir -p "$CLAUDE_CONFIG_DIR/skills/caveman"
  cat > "$CLAUDE_CONFIG_DIR/skills/caveman/SKILL.md" <<'SKILL'
---
name: caveman
---
# Caveman Skill
SKILL

  # Install first
  mkdir -p "$CAVEMAN_KIT_INSTALL_DIR"
  cp -r "$BATS_TEST_DIRNAME/.."/* "$CAVEMAN_KIT_INSTALL_DIR/"
  bash "$CAVEMAN_KIT_INSTALL_DIR/install.sh"
  
  # Verify install succeeded
  [ -f "$HOME/.caveman-kit/manifest.json" ]
  
  # Run uninstall
  bash "$CAVEMAN_KIT_INSTALL_DIR/uninstall.sh"
  
  # Verify KIT_HOME removed
  [ ! -d "$HOME/.caveman-kit" ]
  
  # Verify settings.json markers removed (no caveman references)
  run grep -c "caveman" "$CLAUDE_CONFIG_DIR/settings.json" || true
  # Should be 0 or grep returns non-zero
  [ "$status" -eq 0 ] || [ "$output" = "0" ]
}

# ---- skill install cases (ADR 0020 decision 1 table, ADR 0021) ----

seed_caveman() {
  mkdir -p "$CLAUDE_CONFIG_DIR/skills/caveman"
  printf -- '---\nname: caveman\n---\n# Caveman Skill\n' > "$CLAUDE_CONFIG_DIR/skills/caveman/SKILL.md"
}

seed_ultracave() {
  mkdir -p "$CLAUDE_CONFIG_DIR/skills/ultracave"
  printf -- '---\nname: ultracave\n---\n# Ultracave\n' > "$CLAUDE_CONFIG_DIR/skills/ultracave/SKILL.md"
}

run_install() {
  run bash "$KIT_DIR/install.sh"
}

@test "both skills missing: installs caveman then ultracave at the newest release tag" {
  run_install
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "$HOME/npx.log")" = "caveman JuliusBrussee/caveman@v4.0.1" ]
  [ "$(sed -n 2p "$HOME/npx.log")" = "ultracave JuliusBrussee/caveman@v4.0.1" ]
  [ "$(manifest_get skillInstalledByKit)" = "true" ]
  [ "$(manifest_get ultracaveInstalledByKit)" = "true" ]
  [ "$(manifest_get skillRef)" = '"v4.0.1"' ]
}

@test "caveman present, ultracave missing: installs ultracave only" {
  seed_caveman
  run_install
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$HOME/npx.log" | tr -d ' ')" = "1" ]
  grep -q '^ultracave ' "$HOME/npx.log"
  [ "$(manifest_get skillInstalledByKit)" = "false" ]
  [ "$(manifest_get ultracaveInstalledByKit)" = "true" ]
  [ "$(manifest_get skillRef)" = '"v4.0.1"' ]
}

@test "caveman missing, ultracave present: installs caveman only, ultracave not owned" {
  seed_ultracave
  run_install
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$HOME/npx.log" | tr -d ' ')" = "1" ]
  grep -q '^caveman ' "$HOME/npx.log"
  [ "$(manifest_get skillInstalledByKit)" = "true" ]
  [ "$(manifest_get ultracaveInstalledByKit)" = "false" ]
}

@test "both present: no npx call, nothing owned, skillRef null" {
  seed_caveman
  seed_ultracave
  run_install
  [ "$status" -eq 0 ]
  [ ! -s "$HOME/npx.log" ]
  [ "$(manifest_get ultracaveInstalledByKit)" = "false" ]
  [ "$(manifest_get skillRef)" = "absent" ]
}

@test "--no-install-skill with caveman present: ultracave not installed, recorded false" {
  seed_caveman
  run bash "$KIT_DIR/install.sh" --no-install-skill
  [ "$status" -eq 0 ]
  [ ! -s "$HOME/npx.log" ]
  [ "$(manifest_get ultracaveInstalledByKit)" = "false" ]
}

@test "a partial ultracave directory without SKILL.md counts as missing and is installed over" {
  seed_caveman
  mkdir -p "$CLAUDE_CONFIG_DIR/skills/ultracave"
  echo junk > "$CLAUDE_CONFIG_DIR/skills/ultracave/README.md"
  run_install
  [ "$status" -eq 0 ]
  grep -q '^ultracave ' "$HOME/npx.log"
  [ "$(manifest_get ultracaveInstalledByKit)" = "true" ]
}

@test "failed ultracave call does not abort: warns with a pinned command, records null" {
  seed_caveman
  export NPX_FAIL=ultracave
  run_install
  [ "$status" -eq 0 ]
  [[ "$output" == *"npx skills add JuliusBrussee/caveman@v4.0.1 --skill ultracave"* ]] || false
  [ "$(manifest_get ultracaveInstalledByKit)" = "null" ]
  [ "$(manifest_get completed)" = "true" ]
}

@test "zero-exit ultracave call that leaves no SKILL.md counts as failed: null" {
  seed_caveman
  export NPX_NOWRITE=ultracave
  run_install
  [ "$status" -eq 0 ]
  [ "$(manifest_get ultracaveInstalledByKit)" = "null" ]
}

@test "failed caveman call aborts and rolls back" {
  export NPX_FAIL=caveman
  run_install
  [ "$status" -ne 0 ]
  [ ! -d "$HOME/.caveman-kit" ]
}

@test "tag lookup failure with caveman present is soft: ultracave null, install completes" {
  seed_caveman
  export CAVEMAN_KIT_SKILL_REMOTE="file://$HOME/nope.git"
  run_install
  [ "$status" -eq 0 ]
  [[ "$output" == *"<tag>"* ]] || false
  [[ "$output" == *"https://github.com/JuliusBrussee/caveman/releases"* ]] || false
  [ "$(manifest_get ultracaveInstalledByKit)" = "null" ]
  [ ! -s "$HOME/npx.log" ]
}

@test "tag lookup failure with caveman missing aborts with a placeholder command" {
  export CAVEMAN_KIT_SKILL_REMOTE="file://$HOME/nope.git"
  run_install
  [ "$status" -ne 0 ]
  [[ "$output" == *"<tag>"* ]] || false
  [ ! -d "$HOME/.caveman-kit" ]
}

@test "an upstream with no vX.Y.Z tags counts as a lookup failure" {
  make_upstream v5.0.0-rc1 nightly
  seed_caveman
  run_install
  [ "$status" -eq 0 ]
  [ "$(manifest_get ultracaveInstalledByKit)" = "null" ]
}

@test "CAVEMAN_KIT_SKILL_REF pins the tag and is recorded as skillRefOverride" {
  export CAVEMAN_KIT_SKILL_REF=v4.0.0
  run_install
  [ "$status" -eq 0 ]
  grep -q 'caveman@v4.0.0' "$HOME/npx.log"
  [ "$(manifest_get skillRef)" = '"v4.0.0"' ]
  [ "$(manifest_get skillRefOverride)" = '"v4.0.0"' ]
}

@test "CAVEMAN_KIT_SKILL_REF below v3.1.0 or not a tag is rejected (soft with caveman present)" {
  seed_caveman
  for bad in v3.0.0 main v4.0 4.0.1; do
    rm -rf "$HOME/.caveman-kit"
    : > "$HOME/npx.log"
    export CAVEMAN_KIT_SKILL_REF="$bad"
    run_install
    [ "$status" -eq 0 ]
    [[ "$output" == *"rejected"* ]] || false
    [ "$(manifest_get ultracaveInstalledByKit)" = "null" ]
    [ ! -s "$HOME/npx.log" ]
  done
}

@test "install.sh no longer carries a pin line the pre-change update.sh could grep" {
  run grep -q 'SKILL_SOURCE=' "$KIT_DIR/install.sh"
  [ "$status" -eq 1 ]
  run grep -rq 'SKILL_SOURCE=' "$KIT_DIR/lib"
  [ "$status" -eq 1 ]
}

# ---- uninstall branches for ultracave (ADR 0020 decision 2) ----

uninstall_with_flag() {
  seed_caveman
  run_install
  [ "$status" -eq 0 ]
  if [ "$1" = "absent" ]; then
    node "$KIT_DIR/lib/manifest.js" unset "$HOME/.caveman-kit/manifest.json" ultracaveInstalledByKit
  else
    node "$KIT_DIR/lib/manifest.js" set "$HOME/.caveman-kit/manifest.json" ultracaveInstalledByKit "$1"
  fi
  run bash "$KIT_DIR/uninstall.sh"
  [ "$status" -eq 0 ]
}

@test "uninstall removes ultracave when the flag is true" {
  uninstall_with_flag true
  [ ! -e "$CLAUDE_CONFIG_DIR/skills/ultracave" ]
}

@test "uninstall removes a partial ultracave directory when the flag is null" {
  seed_caveman
  export NPX_NOWRITE=ultracave
  run_install
  mkdir -p "$CLAUDE_CONFIG_DIR/skills/ultracave"
  echo junk > "$CLAUDE_CONFIG_DIR/skills/ultracave/README.md"
  [ "$(manifest_get ultracaveInstalledByKit)" = "null" ]
  run bash "$KIT_DIR/uninstall.sh"
  [ "$status" -eq 0 ]
  [ ! -e "$CLAUDE_CONFIG_DIR/skills/ultracave" ]
}

@test "uninstall leaves ultracave alone when the flag is false" {
  uninstall_with_flag false
  [ -f "$CLAUDE_CONFIG_DIR/skills/ultracave/SKILL.md" ]
}

@test "uninstall leaves ultracave alone for a legacy manifest without the field" {
  uninstall_with_flag absent
  [ -f "$CLAUDE_CONFIG_DIR/skills/ultracave/SKILL.md" ]
}

@test "caveman missing with --no-install-skill aborts before any skill call" {
  run bash "$KIT_DIR/install.sh" --no-install-skill
  [ "$status" -ne 0 ]
  [[ "$output" == *"caveman skill not found"* ]] || false
  [ ! -s "$HOME/npx.log" ]
}

@test "lookup failure with caveman missing aborts before any skill call" {
  export CAVEMAN_KIT_SKILL_REMOTE="file://$HOME/nope.git"
  run_install
  [ "$status" -ne 0 ]
  [ ! -s "$HOME/npx.log" ]
}

@test "a multi-line CAVEMAN_KIT_SKILL_REF is rejected" {
  seed_caveman
  export CAVEMAN_KIT_SKILL_REF=$'v4.0.1\nx'
  run_install
  [ "$status" -eq 0 ]
  [[ "$output" == *"rejected"* ]] || false
  [ "$(manifest_get skillRefOverride)" = "absent" ]
}
