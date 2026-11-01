#!/usr/bin/env bats
# caveman-kit update.bats
#
# Tests for update.sh: pluginRoot re-resolution, skill-skipped notice, health check.

load helpers/skills

setup() {
  export HOME="$(cd "$(mktemp -d)" && pwd -P)"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  export KIT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # Hermetic skills: fake upstream with release tags + stub npx.
  make_upstream v3.0.0 v4.0.0 v4.0.1
  install_npx_stub
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
  : > "$HOME/npx.log"
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
  [[ "$output" == *"Skill location changed"* ]] || false
  [ "$(plugin_root_in_manifest)" = "$CLAUDE_CONFIG_DIR" ]
  grep -q "CLAUDE_PLUGIN_ROOT='$CLAUDE_CONFIG_DIR'" "$CLAUDE_CONFIG_DIR/settings.json"
  ! grep -q "CLAUDE_PLUGIN_ROOT='$HOME/.agents'" "$CLAUDE_CONFIG_DIR/settings.json" || false
}

@test "new kit commits: replaced skill symlink re-points hooks and manifest" {
  replace_symlink_with_copy
  push_new_commit

  run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skill location changed"* ]] || false
  [[ "$output" == *"caveman-kit updated"* ]] || false
  [ "$(plugin_root_in_manifest)" = "$CLAUDE_CONFIG_DIR" ]
  grep -q "CLAUDE_PLUGIN_ROOT='$CLAUDE_CONFIG_DIR'" "$CLAUDE_CONFIG_DIR/settings.json"
}

@test "unchanged skill location leaves plugin root alone" {
  push_new_commit

  run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Skill location changed"* ]] || false
  [ "$(plugin_root_in_manifest)" = "$HOME/.agents" ]
}

@test "skill not installed by kit: update says it skipped the skill" {
  push_new_commit

  run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skill not kit-managed, skipped"* ]] || false
}

@test "health check warns when SKILL.md is missing at the plugin root" {
  rm -rf "$HOME/.agents/skills/caveman"

  run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"missing or unreadable"* ]] || false
}

# ---- skill steps (ADR 0020 decision 7, ADR 0021 decisions 3-7) ----

mset() { node "$KIT_DIR/lib/manifest.js" set "$HOME/.caveman-kit/manifest.json" "$1" "$2"; }
munset() { node "$KIT_DIR/lib/manifest.js" unset "$HOME/.caveman-kit/manifest.json" "$1"; }
npx_calls() { wc -l < "$HOME/npx.log" | tr -d ' '; }

# Fresh install where the kit owns both skills (stub npx installs them).
reinstall_kit_owned() {
  bash "$HOME/kit/uninstall.sh" >/dev/null
  rm -rf "$CLAUDE_CONFIG_DIR/skills/caveman" "$CLAUDE_CONFIG_DIR/skills/ultracave" "$HOME/.agents"
  : > "$HOME/npx.log"
  bash "$HOME/kit/install.sh" >/dev/null
  : > "$HOME/npx.log"
}

add_upstream_tag() {
  git -C "$HOME/upstream-work" tag "$1"
  git -C "$HOME/upstream-work" push -q "$HOME/upstream.git" "$1"
}

@test "same tag as skillRef: no skill reinstall" {
  run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [ "$(npx_calls)" = "0" ]
}

@test "newer release, no kit commits: upgrades only the kit-owned ultracave, leaves the user's caveman" {
  add_upstream_tag v4.1.0

  run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [ "$(npx_calls)" = "1" ]
  grep -q '^ultracave JuliusBrussee/caveman@v4.1.0$' "$HOME/npx.log"
  [ "$(manifest_get skillRef)" = '"v4.1.0"' ]
  ! grep -q '^caveman ' "$HOME/npx.log" || false
}

@test "newer release: upgrades kit-owned caveman and ultracave, re-applies the frontmatter patch" {
  reinstall_kit_owned
  add_upstream_tag v4.1.0

  run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  grep -q '^caveman,ultracave JuliusBrussee/caveman@v4.1.0$' "$HOME/npx.log"
  grep -q '^disable-model-invocation: true$' "$CLAUDE_CONFIG_DIR/skills/caveman/SKILL.md"
  [ "$(manifest_get skillRef)" = '"v4.1.0"' ]
}

