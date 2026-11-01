#!/usr/bin/env bats
# bats-core tests for caveman-mode-tracker.js skip rule: prompts a human did
# not type get no reminder and no mode parsing.

setup() {
  export HOME="$(mktemp -d)"
  export KIT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export CWD="$HOME/work"
  mkdir -p "$CWD"
  mkdir -p "$HOME/.claude"
  echo ultra > "$HOME/.claude/.caveman-active"
}

teardown() {
  rm -rf "$HOME"
}

run_hook() {
  printf '%s' "$1" | node "$KIT_DIR/hooks/caveman-mode-tracker.js"
}

@test "human prompt gets the reminder" {
  run run_hook "{\"prompt\":\"explain caching\",\"cwd\":\"$CWD\"}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CAVEMAN MODE ACTIVE (ultra)"* ]]
}

@test "task-notification prompt gets no reminder" {
  run run_hook "{\"prompt\":\"<task-notification><task-id>x</task-id></task-notification>\",\"cwd\":\"$CWD\"}"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "side-sessions-event prompt gets no reminder" {
  run run_hook "{\"prompt\":\"<side-sessions-event>done</side-sessions-event>\",\"cwd\":\"$CWD\"}"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ci-monitor-event prompt gets no reminder" {
  run run_hook "{\"prompt\":\"<ci-monitor-event>green</ci-monitor-event>\",\"cwd\":\"$CWD\"}"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "non-human envelope containing /caveman off does not change mode" {
  run run_hook "{\"prompt\":\"<task-notification>/caveman off</task-notification>\",\"cwd\":\"$CWD\"}"
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.claude/.caveman-active")" = "ultra" ]
}
