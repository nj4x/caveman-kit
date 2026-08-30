#!/usr/bin/env bash
# caveman-kit bootstrap script.
#
# Clone-free installation: fetches the repo and runs install.sh.
# Supports environment variable overrides for repo URL and install location.
set -euo pipefail

REPO_URL="${CAVEMAN_KIT_GIT_REPO:-https://github.com/nj4x/caveman-kit.git}"
INSTALL_DIR="${CAVEMAN_KIT_INSTALL_DIR:-$HOME/.local/share/caveman-kit}"

echo "[caveman-kit bootstrap] Checking prerequisites..."

if ! command -v git >/dev/null 2>&1; then
  echo "[caveman-kit bootstrap] error: git not found on PATH" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "[caveman-kit bootstrap] error: curl not found on PATH" >&2
  exit 1
fi

if [ -d "$INSTALL_DIR/.git" ]; then
  echo "[caveman-kit bootstrap] Updating existing checkout at $INSTALL_DIR..."
  git -C "$INSTALL_DIR" pull --ff-only
else
  echo "[caveman-kit bootstrap] Cloning caveman-kit to $INSTALL_DIR..."
  mkdir -p "$(dirname "$INSTALL_DIR")"
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

exec "$INSTALL_DIR/install.sh" "$@"
