# Shared bats helpers: a fake upstream (local git repo with release tags) and a
# stub `npx` that records its calls and writes skill files. No network.
#
# Env knobs for the stub npx:
#   NPX_FAIL=<skill>      exit 1 for that skill, write nothing
#   NPX_NOWRITE=<skill>   exit 0 for that skill but write no SKILL.md
#   NPX_WIPE=<skill>      exit 0 for that skill after deleting its directory
# Calls are logged to $HOME/npx.log, one line per call: "<skill> <repo@tag>".

# make_upstream <tag>...: creates $HOME/upstream.git with the given tags.
make_upstream() {
  local w="$HOME/upstream-work" t
  rm -rf "$w" "$HOME/upstream.git"
  git init -q "$w"
  git -C "$w" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
  for t in "$@"; do git -C "$w" tag "$t"; done
  git clone -q --bare "$w" "$HOME/upstream.git"
  export CAVEMAN_KIT_SKILL_REMOTE="file://$HOME/upstream.git"
}

# install_npx_stub: puts a fake npx first on PATH.
install_npx_stub() {
  mkdir -p "$HOME/bin"
  cat > "$HOME/bin/npx" <<'STUB'
#!/usr/bin/env bash
skill=""; ref=""
while [ $# -gt 0 ]; do
  case "$1" in
    --skill) skill="$2"; shift ;;
    JuliusBrussee/caveman@*) ref="$1" ;;
  esac
  shift
done
echo "$skill $ref" >> "$HOME/npx.log"
[ "${NPX_FAIL:-}" = "$skill" ] && exit 1
[ "${NPX_NOWRITE:-}" = "$skill" ] && exit 0
if [ "${NPX_WIPE:-}" = "$skill" ]; then rm -rf "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/$skill"; exit 0; fi
dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/$skill"
mkdir -p "$dir"
printf -- '---\nname: %s\n---\n# %s from %s\n' "$skill" "$skill" "$ref" > "$dir/SKILL.md"
exit 0
STUB
  chmod +x "$HOME/bin/npx"
  export PATH="$HOME/bin:$PATH"
  : > "$HOME/npx.log"
}

# manifest_get <key>: "absent" or the JSON value.
manifest_get() {
  node "$KIT_DIR/lib/manifest.js" get "$HOME/.caveman-kit/manifest.json" "$1"
}
