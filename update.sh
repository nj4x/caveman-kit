#!/usr/bin/env bash
# caveman-kit in-place update script.
#
# Updates the kit and the kit-installed skills without uninstalling.
# Requires an existing manifest.json (from a prior successful install).
# Patches are idempotent; if nothing changed, exits 0 with "already up to date".
#
# Order (ADR 0021 decision 5): the kit step runs first and only when the kit
# has new commits; it then re-execs the pulled copy of this script, so the
# skill steps always run the new code under the new hooks. The skill steps run
# on every run: presence step (no network), upgrade check, pending ultracave.
set -euo pipefail

print_help() {
  cat <<EOF
Usage: update.sh [--help]

In-place update for caveman-kit. Checks for new kit commits, repatches
settings.json and statusline.sh, and copies updated hook files. Then checks
upstream for a newer skill release and upgrades the skills the kit installed
(manifest skillInstalledByKit / ultracaveInstalledByKit); a skill you manage
yourself is never touched. Also re-resolves the skill location the hooks read
(pluginRoot) and warns if SKILL.md is unreadable there.

CAVEMAN_KIT_SKILL_REF=vX.Y.Z holds the skills at that release tag (kept in the
manifest until CAVEMAN_KIT_SKILL_REF=latest clears it).

Requires an existing manifest.json from a prior install. First install still
requires bootstrap.sh.

Exit 0 if update succeeds or nothing is new. Non-zero on error.
EOF
}

[ "${1:-}" = "--help" ] && print_help && exit 0

# ===== Setup =====

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_HOME="$HOME/.caveman-kit"
MANIFEST="$KIT_HOME/manifest.json"

# shellcheck source=lib/skills.sh
. "$KIT_DIR/lib/skills.sh"

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

# mget <key>: the raw JSON value, or "absent". mget_str: the string value or "".
mget() {
  node "$KIT_DIR/lib/manifest.js" get "$MANIFEST" "$1"
}
mget_str() {
  local v
  v="$(mget "$1")"
  case "$v" in
    \"*\") v="${v#\"}"; echo "${v%\"}" ;;
    *) echo "" ;;
  esac
}
mset() {
  node "$KIT_DIR/lib/manifest.js" set "$MANIFEST" "$1" "$2" || fail "could not write $1 to the manifest"
}
# mset_str <key> <string>: the string goes in as argv, never spliced into JSON.
mset_str() {
  node "$KIT_DIR/lib/manifest.js" setstr "$MANIFEST" "$1" "$2" || fail "could not write $1 to the manifest"
}

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

# Booleans are read with mget: the parse_manifest grep fallback (no jq) only
# extracts quoted string values.
SKILL_INSTALLED_BY_KIT="$(mget skillInstalledByKit)" || fail "could not read the manifest"
[ "$SKILL_INSTALLED_BY_KIT" = "true" ] || SKILL_INSTALLED_BY_KIT="false"

SETTINGS="$CLAUDE_DIR/settings.json"
STATUSLINE="$CLAUDE_DIR/statusline.sh"
SKILL_PATH="$CLAUDE_DIR/skills/caveman/SKILL.md"

[ ! -f "$SETTINGS" ] && fail "settings.json not found at $SETTINGS"

# Hooks read SKILL.md from PLUGIN_ROOT, frozen into settings.json at install.
# Re-resolve it exactly as install.sh does, so a skill dir that was moved or
# replaced (e.g. a symlink swapped for a real copy) cannot leave hooks reading
# a stale or missing file.
PLUGIN_ROOT_DRIFTED=0
refresh_plugin_root() {
  [ -f "$SKILL_PATH" ] || return 0
  local live_root
  live_root="$(cd -P "$(dirname "$SKILL_PATH")/../.." && pwd)"
  if [ "$live_root" != "$PLUGIN_ROOT" ]; then
    echo "[caveman-kit update] Skill location changed: $PLUGIN_ROOT -> $live_root"
    PLUGIN_ROOT="$live_root"
    PLUGIN_ROOT_DRIFTED=1
  fi
}

save_plugin_root() {
  if [ "$PLUGIN_ROOT_DRIFTED" = "1" ]; then
    mset_str pluginRoot "$PLUGIN_ROOT"
    PLUGIN_ROOT_DRIFTED=0
  fi
}

