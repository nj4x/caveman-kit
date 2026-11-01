#!/usr/bin/env bats
# bats-core tests for caveman-activate.js hook output.
#
# The hook takes no arguments: it reads the session's cwd from stdin JSON and
# resolves the mode flag from the repo-scoped file, then the global one.

setup() {
  export HOME="$(mktemp -d)"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  export KIT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

  mkdir -p "$CLAUDE_CONFIG_DIR/skills/caveman"
  # Minimal SKILL.md fixture in the upstream v4.0.1 shape: no intensity table,
  # a "wenyan" alias line, mode-agnostic rules.
  cat > "$CLAUDE_CONFIG_DIR/skills/caveman/SKILL.md" <<'SKILL'
---
name: caveman
disable-model-invocation: true
---

Respond terse like smart caveman. All technical substance stay. Only fluff die.

Default: **full**. Switch: `/caveman lite|full|ultra|wenyan-lite|wenyan-full|wenyan-ultra|off`.

`/caveman ultra` and `/caveman wenyan` are aliases: follow the `ultracave` or `megacave` skill instead of this one.

## Rules

CAVEMAN-BODY-MARKER Drop: articles (a/an/the), filler (just/really/basically/actually/simply), pleasantries, hedging. Fragments OK. Short synonyms.

Classical chars = wenyan modes only. Never swap a word to a classical char to shrink at non-wenyan levels.
SKILL
  install_ultracave "$CLAUDE_CONFIG_DIR"

  export CLAUDE_PLUGIN_ROOT="$CLAUDE_CONFIG_DIR"
}

teardown() {
  rm -rf "$HOME"
}

# Writes an ultracave fixture (upstream shape) under <root>/skills/ultracave.
# Its body contains lines that look like caveman's mode bullets, to prove the
# ultracave body is injected unfiltered.
install_ultracave() {
  mkdir -p "$1/skills/ultracave"
  cat > "$1/skills/ultracave/SKILL.md" <<'SKILL'
---
name: ultracave
disable-model-invocation: true
---

# ultracave

ULTRACAVE-BODY-MARKER Respond terse like smart caveman. Then cut again.

- lite: ultracave line that looks like a mode bullet
- wenyan note kept because the ultracave body is not filtered
SKILL
}

# Extracts additionalContext from the JSON hookSpecificOutput envelope.
# Non-JSON output (stderr-only failure paths, merged via 2>&1) passes through
# unchanged. The JSON envelope shape itself is guarded by the tests asserting
# on raw hookEventName/additionalContext keys.
run_hook() {
  local payload
  if [ "$#" -eq 0 ]; then
    payload='{}'
  else
    payload="$(printf '{"cwd":"%s"}' "$1")"
  fi
  printf '%s' "$payload" | node "$KIT_DIR/hooks/caveman-activate.js" 2>&1 | node -e '
    let raw = "";
    process.stdin.on("data", c => { raw += c; });
    process.stdin.on("end", () => {
      if (!raw) { process.stdout.write(""); return; }
      try {
        const parsed = JSON.parse(raw);
        process.stdout.write((parsed.hookSpecificOutput && parsed.hookSpecificOutput.additionalContext) || "");
      } catch (e) {
        process.stdout.write(raw);
      }
    });
  '
}

# Creates a git repo with a .claude/ dir holding the given mode, echoes its path.
make_repo() {
  local root="$HOME/repo"
  mkdir -p "$root/.claude"
  git -C "$root" init -q
  echo "$1" > "$root/.claude/.caveman-mode"
  echo "$root"
}

@test "falls back to the global flag when no repo-scoped file exists" {
  echo "full" > "$CLAUDE_CONFIG_DIR/.caveman-active"

  output="$(run_hook)"

  [[ "$output" == *"CAVEMAN MODE ACTIVE — level: full"* ]] || false
  [[ "$output" == *"CAVEMAN-BODY-MARKER"* ]] || false
}

@test "prefers the repo-scoped flag over the global one" {
  echo "full" > "$CLAUDE_CONFIG_DIR/.caveman-active"
  repo="$(make_repo ultra)"

  output="$(run_hook "$repo")"

  [[ "$output" == *"CAVEMAN MODE ACTIVE — level: ultra"* ]] || false
  [[ "$output" == *"ULTRACAVE-BODY-MARKER"* ]] || false
}

