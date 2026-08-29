#!/usr/bin/env bash
# caveman-kit installer.
#
# Preserves the existing Claude Code configuration: injects two hook entries
# (SessionStart, UserPromptSubmit) into settings.json and a small badge block
# into statusline.sh. Everything touched is backed up under
# ~/.caveman-kit/backup/ so uninstall.sh can restore it exactly.
#
# Requires the caveman skill to already be installed at
# $CLAUDE_CONFIG_DIR/skills/caveman/SKILL.md — this kit does not ship it.
set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
KIT_HOME="$HOME/.caveman-kit"
BACKUP_DIR="$KIT_HOME/backup"
SETTINGS="$CLAUDE_DIR/settings.json"
STATUSLINE="$CLAUDE_DIR/statusline.sh"
SKILL_PATH="$CLAUDE_DIR/skills/caveman/SKILL.md"

if [ -d "$KIT_HOME" ]; then
  echo "error: caveman-kit already installed at $KIT_HOME. Run uninstall.sh first." >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "error: node not found on PATH" >&2
  exit 1
fi

if [ ! -f "$SETTINGS" ]; then
  echo "error: $SETTINGS not found" >&2
  exit 1
fi

if [ ! -f "$SKILL_PATH" ]; then
  echo "error: caveman skill not found at $SKILL_PATH" >&2
  echo "caveman-kit only wires up hooks for it — it does not install the skill itself." >&2
  echo "Install the caveman skill first: https://github.com/JuliusBrussee/caveman" >&2
  exit 1
fi

# Resolve through the skill's symlink chain (if any) so the SessionStart hook
# can find SKILL.md via CLAUDE_PLUGIN_ROOT regardless of how it's linked in.
PLUGIN_ROOT="$(cd -P "$(dirname "$SKILL_PATH")/../.." && pwd)"

mkdir -p "$KIT_HOME/hooks" "$BACKUP_DIR"
cp "$KIT_DIR"/hooks/*.js "$KIT_HOME/hooks/"

cp "$SETTINGS" "$BACKUP_DIR/settings.json.bak"
node "$KIT_DIR/lib/settings-patch.js" "$SETTINGS" "$KIT_HOME/hooks" "$PLUGIN_ROOT"

STATUSLINE_BACKUP_JSON="null"
if [ -f "$STATUSLINE" ] && [ ! -L "$STATUSLINE" ]; then
  cp "$STATUSLINE" "$BACKUP_DIR/statusline.sh.bak"
  node "$KIT_DIR/lib/statusline-patch.js" "$STATUSLINE"
  STATUSLINE_BACKUP_JSON="\"$BACKUP_DIR/statusline.sh.bak\""
else
  echo "warning: $STATUSLINE not found (or is a symlink) — skipping statusline badge" >&2
fi

cat > "$KIT_HOME/manifest.json" <<JSON
{
  "installedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "claudeDir": "$CLAUDE_DIR",
  "settingsBackup": "$BACKUP_DIR/settings.json.bak",
  "statuslineBackup": $STATUSLINE_BACKUP_JSON,
  "pluginRoot": "$PLUGIN_ROOT"
}
JSON

echo
echo "caveman-kit installed to $KIT_HOME"
echo "Restart Claude Code for the hooks to take effect."