repatch_settings() {
  node "$KIT_DIR/lib/settings-unpatch.js" "$SETTINGS" || fail "settings unpatch failed"
  node "$KIT_DIR/lib/settings-patch.js" "$SETTINGS" "$KIT_HOME/hooks" "$PLUGIN_ROOT" || fail "settings repatch failed"
}

health_check() {
  if [ ! -r "$PLUGIN_ROOT/skills/caveman/SKILL.md" ]; then
    echo "[caveman-kit update] warning: hooks read $PLUGIN_ROOT/skills/caveman/SKILL.md but it is missing or unreadable; caveman rules will not load until the skill is restored there" >&2
  fi
}

refresh_plugin_root

# ===== Git check =====

if [ ! -d "$KIT_DIR/.git" ]; then
  fail "$KIT_DIR is not a git repository"
fi

cd "$KIT_DIR"

git fetch origin master 2>/dev/null || git fetch origin 2>/dev/null || fail "git fetch failed"

# Detect default branch (could be master or main)
REMOTE_HEAD="$(git symbolic-ref refs/remotes/origin/HEAD | sed 's|.*/||' 2>/dev/null || echo 'master')"
REMOTE_SHA="$(git rev-parse origin/$REMOTE_HEAD 2>/dev/null || git rev-parse origin/master 2>/dev/null || fail "could not resolve origin branch")"

CHANGED=0

# ===== Kit step (only with new commits) =====

