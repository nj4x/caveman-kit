#!/usr/bin/env bats
# One case table, two badge copies (ADR 0022 decision 12): the shell block
# lib/statusline-patch.js puts in statusline.sh, and the desktop mod's helper
# plugins/caveman-badge/hooks/badge.mjs. Each case states the expected mode
# (none, lite, full, ultra) for both, since ADR 0023 gave them different
# drawings; they differ only on the known shell divergences marked below.

setup_file() {
  export KIT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export PATCHED_STATUSLINE="$BATS_FILE_TMPDIR/statusline.sh"
  printf '#!/bin/bash\necho line\n' > "$PATCHED_STATUSLINE"
  node "$KIT_DIR/lib/statusline-patch.js" "$PATCHED_STATUSLINE" > /dev/null
  grep -q "CAVEMAN-KIT BEGIN" "$PATCHED_STATUSLINE"
}

setup() {
  export HOME="$(mktemp -d)"
  unset CLAUDE_CONFIG_DIR
  mkdir -p "$HOME/.claude" "$HOME/.caveman-kit/hooks" "$HOME/repo/.git"
  : > "$HOME/.caveman-kit/hooks/caveman-activate.js"
}

teardown() { rm -rf "$HOME"; }

# shell_mode <cwd> / mod_mode <cwd>: print the resolved mode, or none.
# A crash prints CRASH, so rows expecting none cannot pass on a crash.
shell_mode() {
  local out badge
  out="$(cd "$1" && bash "$PATCHED_STATUSLINE")" || { echo CRASH; return; }
  case "$out" in *line) ;; *) echo CRASH; return ;; esac
  badge="$(printf '%s' "$out" | head -1 | sed 's/ *line$//; s/ *$//')"
  case "$badge" in
    '') echo none ;;
    '[CAVEMAN]') echo full ;;
    '[CAVEMAN:LITE]') echo lite ;;
    '[CAVEMAN:ULTRA]') echo ultra ;;
    *) echo CRASH ;;
  esac
}
mod_mode() { node "$KIT_DIR/tests/helpers/badge-run.mjs" "$HOME" "$1" || echo CRASH; }

# expect <cwd> <shell expected> <mod expected>
expect() {
  [ "$(shell_mode "$1")" = "$2" ]
  [ "$(mod_mode "$1")" = "$3" ]
}

@test "repo flag wins over global" {
  mkdir -p "$HOME/repo/.claude"
  printf lite > "$HOME/repo/.claude/.caveman-mode"; printf ultra > "$HOME/.claude/.caveman-active"
  expect "$HOME/repo" "lite" "lite"
}

@test "repo flag found from a subdirectory" {
  mkdir -p "$HOME/repo/.claude" "$HOME/repo/a/b"
  printf full > "$HOME/repo/.claude/.caveman-mode"
  expect "$HOME/repo/a/b" "full" "full"
}

@test "repo .claude without flag falls back to global" {
  mkdir -p "$HOME/repo/.claude"; printf ultra > "$HOME/.claude/.caveman-active"
  expect "$HOME/repo" "ultra" "ultra"
}

@test "global flag only, outside any repo" {
  mkdir -p "$HOME/plain"; printf lite > "$HOME/.claude/.caveman-active"
  expect "$HOME/plain" "lite" "lite"
}

@test "CLAUDE_CONFIG_DIR relocates the global flag" {
  export CLAUDE_CONFIG_DIR="$HOME/cfg"; mkdir -p "$CLAUDE_CONFIG_DIR" "$HOME/plain"
  printf ultra > "$CLAUDE_CONFIG_DIR/.caveman-active"; printf lite > "$HOME/.claude/.caveman-active"
  expect "$HOME/plain" "ultra" "ultra"
}

@test "no flag draws nothing" {
  expect "$HOME/repo" "none" "none"
}

@test "invalid flag draws nothing" {
  printf bogus > "$HOME/.claude/.caveman-active"
  expect "$HOME/repo" "none" "none"
}

@test "off draws nothing" {
  printf off > "$HOME/.claude/.caveman-active"
  expect "$HOME/repo" "none" "none"
}

@test "uppercase and trailing newline are normalized" {
  printf 'ULTRA\n' > "$HOME/.claude/.caveman-active"
  expect "$HOME/repo" "ultra" "ultra"
}

@test "symlinked flag draws nothing" {
  printf ultra > "$HOME/real-flag"; ln -s "$HOME/real-flag" "$HOME/.claude/.caveman-active"
  expect "$HOME/repo" "none" "none"
}

# Known shell divergence: the mod falls back to global as the hooks do, the
# shell block stops at the rejected repo flag.
@test "symlinked repo flag (mod falls back to global, shell draws nothing)" {
  mkdir -p "$HOME/repo/.claude"; printf lite > "$HOME/real-flag"
  ln -s "$HOME/real-flag" "$HOME/repo/.claude/.caveman-mode"; printf ultra > "$HOME/.claude/.caveman-active"
  expect "$HOME/repo" "none" "ultra"
}

@test "invalid repo flag (mod falls back to global, shell draws nothing)" {
  mkdir -p "$HOME/repo/.claude"; printf bogus > "$HOME/repo/.claude/.caveman-mode"
  printf ultra > "$HOME/.claude/.caveman-active"
  expect "$HOME/repo" "none" "ultra"
}

@test "repo off over a global mode draws nothing" {
  mkdir -p "$HOME/repo/.claude"; printf off > "$HOME/repo/.claude/.caveman-mode"
  printf ultra > "$HOME/.claude/.caveman-active"
  expect "$HOME/repo" "none" "none"
}

# Known shell divergence: [ -f ] follows a symlinked .claude/, the mod does not.
@test "symlinked .claude/ (shell follows it, mod falls back to global)" {
  mkdir -p "$HOME/evil"; printf lite > "$HOME/evil/.caveman-mode"
  ln -s "$HOME/evil" "$HOME/repo/.claude"; printf ultra > "$HOME/.claude/.caveman-active"
  expect "$HOME/repo" "lite" "ultra"
}

# Known shell divergence: head -c 16 reads an oversized file, the mod rejects it.
@test "flag larger than 16 bytes (shell reads 16, mod rejects)" {
  printf 'ultra%30s' '' > "$HOME/.claude/.caveman-active"
  expect "$HOME/repo" "ultra" "none"
}

# Mod only: an unreadable repo flag falls back to global as the hooks do (the
# shell block's [ -f ] passes, head fails quietly, so it draws nothing).
@test "unreadable repo flag (mod falls back to global, shell draws nothing)" {
  mkdir -p "$HOME/repo/.claude"; printf lite > "$HOME/repo/.claude/.caveman-mode"
  chmod 000 "$HOME/repo/.claude/.caveman-mode"; printf ultra > "$HOME/.claude/.caveman-active"
  expect "$HOME/repo" "none" "ultra"
}

# Mod only: decision 11. The shell block leaves with the kit on uninstall.
@test "mod draws nothing when the kit marker is missing" {
  printf ultra > "$HOME/.claude/.caveman-active"
  [ "$(mod_mode "$HOME/repo")" = "ultra" ]
  rm "$HOME/.caveman-kit/hooks/caveman-activate.js"
  [ "$(mod_mode "$HOME/repo")" = "none" ]
}
