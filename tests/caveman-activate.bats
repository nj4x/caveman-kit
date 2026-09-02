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
  # Copy the actual SKILL.md so the hook can read it
  cp "$HOME/.claude/skills/caveman/SKILL.md" "$CLAUDE_CONFIG_DIR/skills/caveman/" 2>/dev/null || cat > "$CLAUDE_CONFIG_DIR/skills/caveman/SKILL.md" <<'SKILL'
---
name: caveman
disable-model-invocation: true
---

Respond terse like smart caveman. All technical substance stay. Only fluff die.

Default: **full**. Switch: `/caveman lite|full|ultra|wenyan-lite|wenyan-full|wenyan-ultra|off`.

## Rules

Drop: articles (a/an/the), filler (just/really/basically/actually/simply), pleasantries, hedging. Fragments OK. Short synonyms. No tool-call narration, no decorative tables/emoji.

## Intensity

| Level | What change |
|-------|------------|
| **lite** | No filler/hedging. Keep articles + full sentences. Professional but tight |
| **full** | Drop articles, fragments OK, short synonyms. Classic caveman |
| **ultra** | Strip conjunctions when cause-then-effect stay unambiguous. One word when one word enough |
| **wenyan-lite** | Semi-classical. Drop filler/hedging but keep grammar structure |
| **wenyan-full** | Maximum classical terseness. Fully 文言文 |
| **wenyan-ultra** | Extreme abbreviation while keeping classical Chinese feel |

Example "Why React component re-render?"
- lite: "Your component re-renders because you create a new object reference each render. Wrap it in `useMemo`."
- full: "New object ref each render. Inline object prop = new ref = re-render. Wrap in `useMemo`."
- ultra: "Inline obj prop, new ref, re-render. `useMemo`."
SKILL

  export CLAUDE_PLUGIN_ROOT="$CLAUDE_CONFIG_DIR"
}

teardown() {
  rm -rf "$HOME"
}

# Runs the hook with the given cwd on stdin and extracts additionalContext
# from its JSON hookSpecificOutput envelope (or passes non-JSON output, i.e.
# a stderr-only failure path, through unchanged) so existing assertions can
# keep matching on plain ruleset text.
#
# Known gap: if the hook ever regresses to plain-text stdout, this passthrough
# masks it for the tests below (asserting on `hookEventName`/`additionalContext` keys
# directly, bypassing run_hook) actually guard the JSON envelope shape.
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

  [[ "$output" == *"CAVEMAN MODE ACTIVE — level: full"* ]]
  [[ "$output" == *"| **full** |"* ]]
}

@test "prefers the repo-scoped flag over the global one" {
  echo "full" > "$CLAUDE_CONFIG_DIR/.caveman-active"
  repo="$(make_repo ultra)"

  output="$(run_hook "$repo")"

  [[ "$output" == *"CAVEMAN MODE ACTIVE — level: ultra"* ]]
  [[ "$output" == *"| **ultra** |"* ]]
}

@test "emits only the active mode's table row" {
  echo "lite" > "$CLAUDE_CONFIG_DIR/.caveman-active"

  output="$(run_hook)"

  [[ "$output" == *"| **lite** |"* ]]
  [[ "$output" != *"| **full** |"* ]]
  [[ "$output" != *"| **ultra** |"* ]]
}

@test "every mode is resolvable from the global flag" {
  for mode in lite full ultra; do
    echo "$mode" > "$CLAUDE_CONFIG_DIR/.caveman-active"

    output="$(run_hook)"

    [[ "$output" == *"CAVEMAN MODE ACTIVE — level: $mode"* ]]
  done
}

@test "reports the skill path on stderr when SKILL.md is unreadable" {
  echo "full" > "$CLAUDE_CONFIG_DIR/.caveman-active"
  export CLAUDE_PLUGIN_ROOT="$HOME/absent"

  output="$(run_hook)"

  [[ "$output" == *"could not read"* ]]
  [[ "$output" == *"SKILL.md"* ]]
}

@test "defaults hookEventName to SessionStart when the input omits it" {
  echo "full" > "$CLAUDE_CONFIG_DIR/.caveman-active"

  raw="$(printf '{}' | node "$KIT_DIR/hooks/caveman-activate.js")"

  [[ "$raw" == *'"hookEventName":"SessionStart"'* ]]
  [[ "$raw" == *'"additionalContext"'* ]]
}

@test "echoes hook_event_name back so SubagentStart deliveries are accepted" {
  echo "full" > "$CLAUDE_CONFIG_DIR/.caveman-active"

  raw="$(printf '{"hook_event_name":"SubagentStart"}' | node "$KIT_DIR/hooks/caveman-activate.js")"

  [[ "$raw" == *'"hookEventName":"SubagentStart"'* ]]
  [[ "$raw" == *'"additionalContext"'* ]]
  [[ "$raw" == *"CAVEMAN MODE ACTIVE"* ]]
}

@test "honors the repo-scoped mode flag via cwd under SubagentStart" {
  echo "full" > "$CLAUDE_CONFIG_DIR/.caveman-active"
  repo="$(make_repo ultra)"

  raw="$(printf '{"cwd":"%s","hook_event_name":"SubagentStart"}' "$repo" | node "$KIT_DIR/hooks/caveman-activate.js")"

  [[ "$raw" == *'"hookEventName":"SubagentStart"'* ]]
  [[ "$raw" == *"CAVEMAN MODE ACTIVE — level: ultra"* ]]
}
