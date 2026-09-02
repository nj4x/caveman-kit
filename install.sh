#!/usr/bin/env bash
# caveman-kit installer.
#
# Preserves the existing Claude Code configuration: injects three hook entries
# (SessionStart, SubagentStart, UserPromptSubmit) into settings.json and a small badge block
# into statusline.sh. Everything touched is backed up under
# ~/.caveman-kit/backup/ so uninstall.sh can restore it exactly.
#
# Requires the caveman skill at $CLAUDE_CONFIG_DIR/skills/caveman/SKILL.md.
# If missing, installs it automatically (pinned) via `npx skills add`.
# Pass --no-install-skill (or CAVEMAN_KIT_INSTALL_SKILL=0) to opt out and
# manage it yourself (ADR 0001, amended).
set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
KIT_HOME="$HOME/.caveman-kit"
BACKUP_DIR="$KIT_HOME/backup"
SETTINGS="$CLAUDE_DIR/settings.json"
STATUSLINE="$CLAUDE_DIR/statusline.sh"
SKILL_PATH="$CLAUDE_DIR/skills/caveman/SKILL.md"
SKILL_SOURCE="JuliusBrussee/caveman@v2.2.0"

INSTALL_SKILL=1
[ "${1:-}" = "--no-install-skill" ] && INSTALL_SKILL=0
[ "${CAVEMAN_KIT_INSTALL_SKILL:-}" = "0" ] && INSTALL_SKILL=0

