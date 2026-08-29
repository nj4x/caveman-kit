#!/usr/bin/env bash
# caveman-kit uninstaller.
#
# Restores settings.json and statusline.sh from the exact backups install.sh
# made, then removes ~/.caveman-kit. Byte-exact restore, not a surgical diff —
# simpler and safer than trying to reverse-parse what was injected.
set -euo pipefail

KIT_HOME="$HOME/.caveman-kit"
MANIFEST="$KIT_HOME/manifest.json"

if [ ! -d "$KIT_HOME" ]; then
  echo "error: caveman-kit is not installed ($KIT_HOME not found)" >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "error: node not found on PATH" >&2
  exit 1
fi

if [ ! -f "$MANIFEST" ]; then
  echo "error: $MANIFEST missing — cannot determine what to restore." >&2
  echo "Remove $KIT_HOME manually and revert settings.json/statusline.sh by hand." >&2
  exit 1
fi

CLAUDE_DIR="$(node -e "console.log(JSON.parse(require('fs').readFileSync('$MANIFEST','utf8')).claudeDir)")"
SETTINGS_BACKUP="$(node -e "console.log(JSON.parse(require('fs').readFileSync('$MANIFEST','utf8')).settingsBackup)")"
STATUSLINE_BACKUP="$(node -e "const m=JSON.parse(require('fs').readFileSync('$MANIFEST','utf8')); console.log(m.statuslineBackup || '')")"

SETTINGS="$CLAUDE_DIR/settings.json"
STATUSLINE="$CLAUDE_DIR/statusline.sh"

if [ ! -f "$SETTINGS_BACKUP" ]; then
  echo "error: settings backup not found at $SETTINGS_BACKUP" >&2
  exit 1
fi
cp "$SETTINGS_BACKUP" "$SETTINGS"
echo "restored: $SETTINGS"

if [ -n "$STATUSLINE_BACKUP" ]; then
  if [ -f "$STATUSLINE_BACKUP" ]; then
    cp "$STATUSLINE_BACKUP" "$STATUSLINE"
    echo "restored: $STATUSLINE"
  else
    echo "warning: statusline backup recorded but missing at $STATUSLINE_BACKUP — left $STATUSLINE untouched" >&2
  fi
fi

rm -rf "$KIT_HOME"
echo "removed: $KIT_HOME"
echo
echo "caveman-kit uninstalled. Restart Claude Code."
