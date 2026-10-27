"""caveman-kit bench hidden test (fixture tierslot): one tier cache, two scopes.

A tool-result turn (no user text) replays the tier the router cached for its
conversation, with no cap: Claude Code sends the base model on every turn, so a
haiku tier cached on a sonnet-requested turn is meant to send the following
sonnet tool-result turns to haiku. The planted tree keys that cache by the
conversation alone, so the same haiku tier is also replayed into an
opus-requested turn.

The tempting fix refuses any replay below the requested tier. That turns the
opus case green and breaks the same-tier replay. The fix that keeps both scopes
caches by the requested model's tier, taken from the routing baseline
(``lock_requested_model`` when set). Only behavior over HTTP is checked here;
any fix that keeps every case passes.
"""

from anthrouter.model_config import resolve_model
from tests.conftest import _FakeUpstream, db_rows, post

SESSION = '{"session_id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"}'
HAIKU = resolve_model('haiku')


def _user_turn(model, text='hi'):
    return {
        'model': model, 'metadata': {'user_id': SESSION},
        'messages': [{'role': 'user', 'content': text}],
    }


def _continuation(model):
    """A tool-result turn: the final user message carries no text to classify."""
    return {
        'model': model, 'metadata': {'user_id': SESSION},
        'messages': [
            {'role': 'user', 'content': 'hi'},
            {'role': 'assistant', 'content': [
                {'type': 'tool_use', 'id': 'toolu_1', 'name': 'Read',
                 'input': {'file_path': 'README.md'}}]},
            {'role': 'user', 'content': [
                {'type': 'tool_result', 'tool_use_id': 'toolu_1',
                 'content': 'contents'}]},
        ],
    }


def _send(server, payload):
    """Post one turn; return (model sent upstream, recorded reason code)."""
    post(server, '/v1/messages', payload)
    return _FakeUpstream.received[-1]['payload']['model'], db_rows(server)[0]['reason_code']


def _rules_proxy(proxy, **overrides):
    return proxy(auto_model_routing=True, auto_model_routing_mode='rules', **overrides)


def test_same_tier_tool_result_turn_replays_the_cached_downgrade(proxy):
    server = _rules_proxy(proxy)
    assert _send(server, _user_turn('sonnet'))[0] == HAIKU
    assert _send(server, _continuation('sonnet'))[0] == HAIKU


def test_alias_and_full_id_of_one_tier_share_the_slot(proxy):
    server = _rules_proxy(proxy)
    assert _send(server, _user_turn('sonnet'))[0] == HAIKU
    assert _send(server, _continuation('claude-sonnet-5-5'))[0] == HAIKU


def test_higher_tier_turn_is_not_served_the_cached_downgrade(proxy):
    server = _rules_proxy(proxy)
    assert _send(server, _user_turn('sonnet'))[0] == HAIKU
    model, reason = _send(server, _continuation('opus'))
    assert model != HAIKU
    assert not reason.startswith('session_cached')


def test_each_requested_tier_keeps_its_own_slot(proxy):
    server = _rules_proxy(proxy)
    assert _send(server, _user_turn('sonnet'))[0] == HAIKU
    assert _send(server, _continuation('opus'))[0] != HAIKU
    # A classified opus user turn writes the cache. It must not overwrite or
    # evict the sonnet slot (a tool-result turn that replays the cache does
    # not write it).
    assert _send(server, _user_turn('opus'))[0] == HAIKU
    assert _send(server, _continuation('sonnet'))[0] == HAIKU


def test_locked_baseline_scopes_the_slot_by_the_lock(proxy):
    server = _rules_proxy(proxy, lock_requested_model='sonnet')
    assert _send(server, _user_turn('opus'))[0] == HAIKU
    # The lock is the routing baseline, so the client's own model choice does
    # not move the tool-result turn to another slot.
    assert _send(server, _continuation('haiku'))[0] == HAIKU
    assert _send(server, _continuation('opus'))[0] == HAIKU
