---
artifact-type: adr
lineage-rules: exempt
---

# ADR 0018: A tierslot fixture whose tempting fix breaks an intended behavior, not a second caller

**Status**: Accepted as a fixture outside the default set; the calibration target (ADR 0012 decision 2) is not yet measured. See Outcome.

**Context:**

Issue #22 asks for a fixture where the bare arm fails some seeds, so that the hidden-test guardrail can detect a drop. `retryafter` (ADR 0015) and `adminalias` (ADR 0017) did not reach it. Both planted a second fault, a second bug or a second caller, next to the first. Agents grep every hit for the symptom keywords, read about 100 lines around each hit, and read the callers of the function they change, so they found the second fault every time. Issue #22 asks for a fix whose correctness needs context that a keyword grep does not reach, and for a wrong fix that the visible suite does not catch.

anthrouter keeps a routed-tier cache: a text-less tool-result turn replays the tier the router last decided for its conversation. anthrouter ADR-0012 (at the pin, `docs/adr/0012-tier-cache-key-includes-requested-tier.md`) keys that cache by conversation and requested tier. Before that ADR the key was the conversation alone, so a haiku tier decided on a sonnet-requested turn was replayed into an opus-requested turn. The replay is meant to downgrade: Claude Code sends the base model on every turn, so a sonnet conversation classified as trivial sends its tool-result turns to haiku. `route_model` applies no cap on this path, and a comment there says why.

The fault that gives the symptom (opus sent to haiku) is in the cache key in `handlers`. A fix that refuses any replay below the requested tier also turns the opus case green, and it contradicts the intended downgrade. The comment in `route_model` explains the uncapped replay. It does not say that the cache must be keyed by the requested tier; that reasoning lived in anthrouter ADR-0012, which the plant deletes. The reasoning is in a design decision, not in a second call site.

The first review found that the intent text is still reachable by grep for `walkback` or `tool_result`: the `route_model` comment and `TestNoUpgradeCap`; `docs/agents/architecture.md` mentions the walk-back cache and tool-result-only turns in its own words. The prompt therefore carries no reason code. An agent that reads those hits can still find the intended downgrade, so the fixture may pass every seed like its predecessors (a ceiling result). The opposite is also possible: the prompt has no end-to-end sentence, and `retryafter` calibration 2 showed that such a prompt drove `bare` to 0 of 4, which is also outside 50-80% (a floor result). Only a calibration run can show which one happens.

**Decision:**

1. Add a ninth fixture, `tierslot`, under the rules of ADR 0008 decision 5: the same pinned `nj4x/anthrouter` commit, a `plant.patch`, and an offline hidden test. It has no `base.patch`, because the pin already has the fix.
2. `plant.patch` reverts anthrouter ADR-0012 in the code and removes the record of it:
   - `handlers.py`: `tier_key = ctx_key`; `_requested_tier`, its comment and the now unused `classify_model_tier` import are removed.
   - `session_state.py`: the tier cache takes a string key, and the module docstring describes two key shapes, as `docs/agents/architecture.md` already does at the pin.
   - `tests/test_handlers.py`: the `_requested_tier` import, `test_routed_tier_slots_are_per_requested_tier`, the ADR-0012 test section, and the tuple keys in `test_state_maps_evict_oldest_first` are removed or reverted. The two ADR-0012 HTTP tests already fail at the pin: a later walk-back change (anthrouter ADR-0011) re-classifies their continuation turn.
   - `docs/adr/0012-tier-cache-key-includes-requested-tier.md` is deleted. Left in place, a grep for the reason code finds it, and it states the fix.
3. The prompt reports the request log: a sonnet-requested user turn routed to haiku as `trivial`, then a later opus-requested turn routed to haiku. It says the opus turn should not have gone to haiku. It names no function, no cache key, no reason code, no downgrade rule, and it has no end-to-end sentence.
4. The hidden test checks behavior over HTTP only, against a proxy in rules mode:
   - a sonnet tool-result turn after the trivial sonnet turn goes to haiku (the intended downgrade replay);
   - so does a `claude-sonnet-5-5` tool-result turn after a `sonnet` turn (the slot is the tier, not the model string);
   - an opus tool-result turn after it is not sent to haiku, and its reason code does not start with `session_cached`;
   - after that opus turn and a classified opus user turn, a sonnet tool-result turn still goes to haiku (the opus slot does not overwrite the sonnet slot; a tool-result turn that replays the cache does not write it);
   - with `lock_requested_model=sonnet`, haiku- and opus-requested tool-result turns replay the tier cached on an opus-requested turn (the slot follows the routing baseline).
   Any fix that keeps all five passes.
5. To make `prepareWorkDir`'s stand-in check (`bench/tests/patch_standin.js`) cover a plant that deletes a file, the stand-in writes a pre-image only for a `+++ /dev/null` file, and the bats check asserts that the file is absent from the planted tree.
6. `tierslot` is outside the default `--fixtures` set (`"inDefaultSet": false`) until a calibration run shows that `bare` fails 20-50% of seeds. If it does, set `inDefaultSet` to true and record the result here.

**Consequences:**

- Checked on the pinned clone with `fixtures.checkReliability`: `{ ok: true }`. Each variant was run against the planted tree with the hidden test added:
  - planted tree: hidden test 3 of 5 pass; visible suite one failure, `test_config.py::test_editable_fields_live_editable_fields`, which also fails on the unpatched pin;
  - correct fix (the pin's `handlers.py` and `session_state.py`): hidden 5 of 5; visible suite the same one failure;
  - refuse a replay below the requested tier, in `handlers` before `route_model`: hidden 1 of 5; visible suite the same one failure;
  - the same refusal inside `route_model`: hidden 1 of 5, and two visible tests fail (`TestNoUpgradeCap::test_walkback_downgrade_replays_uncapped`, `test_walkback_unknown_requested_fails_open`), so an agent that runs the suite sees it;
  - key by the raw model string: hidden 4 of 5 (the alias/full-ID case fails);
  - key by the tier of the client's model, ignoring the lock: hidden 4 of 5 (the lock case fails).
- The fixture measures whether the agent finds the intended behavior that the tempting fix breaks. The suite catches the tempting fix only when it is made inside `route_model`.
- The patch was built by hand against the pin. If the pin moves, `plant.patch` must be regenerated.

**Source SRS:** none (repo uses `lineage-rules: exempt`).

## Outcome

Not yet calibrated. No paid run has used `tierslot`. The next step is a calibration run, `node bench/run.js --kind agentic --fixtures tierslot`, read for the `bare` arm's pass rate. Record its note in `docs/research/` and its result here.
