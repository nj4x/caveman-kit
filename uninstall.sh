#!/usr/bin/env bash
# caveman-kit uninstaller.
#
# Surgically removes caveman-kit entries from settings.json and statusline.sh
# using marker-based detection (not byte-exact restore from backups):
# - settings.json: removes hook entries containing 'caveman-activate.js' and
#   'caveman-mode-tracker.js' via lib/settings-unpatch.js
# - statusline.sh: removes the block between '# CAVEMAN-KIT BEGIN' and
#   '# CAVEMAN-KIT END' via lib/statusline-unpatch.js
# Install-time backups stay in the manifest for manual recovery only.
# Then removes ~/.caveman-kit and the install source directory.
set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_HOME="$HOME/.caveman-kit"
MANIFEST="$KIT_HOME/manifest.json"
INSTALL_DIR="${CAVEMAN_KIT_INSTALL_DIR:-$HOME/.local/share/caveman-kit}"

if [ ! -d "$KIT_HOME" ]; then
  echo "error: caveman-kit is not installed ($KIT_HOME not found)" >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "error: node not found on PATH" >&2
  exit 1
fi

if [ ! -f "$MANIFEST" ]; then
  echo "warning: $MANIFEST missing — cannot determine skill state." >&2
  echo "Proceeding with best-effort cleanup (settings/statusline markers, $KIT_HOME)." >&2

  CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  SETTINGS="$CLAUDE_DIR/settings.json"
  STATUSLINE="$CLAUDE_DIR/statusline.sh"

  if [ -f "$SETTINGS" ]; then
    node "$KIT_DIR/lib/settings-unpatch.js" "$SETTINGS" || true
    echo "restored: $SETTINGS (best-effort, marker-based)"
  fi

  if [ -f "$STATUSLINE" ] && [ ! -L "$STATUSLINE" ]; then
    node "$KIT_DIR/lib/statusline-unpatch.js" "$STATUSLINE" || true
  fi

  rm -rf "$KIT_HOME"
  echo "removed: $KIT_HOME"

  if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    echo "removed: $INSTALL_DIR"
  fi

  echo
  echo "caveman-kit uninstalled (best-effort, manifest was missing)."
  echo "Manual cleanup may be needed for the skill entry."
  exit 0
fi

CLAUDE_DIR="$(node -e "const m=JSON.parse(require('fs').readFileSync('$MANIFEST','utf8')); console.log(m.claudeDir || '')")"
SKILL_INSTALLED_BY_KIT="$(node -e "const m=JSON.parse(require('fs').readFileSync('$MANIFEST','utf8')); console.log(m.skillInstalledByKit === true ? 'true' : 'false')")"
SKILL_BACKUP="$(node -e "const m=JSON.parse(require('fs').readFileSync('$MANIFEST','utf8')); console.log((m.skillBackup === null || m.skillBackup === undefined) ? '' : m.skillBackup)")"

SETTINGS="$CLAUDE_DIR/settings.json"
STATUSLINE="$CLAUDE_DIR/statusline.sh"

# Surgically remove caveman hooks from settings.json using marker-based detection
if [ -f "$SETTINGS" ]; then
  node "$KIT_DIR/lib/settings-unpatch.js" "$SETTINGS"
  echo "restored: $SETTINGS (surgical removal)"
else
  echo "warning: $SETTINGS not found — skipping settings unpatch" >&2
fi

# Surgically remove caveman badge block from statusline.sh using sentinel markers
if [ -f "$STATUSLINE" ] && [ ! -L "$STATUSLINE" ]; then
  node "$KIT_DIR/lib/statusline-unpatch.js" "$STATUSLINE"
else
  echo "warning: $STATUSLINE not found (or is a symlink) — skipping statusline unpatch" >&2
fi

# Skill cleanup (ADR 0002/0003): remove entirely if the kit installed it;
# otherwise restore the pre-patch backup and leave the skill in place.
SKILL_DIR="$CLAUDE_DIR/skills/caveman"
if [ "$SKILL_INSTALLED_BY_KIT" = "true" ]; then
  rm -rf "$SKILL_DIR"
  echo "removed: $SKILL_DIR (installed by caveman-kit)"
elif [ -n "$SKILL_BACKUP" ]; then
  if [ -f "$SKILL_BACKUP" ] && [ -d "$SKILL_DIR" ]; then
    if cp "$SKILL_BACKUP" "$SKILL_DIR/SKILL.md"; then
      echo "restored: $SKILL_DIR/SKILL.md"
    else
      echo "warning: failed to restore $SKILL_DIR/SKILL.md from backup — left as-is" >&2
    fi
  elif [ ! -d "$SKILL_DIR" ]; then
    echo "warning: $SKILL_DIR no longer exists — skipping SKILL.md restore" >&2
  else
    echo "warning: skill backup recorded but missing at $SKILL_BACKUP — left SKILL.md untouched" >&2
  fi
fi

rm -rf "$KIT_HOME"
echo "removed: $KIT_HOME"

# Remove the install source directory if it exists
if [ -d "$INSTALL_DIR" ]; then
  rm -rf "$INSTALL_DIR"
  echo "removed: $INSTALL_DIR"
fi

echo
echo "caveman-kit uninstalled. Restart Claude Code."
