---
artifact-type: adr
lineage-rules: exempt
---

# ADR 0018: A tierslot fixture whose tempting fix breaks an intended behavior, not a second caller

**Status**: Accepted as a fixture outside the default set; the calibration target (ADR 0012 decision 2) is not met after calibration 2. See Outcome.

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
   - after that opus turn and a classified opus user turn, a sonnet tool-result turn still goes to haiku (the opus slot does not overwrite the sonnet slot; a tool-result turn that replays the cache does not write it).
   Any fix that keeps all four passes. A fifth case, that the slot follows the `lock_requested_model` baseline, was dropped after calibration 1 (see Outcome).
5. To make `prepareWorkDir`'s stand-in check (`bench/tests/patch_standin.js`) cover a plant that deletes a file, the stand-in writes a pre-image only for a `+++ /dev/null` file, and the bats check asserts that the file is absent from the planted tree.
6. `tierslot` is outside the default `--fixtures` set (`"inDefaultSet": false`) until a calibration run shows that `bare` fails 20-50% of seeds. If it does, set `inDefaultSet` to true and record the result here.

**Consequences:**

- Checked on the pinned clone with `fixtures.checkReliability`: `{ ok: true }`. Each variant was run against the planted tree with the hidden test added:
  - planted tree: hidden test 2 of 4 pass; visible suite one failure, `test_config.py::test_editable_fields_live_editable_fields`, which also fails on the unpatched pin;
  - correct fix (the pin's `handlers.py` and `session_state.py`): hidden 4 of 4; visible suite the same one failure;
  - refuse a replay below the requested tier, in `handlers` before `route_model`: hidden 1 of 4; visible suite the same one failure;
  - the same refusal inside `route_model`: hidden 1 of 4, and two visible tests fail (`TestNoUpgradeCap::test_walkback_downgrade_replays_uncapped`, `test_walkback_unknown_requested_fails_open`), so an agent that runs the suite sees it;
  - key by the raw model string: hidden 3 of 4 (the alias/full-ID case fails).
- The fixture measures whether the agent finds the intended behavior that the tempting fix breaks. The suite catches the tempting fix only when it is made inside `route_model`.
- The patch was built by hand against the pin. If the pin moves, `plant.patch` must be regenerated.

**Source SRS:** none (repo uses `lineage-rules: exempt`).

## Outcome

Calibration 1 (`node bench/run.js --kind agentic --fixtures tierslot --seeds 6 --min-fixtures 1 --run-id <id>`, run id `agentic-claude-sonnet-5-5-tireslot-calibarion-1`, five-case hidden test) gave `bare` 1 of 5 for seeds 1 to 5; no `full` or `full-diet` cell ran (`docs/research/2026-10-27-bench-agentic-claude-sonnet-5-5-tierslot-calibration-1.md`). Every failing seed fixed the opus symptom and passed the same-tier and higher-tier cases. The lock case (`lock_requested_model` scopes the slot) failed in seeds 1 to 4, and the alias/full-ID case failed in seeds 1 and 2. Seed 5 passed all five cases.

The lock case was not derivable from the symptom: the prompt never names the lock, and the plant deletes the only text that says the slot follows it. The fixture then measured a missing requirement, not a missed behavior, which is the floor risk named in Context. Decision 4 drops the lock case; the alias/full-ID case stays, because the pin's `_requested_tier` is the only place that states the slot is the tier. Calibration 2 (same command with its own run id, `agentic-claude-sonnet-5-5-tierslot-calibration-2`, four-case hidden test, `docs/research/2026-10-27-bench-agentic-claude-sonnet-5-5-tierslot-calibration-2.md`) gave `bare` 2 of 6, `full` 1 of 6 and `full-diet` 0 of 6. All 15 failing cells fail one test, `test_alias_and_full_id_of_one_tier_share_the_slot`. Every failing agent fixed the opus symptom, passed the other three cases, and keyed the cache by the raw model string. The run ended at the escalation prompt, so seeds 7 to 12 never ran, and the cost gate did not run to its end.

The observed `bare` failure rate, 4 of 6 (67%), is above the 20-50% failure band. With 6 seeds the `bare` pass rate of 33% has an exact 95% interval of about 4% to 78%, which covers almost all of the 50-80% pass band, so the data do not exclude the target. The fixture is bimodal. The other three cases passed in every cell, so dropping the alias case would leave a fixture that `bare` passes almost always. Keeping it makes the fixture hinge on a requirement that the symptom does not name, the flaw that removed the lock case. `tierslot` stays in `bench/fixtures/` and outside the default set, and this ADR records no further design. It is the closest of the fixtures so far: `retryafter` and `adminalias` gave `bare` 6 of 6 or 12 of 12, except one `retryafter` run with no end-to-end sentence (0 of 4).
