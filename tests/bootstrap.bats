#!/usr/bin/env bats
# caveman-kit bootstrap.bats
#
# Tests for bootstrap.sh: fresh clone, re-run does git pull not clone.

setup_file() {
  # Create a bare git clone for bootstrap tests to use - done once for all tests
  export TEST_BARE_REPO="$BATS_TMPDIR/caveman-kit-bare.git"
  rm -rf "$TEST_BARE_REPO"
  git init --bare "$TEST_BARE_REPO"
  # Push current checkout (HEAD may be detached in CI) to bare clone as master
  git -C "$BATS_TEST_DIRNAME/.." push --force "$TEST_BARE_REPO" HEAD:refs/heads/master
  git -C "$TEST_BARE_REPO" symbolic-ref HEAD refs/heads/master 2>/dev/null || true
  export CAVEMAN_KIT_GIT_REPO="file://$TEST_BARE_REPO"
  export CAVEMAN_KIT_INSTALL_DIR="$BATS_TMPDIR/caveman-kit-install"
}

teardown_file() {
  rm -rf "$TEST_BARE_REPO"
  rm -rf "$CAVEMAN_KIT_INSTALL_DIR"
}

setup() {
  # Isolate each test with a fresh HOME
  export TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  
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
  
  # Pre-seed the caveman skill so we skip the npx call
  mkdir -p "$CLAUDE_CONFIG_DIR/skills/caveman"
  cat > "$CLAUDE_CONFIG_DIR/skills/caveman/SKILL.md" <<'SKILL'
---
name: caveman
---
# Caveman Skill
SKILL
}

teardown() {
  rm -rf "$TEST_HOME"
  rm -rf "$HOME/.caveman-kit"
}

@test "bootstrap.sh clones and runs install.sh" {
  # Run bootstrap
  bash "$BATS_TEST_DIRNAME/../bootstrap.sh"
  
  # Verify install dir was created
  [ -d "$CAVEMAN_KIT_INSTALL_DIR" ]
  
  # Verify .git directory exists (it's a clone)
  [ -d "$CAVEMAN_KIT_INSTALL_DIR/.git" ]
  
  # Verify manifest.json was created (install completed)
  [ -f "$HOME/.caveman-kit/manifest.json" ]
}

@test "re-running bootstrap does git pull not git clone" {
  # First run - clone
  bash "$BATS_TEST_DIRNAME/../bootstrap.sh"
  
  # Verify install dir exists
  [ -d "$CAVEMAN_KIT_INSTALL_DIR" ]
  
  # Capture output of second run
  run bash "$BATS_TEST_DIRNAME/../bootstrap.sh"
  
  # Second run should say "Updating" not "Cloning"
  [[ "$output" == *"Updating"* ]]
  [[ "$output" != *"Cloning"* ]]
}
