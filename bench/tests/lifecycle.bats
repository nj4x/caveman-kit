#!/usr/bin/env bats
# Temp config dir lifecycle: mode 0700 while in use, gone on every exit path.

load helpers

setup() { bench_setup; }
teardown() {
  [ -n "${BENCH_PID:-}" ] && kill -9 "$BENCH_PID" 2>/dev/null
  bench_teardown
}

# Starts the runner in the background with a sleeping stub, waits until the
# stub has been called, and leaves the runner's pid in BENCH_PID.
start_sleeping_run() {
  export STUB_SLEEP=30
  node "$BENCH_DIR/run.js" --results-dir "$RESULTS" --research-dir "$RESEARCH" --kind single-turn --seeds 1 --yes \
    < /dev/null > "$TEST_ROOT/bench.out" 2>&1 &
  BENCH_PID=$!
  for _ in $(seq 1 100); do
    [ "$(stub_calls)" -ge 1 ] && return 0
    sleep 0.1
  done
  echo "stub never called"; cat "$TEST_ROOT/bench.out"
  return 1
}

@test "tempdir-lifecycle: temp root is 0700 while running and gone after a normal exit" {
  run run_bench --kind single-turn --seeds 1 --yes
  [ "$status" -eq 0 ]

  log_assert 'for (const e of entries) assert.strictEqual(e.tempRootMode, "700");'
  [ "$(leftover_temp_dirs)" -eq 0 ]
}

@test "tempdir-lifecycle: temp root is gone after a failing claude" {
  STUB_FAIL=1 run run_bench --kind single-turn --seeds 1 --yes
  [ "$status" -ne 0 ]
  [ "$(stub_calls)" -eq 36 ]
  [ "$(find "$RESULTS" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]
  [ "$(leftover_temp_dirs)" -eq 0 ]
}

@test "tempdir-lifecycle: temp root is gone after an early error" {
  fake_kit="$TEST_ROOT/fake-kit"
  mkdir -p "$fake_kit/hooks"
  cp "$KIT_DIR"/hooks/*.js "$fake_kit/hooks/"
  printf '%s\n' "process.exit(0);" > "$fake_kit/hooks/caveman-activate.js"

  run run_bench --kind single-turn --seeds 1 --yes --kit-dir "$fake_kit"
  [ "$status" -ne 0 ]
  [ "$(leftover_temp_dirs)" -eq 0 ]
}

@test "tempdir-lifecycle: SIGTERM stops claude and removes the temp root" {
  start_sleeping_run
  [ "$(leftover_temp_dirs)" -eq 1 ]

  kill -TERM "$BENCH_PID"
  status=0; wait "$BENCH_PID" || status=$?
  BENCH_PID=

  [ "$status" -eq 143 ]
  [ "$(leftover_temp_dirs)" -eq 0 ]
  [ "$(stub_calls)" -eq 1 ]
  stub_pid="$(head -1 "$STUB_LOG" | node -e 'process.stdout.write(String(JSON.parse(require("fs").readFileSync(0, "utf8")).pid))')"
  ! kill -0 "$stub_pid" 2>/dev/null || false
}

@test "tempdir-lifecycle: SIGINT stops claude and removes the temp root" {
  start_sleeping_run
  [ "$(leftover_temp_dirs)" -eq 1 ]

  kill -INT "$BENCH_PID"
  status=0; wait "$BENCH_PID" || status=$?
  BENCH_PID=

  [ "$status" -eq 130 ]
  [ "$(leftover_temp_dirs)" -eq 0 ]
  [ "$(stub_calls)" -eq 1 ]
  stub_pid="$(head -1 "$STUB_LOG" | node -e 'process.stdout.write(String(JSON.parse(require("fs").readFileSync(0, "utf8")).pid))')"
  ! kill -0 "$stub_pid" 2>/dev/null || false
}

@test "tempdir-lifecycle: SIGHUP stops claude and removes the temp root" {
  start_sleeping_run

  kill -HUP "$BENCH_PID"
  status=0; wait "$BENCH_PID" || status=$?
  BENCH_PID=

  [ "$status" -eq 129 ]
  [ "$(leftover_temp_dirs)" -eq 0 ]
  [ "$(stub_calls)" -eq 1 ]
  stub_pid="$(head -1 "$STUB_LOG" | node -e 'process.stdout.write(String(JSON.parse(require("fs").readFileSync(0, "utf8")).pid))')"
  [[ "$stub_pid" =~ ^[0-9]+$ ]]
  ! kill -0 "$stub_pid" 2>/dev/null || false
}