# Paths flow unescaped into manifest.json heredocs and node -e strings; a
# quote or backslash in one would corrupt the manifest and break uninstall.
for _pv in "HOME=$HOME" "CLAUDE_DIR=$CLAUDE_DIR"; do
  case "${_pv#*=}" in
    *\"*|*\\*) echo "error: ${_pv%%=*} contains a quote or backslash — unsupported installation path: ${_pv#*=}" >&2; exit 1 ;;
  esac
done
unset _pv

write_manifest() {
  local settings_backup="$1"
  local statusline_backup="$2"
  local skill_backup="$3"
  local plugin_root="$4"
  local skill_installed="$5"
  local completed="$6"

  cat > "$KIT_HOME/manifest.json" <<JSON
{
  "installedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "claudeDir": "$CLAUDE_DIR",
  "settingsBackup": "${settings_backup:-null}",
  "statuslineBackup": ${statusline_backup:-null},
  "pluginRoot": "${plugin_root:-null}",
  "skillInstalledByKit": ${skill_installed:-false},
  "skillBackup": ${skill_backup:-null},
  "completed": ${completed:-false}
}
JSON
}

rollback_on_failure() {
  echo "[caveman-kit] Install failed — rolling back partial changes..." >&2
  if [ -f "$KIT_HOME/manifest.json" ]; then
    "$KIT_DIR/uninstall.sh" >&2 || echo "[caveman-kit] warning: rollback via uninstall.sh failed — remove $KIT_HOME manually" >&2
  else
    rm -rf "$KIT_HOME"
  fi
}

trap 'rollback_on_failure' ERR

# Check for already completed install (failed installs get rolled back, so KIT_HOME
# with completed=true means a prior successful install)
if [ -d "$KIT_HOME" ] && [ -f "$KIT_HOME/manifest.json" ]; then
  COMPLETED="$(node -e "const m=JSON.parse(require('fs').readFileSync('$KIT_HOME/manifest.json','utf8')); console.log(m.completed === true ? 'true' : 'false')" 2>/dev/null || echo "false")"
  if [ "$COMPLETED" = "true" ]; then
    echo "[caveman-kit] error: caveman-kit already installed at $KIT_HOME. Run uninstall.sh first." >&2
    exit 1
  fi
fi

skill_missing_abort() {
  echo "[caveman-kit] error: caveman skill not found at $SKILL_PATH" >&2
  echo "caveman-kit only wires up hooks for it — install the skill first:" >&2
  echo "  npx skills add $SKILL_SOURCE --skill caveman -g --copy" >&2
  echo "or drop --no-install-skill to let this installer do it automatically." >&2
  echo "Details: https://github.com/JuliusBrussee/caveman" >&2
  exit 1
}

echo "[caveman-kit] Checking prerequisites..."

if ! command -v node >/dev/null 2>&1; then
  echo "[caveman-kit] error: node not found on PATH" >&2
  exit 1
fi

if [ ! -f "$SETTINGS" ]; then
  echo "[caveman-kit] error: $SETTINGS not found" >&2
  exit 1
fi

SKILL_INSTALLED_BY_KIT=false
if [ ! -f "$SKILL_PATH" ]; then
  [ "$INSTALL_SKILL" = "1" ] || skill_missing_abort

  echo "[caveman-kit] Installing caveman skill ($SKILL_SOURCE)..."
  if ! npx --yes skills add "$SKILL_SOURCE" --skill caveman -g -y --copy; then
    echo "[caveman-kit] warning: automated skill install failed" >&2
    skill_missing_abort
  fi
  if [ ! -f "$SKILL_PATH" ]; then
    echo "[caveman-kit] warning: skill install ran but $SKILL_PATH still missing" >&2
    skill_missing_abort
  fi
  SKILL_INSTALLED_BY_KIT=true
fi

# Resolve through the skill's symlink chain (if any) so the SessionStart hook
# can find SKILL.md via CLAUDE_PLUGIN_ROOT regardless of how it's linked in.
PLUGIN_ROOT="$(cd -P "$(dirname "$SKILL_PATH")/../.." && pwd)"

echo "[caveman-kit] Creating kit home directory..."
mkdir -p "$KIT_HOME/hooks" "$BACKUP_DIR"
cp "$KIT_DIR"/hooks/*.js "$KIT_HOME/hooks/"

# Write initial manifest with partial state
write_manifest "null" "null" "null" "null" "false" "false"

echo "[caveman-kit] Patching Claude Code settings..."
cp "$SETTINGS" "$BACKUP_DIR/settings.json.bak"
node "$KIT_DIR/lib/settings-patch.js" "$SETTINGS" "$KIT_HOME/hooks" "$PLUGIN_ROOT"

# Update manifest with settings backup
write_manifest "$BACKUP_DIR/settings.json.bak" "null" "null" "$PLUGIN_ROOT" "$SKILL_INSTALLED_BY_KIT" "false"

STATUSLINE_BACKUP_JSON="null"
if [ -f "$STATUSLINE" ] && [ ! -L "$STATUSLINE" ]; then
  echo "[caveman-kit] Patching statusline.sh..."
  cp "$STATUSLINE" "$BACKUP_DIR/statusline.sh.bak"
  node "$KIT_DIR/lib/statusline-patch.js" "$STATUSLINE"
  STATUSLINE_BACKUP_JSON="\"$BACKUP_DIR/statusline.sh.bak\""
  # Update manifest with statusline backup
  write_manifest "$BACKUP_DIR/settings.json.bak" "\"$BACKUP_DIR/statusline.sh.bak\"" "null" "$PLUGIN_ROOT" "$SKILL_INSTALLED_BY_KIT" "false"
else
  echo "[caveman-kit] warning: $STATUSLINE not found (or is a symlink) — skipping statusline badge" >&2
fi

# Skill frontmatter patch (ADR 0002). Backup first; manifest is written with
# the skill fields BEFORE the patch attempt (decision 6) so uninstall.sh can
# always clean up correctly even if the patch fails. Patch failure is
# non-fatal by design.
SKILL_BACKUP_JSON="null"
SKILL_NEEDS_PATCH=1
if grep -q '^disable-model-invocation:' "$SKILL_PATH" 2>/dev/null; then
  SKILL_NEEDS_PATCH=0
fi
if [ "$SKILL_NEEDS_PATCH" = "1" ]; then
  echo "[caveman-kit] Backing up SKILL.md for frontmatter patch..."
  if cp "$SKILL_PATH" "$BACKUP_DIR/SKILL.md.bak"; then
    SKILL_BACKUP_JSON="\"$BACKUP_DIR/SKILL.md.bak\""
    # Update manifest with skill backup before patch
    write_manifest "$BACKUP_DIR/settings.json.bak" "$STATUSLINE_BACKUP_JSON" "\"$BACKUP_DIR/SKILL.md.bak\"" "$PLUGIN_ROOT" "$SKILL_INSTALLED_BY_KIT" "false"
  else
    echo "[caveman-kit] warning: could not back up SKILL.md — skipping frontmatter patch" >&2
    SKILL_NEEDS_PATCH=0
  fi
fi

# Disable trap on success path
trap - ERR

if [ "$SKILL_NEEDS_PATCH" = "1" ]; then
  echo "[caveman-kit] Patching SKILL.md frontmatter..."
  if ! node "$KIT_DIR/lib/skill-patch.js" "$SKILL_PATH"; then
    echo "[caveman-kit] warning: failed to patch SKILL.md frontmatter — skill installed without disable-model-invocation" >&2
  fi
fi

# Final manifest write with completed=true
write_manifest "$BACKUP_DIR/settings.json.bak" "$STATUSLINE_BACKUP_JSON" "$SKILL_BACKUP_JSON" "$PLUGIN_ROOT" "$SKILL_INSTALLED_BY_KIT" "true"

echo
echo "[caveman-kit] caveman-kit installed to $KIT_HOME"
echo "To uninstall: $KIT_HOME/uninstall.sh"
echo "Restart Claude Code for the hooks to take effect."
