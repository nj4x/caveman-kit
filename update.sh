#!/usr/bin/env bash
# caveman-kit in-place update script.
#
# Updates the kit and optionally the pinned skill without uninstalling.
# Requires an existing manifest.json (from a prior successful install).
# Patches are idempotent; if no changes detected, exits 0 with "already up to date".
set -euo pipefail

print_help() {
  cat <<EOF
Usage: update.sh [--help]

In-place update for caveman-kit. Checks for new commits, repatches settings.json
and statusline.sh, copies updated hook files, and optionally upgrades the skill.

Requires an existing manifest.json from a prior install. First install still
requires bootstrap.sh.

Exit 0 if update succeeds or no new commits found. Non-zero on error.
EOF
}

[ "${1:-}" = "--help" ] && print_help && exit 0

# ===== Setup =====

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_HOME="$HOME/.caveman-kit"
MANIFEST="$KIT_HOME/manifest.json"

fail() {
  echo "[caveman-kit update] error: $*" >&2
  echo "[caveman-kit update] Update failed; run again to retry or run uninstall.sh + bootstrap.sh to recover" >&2
  exit 1
}

trap 'fail "unexpected error"' ERR

# ===== Manifest check =====

if [ ! -f "$MANIFEST" ]; then
  fail "manifest.json not found at $MANIFEST. First install requires: bootstrap.sh"
fi

if ! command -v node >/dev/null 2>&1; then
  fail "node not found on PATH"
fi

# Parse manifest (jq preferred, fallback to grep extraction)
parse_manifest() {
  local field="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r ".${field} // empty" "$MANIFEST" 2>/dev/null || echo ""
  else
    grep "\"${field}\"" "$MANIFEST" | sed 's/.*: *"\([^"]*\)".*/\1/' | head -1
  fi
}

CURRENT_KIT_SHA="$(parse_manifest 'kitSha')"
[ -z "$CURRENT_KIT_SHA" ] && CURRENT_KIT_SHA="none"

CLAUDE_DIR="$(parse_manifest 'claudeDir')"
[ -z "$CLAUDE_DIR" ] && fail "claudeDir not in manifest"

PLUGIN_ROOT="$(parse_manifest 'pluginRoot')"
[ -z "$PLUGIN_ROOT" ] && fail "pluginRoot not in manifest"

SKILL_INSTALLED_BY_KIT="$(parse_manifest 'skillInstalledByKit')"
[ -z "$SKILL_INSTALLED_BY_KIT" ] && SKILL_INSTALLED_BY_KIT="false"

SETTINGS="$CLAUDE_DIR/settings.json"
STATUSLINE="$CLAUDE_DIR/statusline.sh"
SKILL_PATH="$CLAUDE_DIR/skills/caveman/SKILL.md"

[ ! -f "$SETTINGS" ] && fail "settings.json not found at $SETTINGS"

# ===== Git check =====

if [ ! -d "$KIT_DIR/.git" ]; then
  fail "$KIT_DIR is not a git repository"
fi

cd "$KIT_DIR"

git fetch origin master 2>/dev/null || git fetch origin 2>/dev/null || fail "git fetch failed"

# Detect default branch (could be master or main)
REMOTE_HEAD="$(git symbolic-ref refs/remotes/origin/HEAD | sed 's|.*/||' 2>/dev/null || echo 'master')"
REMOTE_SHA="$(git rev-parse origin/$REMOTE_HEAD 2>/dev/null || git rev-parse origin/master 2>/dev/null || fail "could not resolve origin branch")"

if [ "$REMOTE_SHA" = "$CURRENT_KIT_SHA" ]; then
  echo "[caveman-kit update] Kit is already up to date (SHA: $REMOTE_SHA)"
  exit 0
fi

if [ "$CURRENT_KIT_SHA" = "none" ]; then
  echo "[caveman-kit update] Initial update detected (no prior kitSha in manifest)"
else
  echo "[caveman-kit update] New commits available ($CURRENT_KIT_SHA → $REMOTE_SHA)"
fi

# ===== Unpatch =====

echo "[caveman-kit update] Unpatching settings.json..."
node "$KIT_DIR/lib/settings-unpatch.js" "$SETTINGS" || fail "settings unpatch failed"

if [ -f "$STATUSLINE" ] && [ ! -L "$STATUSLINE" ]; then
  echo "[caveman-kit update] Unpatching statusline.sh..."
  node "$KIT_DIR/lib/statusline-unpatch.js" "$STATUSLINE" || fail "statusline unpatch failed"
fi

# ===== Update kit files =====

echo "[caveman-kit update] Pulling latest kit..."
git -C "$KIT_DIR" pull origin $REMOTE_HEAD --ff-only || fail "git pull failed"

echo "[caveman-kit update] Copying hook files..."
cp "$KIT_DIR"/hooks/*.js "$KIT_HOME/hooks/" || fail "could not copy hook scripts"
cp "$KIT_DIR"/hooks/*.md "$KIT_HOME/hooks/" 2>/dev/null || true

# ===== Skill update (optional) =====

if [ "$SKILL_INSTALLED_BY_KIT" = "true" ]; then
  SKILL_SOURCE="$(grep 'SKILL_SOURCE=' "$KIT_DIR/install.sh" | head -1 | cut -d= -f2 | tr -d '"')"
  if [ -n "$SKILL_SOURCE" ]; then
    echo "[caveman-kit update] Upgrading caveman skill ($SKILL_SOURCE)..."
    if npx --yes skills add "$SKILL_SOURCE" --skill caveman -g -y --copy 2>/dev/null; then
      echo "[caveman-kit update] Skill upgraded"
    else
      echo "[caveman-kit update] warning: skill upgrade failed — proceeding with kit update only" >&2
    fi
  fi
fi

# ===== Repatch =====

echo "[caveman-kit update] Repatching settings.json..."
node "$KIT_DIR/lib/settings-patch.js" "$SETTINGS" "$KIT_HOME/hooks" "$PLUGIN_ROOT" || fail "settings repatch failed"

if [ -f "$STATUSLINE" ] && [ ! -L "$STATUSLINE" ]; then
  echo "[caveman-kit update] Repatching statusline.sh..."
  node "$KIT_DIR/lib/statusline-patch.js" "$STATUSLINE" || fail "statusline repatch failed"
fi

# ===== Update manifest =====

NEW_KIT_SHA="$(git -C "$KIT_DIR" rev-parse HEAD)"

if command -v jq >/dev/null 2>&1; then
  jq ".kitSha = \"$NEW_KIT_SHA\"" "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"
else
  # Fallback: naive JSON update (assumes "completed" is last field)
  sed "s/\"completed\": true/\"kitSha\": \"$NEW_KIT_SHA\",\n  \"completed\": true/" "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"
fi

echo
echo "[caveman-kit update] caveman-kit updated to $(git -C "$KIT_DIR" rev-parse HEAD | cut -c1-8)"
echo "Restart Claude Code for the updates to take effect."
