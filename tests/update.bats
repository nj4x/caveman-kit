#!/usr/bin/env bats
# caveman-kit update.bats
#
# Tests for update.sh: pluginRoot re-resolution, skill-skipped notice, health check.

setup() {
  export HOME="$(cd "$(mktemp -d)" && pwd -P)"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  mkdir -p "$CLAUDE_CONFIG_DIR/skills" "$HOME/.agents/skills/caveman"

  echo '{ "hooks": {} }' > "$CLAUDE_CONFIG_DIR/settings.json"
  printf '#!/usr/bin/env bash\necho "statusline"\n' > "$CLAUDE_CONFIG_DIR/statusline.sh"
  chmod +x "$CLAUDE_CONFIG_DIR/statusline.sh"

  printf -- '---\nname: caveman\n---\n# Caveman Skill\n' > "$HOME/.agents/skills/caveman/SKILL.md"
  ln -s "$HOME/.agents/skills/caveman" "$CLAUDE_CONFIG_DIR/skills/caveman"

  # Seed repo (working-tree copy, so uncommitted edits are tested) -> bare remote -> kit clone
  SEED="$HOME/seed"
  mkdir -p "$SEED"
  (cd "$BATS_TEST_DIRNAME/.." && tar --exclude=.git -cf - .) | tar -xf - -C "$SEED"
  git -C "$SEED" init -q -b master
  git -C "$SEED" add -A
  git -C "$SEED" -c user.name=t -c user.email=t@t commit -q -m seed
  git init -q --bare "$HOME/remote.git"
  git -C "$SEED" push -q "$HOME/remote.git" master:master
  git -C "$HOME/remote.git" symbolic-ref HEAD refs/heads/master
  git clone -q "$HOME/remote.git" "$HOME/kit"

  bash "$HOME/kit/install.sh" >/dev/null
}

teardown() {
  rm -rf "$HOME"
}

push_new_commit() {
  echo x >> "$SEED/CLAUDE.md"
  git -C "$SEED" -c user.name=t -c user.email=t@t commit -q -am bump
  git -C "$SEED" push -q "$HOME/remote.git" master:master
}

replace_symlink_with_copy() {
  rm "$CLAUDE_CONFIG_DIR/skills/caveman"
  cp -R "$HOME/.agents/skills/caveman" "$CLAUDE_CONFIG_DIR/skills/caveman"
}

plugin_root_in_manifest() {
  node -e "console.log(JSON.parse(require('fs').readFileSync('$HOME/.caveman-kit/manifest.json','utf8')).pluginRoot)"
}

@test "install records the symlink-resolved plugin root" {
  [ "$(plugin_root_in_manifest)" = "$HOME/.agents" ]
}

@test "kit up to date: replaced skill symlink re-points hooks and manifest" {
  replace_symlink_with_copy

  run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skill location changed"* ]]
  [ "$(plugin_root_in_manifest)" = "$CLAUDE_CONFIG_DIR" ]
  grep -q "CLAUDE_PLUGIN_ROOT='$CLAUDE_CONFIG_DIR'" "$CLAUDE_CONFIG_DIR/settings.json"
  ! grep -q "CLAUDE_PLUGIN_ROOT='$HOME/.agents'" "$CLAUDE_CONFIG_DIR/settings.json"
}

@test "new kit commits: replaced skill symlink re-points hooks and manifest" {
  replace_symlink_with_copy
  push_new_commit

  run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skill location changed"* ]]
  [[ "$output" == *"caveman-kit updated"* ]]
  [ "$(plugin_root_in_manifest)" = "$CLAUDE_CONFIG_DIR" ]
  grep -q "CLAUDE_PLUGIN_ROOT='$CLAUDE_CONFIG_DIR'" "$CLAUDE_CONFIG_DIR/settings.json"
}

@test "unchanged skill location leaves plugin root alone" {
  push_new_commit

  run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Skill location changed"* ]]
  [ "$(plugin_root_in_manifest)" = "$HOME/.agents" ]
}

@test "skill not installed by kit: update says it skipped the skill" {
  push_new_commit

  run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skill not kit-managed, skipped"* ]]
}

@test "health check warns when SKILL.md is missing at the plugin root" {
  rm -rf "$HOME/.agents/skills/caveman"

  run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"missing or unreadable"* ]]
}