@test "lite and full inject the caveman body, not the ultracave body" {
  for mode in lite full; do
    echo "$mode" > "$CLAUDE_CONFIG_DIR/.caveman-active"

    output="$(run_hook)"

    [[ "$output" == *"CAVEMAN-BODY-MARKER"* ]] || false
    [[ "$output" != *"ULTRACAVE-BODY-MARKER"* ]] || false
  done
}

@test "ultra injects the ultracave body in place of the caveman body, unfiltered" {
  echo "ultra" > "$CLAUDE_CONFIG_DIR/.caveman-active"

  output="$(run_hook)"

  [[ "$output" == *"ULTRACAVE-BODY-MARKER"* ]] || false
  [[ "$output" != *"CAVEMAN-BODY-MARKER"* ]] || false
  [[ "$output" == *"- lite: ultracave line that looks like a mode bullet"* ]] || false
  [[ "$output" == *"- wenyan note kept"* ]] || false
  [[ "$output" != *"name: ultracave"* ]] || false
}

@test "ultra appends only the ultra example lines to the ultracave body" {
  echo "ultra" > "$CLAUDE_CONFIG_DIR/.caveman-active"

  output="$(run_hook)"

  [[ "$output" == *"- ultra: \"Threads hit same resource unsync"* ]] || false
  [[ "$output" != *"- full: \"Two threads hit same resource"* ]] || false
  [[ "$output" != *"- lite: \"A race condition occurs"* ]] || false
}

@test "ultra reads ultracave from the config dir when the plugin root has none" {
  echo "ultra" > "$CLAUDE_CONFIG_DIR/.caveman-active"
  other="$HOME/shared-store"
  mkdir -p "$other/skills/caveman"
  cp "$CLAUDE_CONFIG_DIR/skills/caveman/SKILL.md" "$other/skills/caveman/SKILL.md"
  export CLAUDE_PLUGIN_ROOT="$other"

  output="$(run_hook)"

  [[ "$output" == *"ULTRACAVE-BODY-MARKER"* ]] || false
}

@test "ultra falls back to the caveman body with a stderr line when ultracave is missing" {
  echo "ultra" > "$CLAUDE_CONFIG_DIR/.caveman-active"
  rm -rf "$CLAUDE_CONFIG_DIR/skills/ultracave"

  output="$(run_hook)"

  [[ "$output" == *"CAVEMAN MODE ACTIVE — level: ultra"* ]] || false
  [[ "$output" == *"CAVEMAN-BODY-MARKER"* ]] || false
  [[ "$output" == *"ultracave skill not found or empty"* ]] || false
}

@test "ultra falls back when the ultracave body after frontmatter is empty" {
  echo "ultra" > "$CLAUDE_CONFIG_DIR/.caveman-active"
  printf -- '---\nname: ultracave\n---\n\n' > "$CLAUDE_CONFIG_DIR/skills/ultracave/SKILL.md"

  output="$(run_hook)"

  [[ "$output" == *"CAVEMAN-BODY-MARKER"* ]] || false
  [[ "$output" != *"ULTRACAVE-BODY-MARKER"* ]] || false
}

@test "ultra still exits 0 when neither ultracave nor caveman is readable" {
  echo "ultra" > "$CLAUDE_CONFIG_DIR/.caveman-active"
  rm -rf "$CLAUDE_CONFIG_DIR/skills/ultracave"
  export CLAUDE_PLUGIN_ROOT="$HOME/absent"

  run bash -c "printf '{}' | node '$KIT_DIR/hooks/caveman-activate.js'"

  [ "$status" -eq 0 ]
}

@test "every mode is resolvable from the global flag" {
  for mode in lite full ultra; do
    echo "$mode" > "$CLAUDE_CONFIG_DIR/.caveman-active"

    output="$(run_hook)"

    [[ "$output" == *"CAVEMAN MODE ACTIVE — level: $mode"* ]] || false
  done
}

