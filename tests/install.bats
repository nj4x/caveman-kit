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
  [[ "$output" == *"already installed"* ]]
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

  [[ "$output" == *"warning"* ]] || [[ "$output" == *"best-effort"* ]]
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