if [ -z "${CAVEMAN_KIT_UPDATE_REEXEC:-}" ] && [ "$REMOTE_SHA" != "$CURRENT_KIT_SHA" ]; then
  if [ "$CURRENT_KIT_SHA" = "none" ]; then
    echo "[caveman-kit update] Initial update detected (no prior kitSha in manifest)"
  else
    echo "[caveman-kit update] New commits available ($CURRENT_KIT_SHA → $REMOTE_SHA)"
  fi

  echo "[caveman-kit update] Unpatching settings.json..."
  node "$KIT_DIR/lib/settings-unpatch.js" "$SETTINGS" || fail "settings unpatch failed"

  if [ -f "$STATUSLINE" ] && [ ! -L "$STATUSLINE" ]; then
    echo "[caveman-kit update] Unpatching statusline.sh..."
    node "$KIT_DIR/lib/statusline-unpatch.js" "$STATUSLINE" || fail "statusline unpatch failed"
  fi

  echo "[caveman-kit update] Pulling latest kit..."
  git -C "$KIT_DIR" pull origin $REMOTE_HEAD --ff-only || fail "git pull failed"

  echo "[caveman-kit update] Copying hook files..."
  cp "$KIT_DIR"/hooks/*.js "$KIT_HOME/hooks/" || fail "could not copy hook scripts"
  cp "$KIT_DIR"/hooks/*.md "$KIT_HOME/hooks/" 2>/dev/null || true

  echo "[caveman-kit update] Repatching settings.json..."
  node "$KIT_DIR/lib/settings-patch.js" "$SETTINGS" "$KIT_HOME/hooks" "$PLUGIN_ROOT" || fail "settings repatch failed"

  if [ -f "$STATUSLINE" ] && [ ! -L "$STATUSLINE" ]; then
    echo "[caveman-kit update] Repatching statusline.sh..."
    node "$KIT_DIR/lib/statusline-patch.js" "$STATUSLINE" || fail "statusline repatch failed"
  fi

  save_plugin_root
  mset_str kitSha "$(git -C "$KIT_DIR" rev-parse HEAD)"
  echo "[caveman-kit update] caveman-kit updated to $(git -C "$KIT_DIR" rev-parse HEAD | cut -c1-8)"

  # The script that just ran is the pre-pull copy. Run the pulled one for the
  # skill steps, so they never run old code under new hooks.
  CAVEMAN_KIT_UPDATE_REEXEC=1 exec bash "$KIT_DIR/update.sh"
fi

if [ -z "${CAVEMAN_KIT_UPDATE_REEXEC:-}" ]; then
  echo "[caveman-kit update] Kit is already up to date (SHA: $REMOTE_SHA)"
else
  CHANGED=1
fi

# ===== Skill steps (every run) =====

# Optional override from the environment (ADR 0021 decision 3).
OVERRIDE="$(mget_str skillRefOverride)"
LOOKUP_BLOCKED=0
ENV_REF="${CAVEMAN_KIT_SKILL_REF:-}"
if [ -n "$ENV_REF" ]; then
  if [ "$ENV_REF" = "latest" ]; then
    if [ -n "$OVERRIDE" ]; then
      node "$KIT_DIR/lib/manifest.js" unset "$MANIFEST" skillRefOverride || fail "could not clear skillRefOverride"
      echo "[caveman-kit update] Skill tag hold cleared"
    fi
    OVERRIDE=""
  elif check_override "$ENV_REF"; then
    OVERRIDE="$ENV_REF"
    mset_str skillRefOverride "$ENV_REF"
  else
    echo "[caveman-kit update] warning: CAVEMAN_KIT_SKILL_REF=$ENV_REF rejected: expected vX.Y.Z at or above $SKILL_MIN_TAG; keeping the installed skills" >&2
    LOOKUP_BLOCKED=1
  fi
fi
# A hand-edited hold is validated like the variable (ADR 0021 decision 3).
if [ -n "$OVERRIDE" ] && [ "$LOOKUP_BLOCKED" = "0" ] && ! check_override "$OVERRIDE"; then
  echo "[caveman-kit update] warning: skillRefOverride=$OVERRIDE in the manifest is not a vX.Y.Z tag at or above $SKILL_MIN_TAG; keeping the installed skills (CAVEMAN_KIT_SKILL_REF=latest clears it)" >&2
  LOOKUP_BLOCKED=1
fi
[ -n "$OVERRIDE" ] && echo "[caveman-kit update] Skill tag held at $OVERRIDE (CAVEMAN_KIT_SKILL_REF=latest clears the hold)"

# Presence step: no network. Settles ultracaveInstalledByKit from what is on
# disk (ADR 0020 decision 7).
ULTRA="$(mget ultracaveInstalledByKit)"
if [ "$ULTRA" = "absent" ]; then
  # Legacy manifest: keyed on who owns caveman, since a legacy manifest cannot
  # tell --no-install-skill from a user-managed caveman.
  if [ "$SKILL_INSTALLED_BY_KIT" = "true" ]; then ULTRA="null"; else ULTRA="false"; fi
  mset ultracaveInstalledByKit "$ULTRA"
fi
if [ "$ULTRA" = "null" ] && ultracave_present "$CLAUDE_DIR"; then
  ULTRA="false"
  mset ultracaveInstalledByKit false
fi
if [ "$ULTRA" = "true" ] && ! ultracave_present "$CLAUDE_DIR"; then
  echo "[caveman-kit update] ultracave was removed; leaving it removed (ultra falls back to the caveman rules)"
  ULTRA="false"
  mset ultracaveInstalledByKit false
fi

[ "$SKILL_INSTALLED_BY_KIT" = "true" ] || echo "[caveman-kit update] Skill not kit-managed, skipped (upgrade it yourself; releases: $SKILL_RELEASES_URL)"

NEED_UPGRADE=0
{ [ "$SKILL_INSTALLED_BY_KIT" = "true" ] || [ "$ULTRA" = "true" ]; } && NEED_UPGRADE=1
NEED_PENDING=0
[ "$ULTRA" = "null" ] && NEED_PENDING=1

if [ "$LOOKUP_BLOCKED" = "1" ] && [ "$NEED_PENDING" = "1" ]; then
  # Pinned to the held tag when it is valid, else to skillRef (ADR 0021 decision 7).
  CMD_TAG="$(mget_str skillRef)"
  if [ -n "$OVERRIDE" ] && check_override "$OVERRIDE"; then CMD_TAG="$OVERRIDE"; fi
  echo "[caveman-kit update] ultracave is still pending; to install it now: $(manual_skill_cmd ultracave "$CMD_TAG")" >&2
fi

TAG=""
if [ "$LOOKUP_BLOCKED" = "0" ] && { [ "$NEED_UPGRADE" = "1" ] || [ "$NEED_PENDING" = "1" ]; }; then
  SKILL_REF="$(mget_str skillRef)"
  if [ -n "$OVERRIDE" ]; then
    TAG="$OVERRIDE"
  elif ! TAG="$(latest_release_tag)"; then
    TAG=""
    echo "[caveman-kit update] warning: could not resolve the latest $SKILL_REPO release tag (network, git, or no vX.Y.Z tags); keeping the installed skills" >&2
    if [ "$NEED_PENDING" = "1" ]; then
      echo "[caveman-kit update] ultracave is still pending; to install it now: $(manual_skill_cmd ultracave "$SKILL_REF")" >&2
    fi
  fi
fi

CAVEMAN_FAILED=0
if [ -n "$TAG" ]; then
  SKILL_REF="$(mget_str skillRef)"

  DO_UPGRADE=0
  if [ "$NEED_UPGRADE" = "1" ]; then
    if [ -n "$OVERRIDE" ]; then
      [ "$TAG" != "$SKILL_REF" ] && DO_UPGRADE=1
    elif [ -z "$SKILL_REF" ]; then
      DO_UPGRADE=1
    elif [ "$TAG" != "$SKILL_REF" ]; then
      if tag_ge "$TAG" "$SKILL_REF"; then
        DO_UPGRADE=1
      else
        echo "[caveman-kit update] warning: latest release $TAG is older than the installed $SKILL_REF; keeping the installed skills (hold a tag with CAVEMAN_KIT_SKILL_REF to downgrade)" >&2
      fi
    fi
  fi

  if [ "$DO_UPGRADE" = "1" ]; then
    REINSTALLED=0
    ALL_OK=1

    if [ "$SKILL_INSTALLED_BY_KIT" = "true" ]; then
      echo "[caveman-kit update] Upgrading caveman skill ($SKILL_REPO@$TAG)..."
      if install_skill "$TAG" caveman; then
        REINSTALLED=$((REINSTALLED + 1))
        # The reinstall replaces SKILL.md, dropping the ADR 0002 patch.
        if ! node "$KIT_DIR/lib/skill-patch.js" "$SKILL_PATH"; then
          echo "[caveman-kit update] warning: could not patch caveman frontmatter; the model can auto-invoke caveman until the next run" >&2
          ALL_OK=0
          CAVEMAN_FAILED=1
        fi
      else
        echo "[caveman-kit update] warning: caveman upgrade failed; keeping the old skillRef" >&2
        ALL_OK=0
        CAVEMAN_FAILED=1
      fi
    fi

    if [ "$ULTRA" = "true" ]; then
      echo "[caveman-kit update] Upgrading ultracave skill ($SKILL_REPO@$TAG)..."
      if install_skill "$TAG" ultracave; then
        UC_RC=0
      else
        UC_RC=1
      fi
      if ! ultracave_present "$CLAUDE_DIR"; then
        echo "[caveman-kit update] warning: ultracave is not present after the upgrade; marking it pending" >&2
        ULTRA="null"
        mset ultracaveInstalledByKit null
        ALL_OK=0
      elif [ "$UC_RC" -ne 0 ]; then
        echo "[caveman-kit update] warning: ultracave upgrade failed; the previous copy stays in place" >&2
        ALL_OK=0
      else
        REINSTALLED=$((REINSTALLED + 1))
      fi
    fi

    if [ "$ALL_OK" = "1" ] && [ "$REINSTALLED" -ge 1 ]; then
      mset_str skillRef "$TAG"
      CHANGED=1
    else
      echo "[caveman-kit update] skillRef stays at ${SKILL_REF:-unset}; the next run retries" >&2
    fi
  fi

  # Pending step: runs whenever ultracave is still null, even with an
  # unchanged tag (ADR 0021 decision 5).
  if [ "$ULTRA" = "null" ]; then
    echo "[caveman-kit update] Installing ultracave skill ($SKILL_REPO@$TAG)..."
    if install_skill "$TAG" ultracave && ultracave_present "$CLAUDE_DIR"; then
      ULTRA="true"
      mset ultracaveInstalledByKit true
      # skillRef is written here only when it is still null, and never after a
      # failed caveman upgrade this run: that would hide the caveman retry.
      if [ -z "$(mget_str skillRef)" ] && [ "$CAVEMAN_FAILED" = "0" ]; then
        mset_str skillRef "$TAG"
      fi
      CHANGED=1
    else
      echo "[caveman-kit update] warning: ultracave install failed; ultra uses the caveman rules and the next run retries. Install it now with: $(manual_skill_cmd ultracave "$TAG")" >&2
    fi
  fi
fi

# ===== Plugin root =====

refresh_plugin_root
if [ "$PLUGIN_ROOT_DRIFTED" = "1" ]; then
  echo "[caveman-kit update] Repatching settings.json for new skill location..."
  repatch_settings
  save_plugin_root
  CHANGED=1
fi

health_check

if [ "$CHANGED" = "1" ]; then
  echo
  echo "Restart Claude Code for the updates to take effect."
fi