@test "off mode emits nothing and clears the flag" {
  echo "off" > "$CLAUDE_CONFIG_DIR/.caveman-active"

  output="$(run_hook)"

  [ -z "$output" ]
  [ ! -f "$CLAUDE_CONFIG_DIR/.caveman-active" ]
}

@test "reports the skill path on stderr when SKILL.md is unreadable" {
  echo "full" > "$CLAUDE_CONFIG_DIR/.caveman-active"
  export CLAUDE_PLUGIN_ROOT="$HOME/absent"

  output="$(run_hook)"

  [[ "$output" == *"could not read"* ]] || false
  [[ "$output" == *"SKILL.md"* ]] || false
}

@test "defaults hookEventName to SessionStart when the input omits it" {
  echo "full" > "$CLAUDE_CONFIG_DIR/.caveman-active"

  raw="$(printf '{}' | node "$KIT_DIR/hooks/caveman-activate.js")"

  [[ "$raw" == *'"hookEventName":"SessionStart"'* ]] || false
  [[ "$raw" == *'"additionalContext"'* ]] || false
}

@test "echoes hook_event_name back so SubagentStart deliveries are accepted" {
  echo "full" > "$CLAUDE_CONFIG_DIR/.caveman-active"

  raw="$(printf '{"hook_event_name":"SubagentStart"}' | node "$KIT_DIR/hooks/caveman-activate.js")"

  [[ "$raw" == *'"hookEventName":"SubagentStart"'* ]] || false
  [[ "$raw" == *'"additionalContext"'* ]] || false
  [[ "$raw" == *"CAVEMAN MODE ACTIVE"* ]] || false
}

@test "honors the repo-scoped mode flag via cwd under SubagentStart" {
  echo "full" > "$CLAUDE_CONFIG_DIR/.caveman-active"
  repo="$(make_repo ultra)"

  raw="$(printf '{"cwd":"%s","hook_event_name":"SubagentStart"}' "$repo" | node "$KIT_DIR/hooks/caveman-activate.js")"

  [[ "$raw" == *'"hookEventName":"SubagentStart"'* ]] || false
  [[ "$raw" == *"CAVEMAN MODE ACTIVE — level: ultra"* ]] || false
}

@test "appends the active mode's supplemental example, not other modes'" {
  echo "full" > "$CLAUDE_CONFIG_DIR/.caveman-active"

  output="$(run_hook)"

  [[ "$output" == *"- full: \"Two threads hit same resource, race."* ]] || false
  [[ "$output" != *"- lite: \"A race condition occurs"* ]] || false
  [[ "$output" != *"- ultra: \"Threads hit same resource unsync"* ]] || false
}

@test "strips wenyan mentions from the pinned upstream skill's prose" {
  echo "full" > "$CLAUDE_CONFIG_DIR/.caveman-active"

  output="$(run_hook)"

  [[ "$output" != *"wenyan"* ]] || false
  [[ "$output" == *'Switch: `/caveman lite|full|ultra|off`.'* ]] || false
}