@test "new kit commits: kit step runs first, then the pulled script runs the skill steps" {
  reinstall_kit_owned
  add_upstream_tag v4.1.0
  push_new_commit

  run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"caveman-kit updated"* ]] || false
  [[ "$output" == *"Upgrading caveman ultracave"* ]] || false
  [[ "$output" != *"Kit is already up to date"* ]] || false
  [ "$(manifest_get skillRef)" = '"v4.1.0"' ]
  [ "$(manifest_get kitSha)" = "\"$(git -C "$HOME/kit" rev-parse HEAD)\"" ]
}

@test "failed caveman upgrade keeps skillRef; the next run retries" {
  reinstall_kit_owned
  add_upstream_tag v4.1.0

  NPX_FAIL=caveman run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [ "$(manifest_get skillRef)" = '"v4.0.1"' ]

  run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [ "$(manifest_get skillRef)" = '"v4.1.0"' ]
}

@test "failed ultracave upgrade with the old copy present keeps true and skillRef" {
  add_upstream_tag v4.1.0

  NPX_FAIL=ultracave run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [ "$(manifest_get ultracaveInstalledByKit)" = "true" ]
  [ "$(manifest_get skillRef)" = '"v4.0.1"' ]
}

@test "upgrade that leaves ultracave not present records null (pending), never true" {
  add_upstream_tag v4.1.0

  NPX_WIPE=ultracave run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [ "$(manifest_get ultracaveInstalledByKit)" = "null" ]
  [ "$(manifest_get skillRef)" = '"v4.0.1"' ]

  # Same tag next run: the pending step still retries.
  run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [ "$(manifest_get ultracaveInstalledByKit)" = "true" ]
}

@test "true with ultracave deleted by the user: recorded false, never reinstalled" {
  add_upstream_tag v4.1.0
  rm -rf "$CLAUDE_CONFIG_DIR/skills/ultracave"

  run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [ "$(manifest_get ultracaveInstalledByKit)" = "false" ]
  [ "$(npx_calls)" = "0" ]
  [ ! -e "$CLAUDE_CONFIG_DIR/skills/ultracave" ]
}

@test "legacy manifest, kit owns caveman, ultracave missing: pending install, skillRef recorded" {
  reinstall_kit_owned
  rm -rf "$CLAUDE_CONFIG_DIR/skills/ultracave"
  munset ultracaveInstalledByKit
  munset skillRef

  run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [ "$(manifest_get ultracaveInstalledByKit)" = "true" ]
  [ -f "$CLAUDE_CONFIG_DIR/skills/ultracave/SKILL.md" ]
  [ "$(manifest_get skillRef)" = '"v4.0.1"' ]
}

@test "legacy manifest, kit owns caveman, ultracave already present: recorded false, no install" {
  reinstall_kit_owned
  munset ultracaveInstalledByKit
  munset skillRef

  run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [ "$(manifest_get ultracaveInstalledByKit)" = "false" ]
  ! grep -q '^ultracave ' "$HOME/npx.log" || false
}

@test "legacy manifest, user-managed caveman: recorded false, nothing installed, no lookup" {
  rm -rf "$CLAUDE_CONFIG_DIR/skills/ultracave"
  munset ultracaveInstalledByKit
  export CAVEMAN_KIT_SKILL_REMOTE="file://$HOME/nope.git"

  run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [ "$(manifest_get ultracaveInstalledByKit)" = "false" ]
  [ "$(npx_calls)" = "0" ]
  [[ "$output" != *"could not resolve"* ]] || false
}

@test "false is never installed over: a --no-install-skill user stays opted out" {
  rm -rf "$CLAUDE_CONFIG_DIR/skills/ultracave"
  mset ultracaveInstalledByKit false
  add_upstream_tag v4.1.0

  run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [ "$(npx_calls)" = "0" ]
}

