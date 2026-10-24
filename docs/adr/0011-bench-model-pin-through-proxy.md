---
artifact-type: adr
lineage-rules: exempt
---

# ADR 0011: Bench calls must reach the requested model; routing proxies are refused

**Status**: Approved

**Context:**

ADR 0008 gates a ruleset change on measured cost of a fixed model (`claude-sonnet-5-5` by default). The harness calls `claude -p --model <model>`, and nothing checks where the call goes. `ANTHROPIC_BASE_URL` can point at an anthproxy instance. That proxy, run with auto model routing on, rewrites the requested model per request (classifier or session tier cache).

The b56c077 run went through such a proxy (`127.0.0.1:8083`, `--auto-model-routing`). The proxy log shows the arms routed to different models: about 58% of the bench requests on opus and 42% on sonnet, with 9 of 24 gate pairs comparing different models (`docs/research/2026-10-23-bench-compare-8c90768-vs-b56c077.md`, caveat added 2026-10-24). The streams still report `claude-sonnet-5-5`, because the proxy echoes the requested name, so the run's own files do not reveal the change. The run's numbers therefore do not measure the model the gate names.

The prompt cache is also per model: a warmup call that routes to another model cannot warm the cell (`bench/results/warmup-check` shows this).

**Decision:**

1. A bench run must reach the requested model. When `ANTHROPIC_BASE_URL` is set, `bench/run.js` asks the proxy for `proxy-status` before any paid call and refuses to start when the proxy reports model routing on, or does not answer. Unset `ANTHROPIC_BASE_URL` is a direct run and is not checked (`bench/lib/proxy.js`).
2. The operator runs bench traffic through a pass-through instance: routing off, `--lock-requested-model off`, on its own port, with its own DB (`--db-path`). `bench/README.md`, "Routing proxy", gives the command.
3. `proxy-status` does not report the model lock. The lock is checked in the proxy log: no `Model lock:` lines, and every `Routing economics:` line reads `routed=<requested model> reason=disabled`. The check is part of the procedure, not automated.
4. Runs made before this ADR through a routing proxy measure a mix of models. They are not valid for the gate. The b56c077 run is one such run: its note carries the caveat.

**Consequences:**

- A run started by mistake through a routing proxy is refused before any cost, instead of after a full run.
- The check trusts the proxy's own report of routing. The model lock is not covered by an automated check, only by the log procedure.
- Bench runs need a second proxy instance, or direct API access.
- The check sends one extra request to the proxy. The `proxy-status` reply is local and reports zero tokens; whether the proxy logs it is not verified.
- `ANTHROPIC_BASE_URL` is commonly exported in a maintainer's shell. Runs from that shell are checked too, so a routing proxy there blocks them. This is intended.
