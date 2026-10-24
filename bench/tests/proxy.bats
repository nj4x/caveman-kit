#!/usr/bin/env bats
# ADR 0011: a routing proxy (ANTHROPIC_BASE_URL) must be pass-through before
# any paid call. No network: the unit tests use a fake fetch, and the runner
# tests point at a closed port.

load helpers
load helpers_agentic

setup() {
  bench_setup
  unset ANTHROPIC_BASE_URL
  make_diet_kit
  export KIT
  make_source_repo
  make_fixture tiny
  export FIXTURES
}
teardown() { bench_teardown; }

# status_reply <text>: node snippet calling checkProxy with a fake proxy reply.
proxy_check() {
  REPLY="$1" node -e '
    const assert = require("assert");
    const proxy = require(process.env.BENCH_DIR + "/lib/proxy");
    const fake = text => async () => ({ json: async () => ({ content: [{ type: "text", text }] }) });
    const expectFail = (text, re) => assert.rejects(proxy.checkProxy("http://x", fake(text)), re);
    (async () => {
      if (process.env.REPLY === "off") {
        const r = await proxy.checkProxy("http://x", fake("## anthproxy status\n**Model routing:** off\n"));
        assert.strictEqual(r.routing, "off");
      } else if (process.env.REPLY === "on") {
        await expectFail("**Model routing:** on", /model routing on/);
      } else if (process.env.REPLY === "nonline") {
        await expectFail("hello", /no routing line/);
      } else if (process.env.REPLY === "down") {
        const failing = async () => { throw new Error("ECONNREFUSED"); };
        await assert.rejects(proxy.checkProxy("http://x", failing), /did not answer proxy-status: ECONNREFUSED/);
      }
    })().catch(e => { console.error(e); process.exit(1); });
  '
}

@test "proxy-check: routing off passes; routing on, no routing line, or no answer refuses" {
  REPLY=off proxy_check
  REPLY=on proxy_check
  REPLY=nonline proxy_check
  REPLY=down proxy_check
}

@test "proxy-base-url: unset or blank means direct; a trailing slash is dropped" {
  node -e '
    const assert = require("assert");
    const { proxyBaseUrl } = require(process.env.BENCH_DIR + "/lib/proxy");
    assert.strictEqual(proxyBaseUrl({}), null);
    assert.strictEqual(proxyBaseUrl({ ANTHROPIC_BASE_URL: "  " }), null);
    assert.strictEqual(proxyBaseUrl({ ANTHROPIC_BASE_URL: "http://127.0.0.1:8084/" }), "http://127.0.0.1:8084");
  '
}

@test "proxy-runner: a set ANTHROPIC_BASE_URL that does not answer refuses before any claude call" {
  ANTHROPIC_BASE_URL=http://127.0.0.1:1 run run_agentic --seeds 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"did not answer proxy-status"* ]] || false
  [ "$(stub_calls)" -eq 0 ]
}

@test "proxy-runner: a direct run (no ANTHROPIC_BASE_URL) prints no proxy line" {
  unset ANTHROPIC_BASE_URL
  run run_agentic --seeds 1
  [ "$status" -eq 0 ]
  [[ "$output" != *"Proxy "* ]] || false
}