@test "null with ultracave present is recorded false without a tag lookup" {
  mset ultracaveInstalledByKit null
  export CAVEMAN_KIT_SKILL_REMOTE="file://$HOME/nope.git"

  run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [ "$(manifest_get ultracaveInstalledByKit)" = "false" ]
  [[ "$output" != *"could not resolve"* ]] || false
}

@test "lookup failure: warns, keeps pending null and the installed skills, exits 0" {
  rm -rf "$CLAUDE_CONFIG_DIR/skills/ultracave"
  mset ultracaveInstalledByKit null
  export CAVEMAN_KIT_SKILL_REMOTE="file://$HOME/nope.git"

  run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"could not resolve"* ]] || false
  [[ "$output" == *"npx skills add JuliusBrussee/caveman@v4.0.1 --skill ultracave"* ]] || false
  [ "$(manifest_get ultracaveInstalledByKit)" = "null" ]
  [ "$(npx_calls)" = "0" ]
}

@test "latest release older than skillRef: warns and installs nothing" {
  mset skillRef '"v4.5.0"'

  run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"older than the installed v4.5.0"* ]] || false
  [ "$(npx_calls)" = "0" ]
  [ "$(manifest_get skillRef)" = '"v4.5.0"' ]
}

@test "CAVEMAN_KIT_SKILL_REF holds a tag across plain runs, and latest clears the hold" {
  reinstall_kit_owned
  add_upstream_tag v4.1.0

  CAVEMAN_KIT_SKILL_REF=v4.0.0 run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  grep -q '^caveman,ultracave JuliusBrussee/caveman@v4.0.0$' "$HOME/npx.log"
  [ "$(manifest_get skillRef)" = '"v4.0.0"' ]
  [ "$(manifest_get skillRefOverride)" = '"v4.0.0"' ]

  : > "$HOME/npx.log"
  run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"held at v4.0.0"* ]] || false
  [ "$(npx_calls)" = "0" ]

  CAVEMAN_KIT_SKILL_REF=latest run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [ "$(manifest_get skillRefOverride)" = "absent" ]
  [ "$(manifest_get skillRef)" = '"v4.1.0"' ]
}

@test "rejected CAVEMAN_KIT_SKILL_REF leaves state unchanged" {
  add_upstream_tag v4.1.0

  for bad in v3.0.0 main v4.0 4.0.1; do
    CAVEMAN_KIT_SKILL_REF="$bad" run bash "$HOME/kit/update.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"rejected"* ]] || false
    [ "$(npx_calls)" = "0" ]
    [ "$(manifest_get skillRef)" = '"v4.0.1"' ]
    [ "$(manifest_get skillRefOverride)" = "absent" ]
  done
}

@test "pending ultracave is retried on a run where the tag equals skillRef" {
  rm -rf "$CLAUDE_CONFIG_DIR/skills/ultracave"
  mset ultracaveInstalledByKit null
  [ "$(manifest_get skillRef)" = '"v4.0.1"' ]

  run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [ "$(npx_calls)" = "1" ]
  grep -q '^ultracave JuliusBrussee/caveman@v4.0.1$' "$HOME/npx.log"
  [ "$(manifest_get ultracaveInstalledByKit)" = "true" ]
}

@test "failed caveman upgrade with null skillRef: the pending ultracave install does not write skillRef" {
  reinstall_kit_owned
  rm -rf "$CLAUDE_CONFIG_DIR/skills/ultracave"
  mset ultracaveInstalledByKit null
  munset skillRef

  NPX_FAIL=caveman run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [ "$(manifest_get ultracaveInstalledByKit)" = "true" ]
  [ "$(manifest_get skillRef)" = "absent" ]

  # Next run retries caveman because skillRef still differs.
  : > "$HOME/npx.log"
  run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  grep -q '^caveman,ultracave JuliusBrussee/caveman@v4.0.1$' "$HOME/npx.log"
  [ "$(manifest_get skillRef)" = '"v4.0.1"' ]
}

@test "a hand-edited invalid skillRefOverride is rejected, not installed" {
  node "$KIT_DIR/lib/manifest.js" setstr "$HOME/.caveman-kit/manifest.json" skillRefOverride main

  run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skillRefOverride=main"* ]] || false
  [ "$(npx_calls)" = "0" ]
}