@test "still emits a valid hook envelope when caveman-examples.md is missing" {
  echo "full" > "$CLAUDE_CONFIG_DIR/.caveman-active"
  tmp_hooks="$(mktemp -d)"
  cp "$KIT_DIR"/hooks/*.js "$tmp_hooks/"

  raw="$(printf '{}' | node "$tmp_hooks/caveman-activate.js")"

  [[ "$raw" == *'"additionalContext"'* ]] || false
  [[ "$raw" == *"CAVEMAN MODE ACTIVE — level: full"* ]] || false
  rm -rf "$tmp_hooks"
}

@test "ultra treats unterminated ultracave frontmatter as empty and falls back" {
  echo "ultra" > "$CLAUDE_CONFIG_DIR/.caveman-active"
  printf -- '---\nname: ultracave\nULTRACAVE-BODY-MARKER\n' > "$CLAUDE_CONFIG_DIR/skills/ultracave/SKILL.md"

  output="$(run_hook)"

  [[ "$output" == *"CAVEMAN-BODY-MARKER"* ]] || false
  [[ "$output" != *"ULTRACAVE-BODY-MARKER"* ]] || false
}

@test "a mid-line --- in ultracave frontmatter does not end the frontmatter" {
  echo "ultra" > "$CLAUDE_CONFIG_DIR/.caveman-active"
  printf -- '---\nname: ultracave\ndescription: terse---ultra\n---\nULTRACAVE-BODY-MARKER\n' > "$CLAUDE_CONFIG_DIR/skills/ultracave/SKILL.md"

  output="$(run_hook)"

  [[ "$output" == *"ULTRACAVE-BODY-MARKER"* ]] || false
  [[ "$output" != *"description:"* ]] || false
}

# --- ADR 0026: rules source in the header, resolveRules export ---

hook_header() {
  printf '{"hook_event_name":"%s"}' "${1:-SessionStart}" | node "$KIT_DIR/hooks/caveman-activate.js" 2>/dev/null \
    | node -e 'let r="";process.stdin.on("data",c=>r+=c).on("end",()=>process.stdout.write(JSON.parse(r).hookSpecificOutput.additionalContext.split("\n")[0]))'
}

@test "header names rules: ultracave for ultra with a usable ultracave" {
  echo "ultra" > "$CLAUDE_CONFIG_DIR/.caveman-active"
  [ "$(hook_header)" = "CAVEMAN MODE ACTIVE — level: ultra (rules: ultracave)" ]
}

@test "header names rules: caveman for lite and full" {
  for mode in lite full; do
    echo "$mode" > "$CLAUDE_CONFIG_DIR/.caveman-active"
    [ "$(hook_header)" = "CAVEMAN MODE ACTIVE — level: $mode (rules: caveman)" ]
  done
}

@test "header says ultracave missing when ultracave is absent, empty or unterminated" {
  echo "ultra" > "$CLAUDE_CONFIG_DIR/.caveman-active"
  want="CAVEMAN MODE ACTIVE — level: ultra (rules: caveman, ultracave missing)"
  rm -rf "$CLAUDE_CONFIG_DIR/skills/ultracave"
  [ "$(hook_header)" = "$want" ]
  mkdir -p "$CLAUDE_CONFIG_DIR/skills/ultracave"
  printf -- '---\nname: ultracave\n---\n\n' > "$CLAUDE_CONFIG_DIR/skills/ultracave/SKILL.md"
  [ "$(hook_header)" = "$want" ]
  printf -- '---\nname: ultracave\nBODY text never closed\n' > "$CLAUDE_CONFIG_DIR/skills/ultracave/SKILL.md"
  [ "$(hook_header)" = "$want" ]
}

@test "SubagentStart header carries the rules suffix" {
  echo "ultra" > "$CLAUDE_CONFIG_DIR/.caveman-active"
  [ "$(hook_header SubagentStart)" = "CAVEMAN MODE ACTIVE — level: ultra (rules: ultracave)" ]
}

@test "fallback keeps the stderr line" {
  echo "ultra" > "$CLAUDE_CONFIG_DIR/.caveman-active"
  rm -rf "$CLAUDE_CONFIG_DIR/skills/ultracave"
  run bash -c "printf '{}' | node '$KIT_DIR/hooks/caveman-activate.js' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ultracave skill not found or empty"* ]] || false
}

@test "requiring the module has no side effects and resolveRulesSource labels ultra" {
  run node -e '
    const m = require(process.argv[1]);
    process.stdout.write(m.resolveRulesSource("ultra") + "|" + m.resolveRulesSource("full") + "|" + m.resolveRules("ultra").body.includes("ULTRACAVE-BODY-MARKER"));
  ' "$KIT_DIR/hooks/caveman-activate.js"
  [ "$status" -eq 0 ]
  [ "$output" = "ultracave|caveman|true" ]
  [ ! -e "$CLAUDE_CONFIG_DIR/.caveman-active" ]
  rm -rf "$CLAUDE_CONFIG_DIR/skills/ultracave"
  run node -e 'process.stdout.write(require(process.argv[1]).resolveRulesSource("ultra"))' "$KIT_DIR/hooks/caveman-activate.js"
  [ "$output" = "caveman, ultracave missing" ]
}