@test "latest release is chosen by numeric version order, not text order" {
  add_upstream_tag v4.9.0
  add_upstream_tag v4.10.0

  run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [ "$(manifest_get skillRef)" = '"v4.10.0"' ]
}

# ---- combined upgrade (ADR 0025 decisions 1, 3, 4) ----

@test "combined: both due makes exactly one call" {
  reinstall_kit_owned
  add_upstream_tag v4.1.0
  run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [ "$(npx_calls)" = "1" ]
  grep -q '^caveman,ultracave JuliusBrussee/caveman@v4.1.0$' "$HOME/npx.log"
  [ "$(manifest_get skillRef)" = '"v4.1.0"' ]
  [ "$(manifest_get skillInstalledByKit)" = "true" ]
  [ "$(manifest_get ultracaveInstalledByKit)" = "true" ]
}

@test "combined: a user-managed caveman is never named in --skill" {
  add_upstream_tag v4.1.0
  run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [ "$(npx_calls)" = "1" ]
  grep -q '^ultracave JuliusBrussee/caveman@v4.1.0$' "$HOME/npx.log"
}

@test "combined: non-zero exit with a kit-owned ultracave still present keeps true and skillRef" {
  reinstall_kit_owned
  add_upstream_tag v4.1.0
  NPX_EXIT1=1 run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [ "$(npx_calls)" = "1" ]
  [ "$(manifest_get ultracaveInstalledByKit)" = "true" ]
  [ "$(manifest_get skillRef)" = '"v4.0.1"' ]
  # skill-patch.js ran despite the exit code.
  grep -q '^disable-model-invocation: true$' "$CLAUDE_CONFIG_DIR/skills/caveman/SKILL.md"
}

@test "combined: ultracave missing after the call is null, skillRef unchanged, same-run single-skill retry" {
  reinstall_kit_owned
  add_upstream_tag v4.1.0
  NPX_WIPE=ultracave run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [ "$(npx_calls)" = "2" ]
  [ "$(sed -n 1p "$HOME/npx.log")" = "caveman,ultracave JuliusBrussee/caveman@v4.1.0" ]
  [ "$(sed -n 2p "$HOME/npx.log")" = "ultracave JuliusBrussee/caveman@v4.1.0" ]
  [ "$(manifest_get ultracaveInstalledByKit)" = "null" ]
  [ "$(manifest_get skillRef)" = '"v4.0.1"' ]
}

@test "combined: legacy migration run is one call; non-zero exit with ultracave written records true" {
  reinstall_kit_owned
  rm -rf "$CLAUDE_CONFIG_DIR/skills/ultracave"
  mset ultracaveInstalledByKit null
  add_upstream_tag v4.1.0
  NPX_EXIT1=1 run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [ "$(npx_calls)" = "1" ]
  grep -q '^caveman,ultracave JuliusBrussee/caveman@v4.1.0$' "$HOME/npx.log"
  [ "$(manifest_get ultracaveInstalledByKit)" = "true" ]
  [ "$(manifest_get skillRef)" = '"v4.0.1"' ]
}

@test "combined: a patch failure warns about auto-invocation and keeps skillRef" {
  reinstall_kit_owned
  add_upstream_tag v4.1.0
  NPX_NOFRONT=caveman run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"could not patch caveman frontmatter"* ]] || false
  [ "$(manifest_get skillRef)" = '"v4.0.1"' ]
}

@test "combined: caveman missing after the call warns with the manual command and skips the patch" {
  reinstall_kit_owned
  add_upstream_tag v4.1.0
  NPX_WIPE=caveman run bash "$HOME/kit/update.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"caveman is not present after the upgrade"* ]] || false
  [[ "$output" == *"npx skills add JuliusBrussee/caveman@v4.1.0 --skill caveman"* ]] || false
  [[ "$output" != *"could not patch"* ]] || false
  [ "$(manifest_get skillRef)" = '"v4.0.1"' ]
}
