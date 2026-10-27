"""caveman-kit bench hidden test (fixture adminalias): one parser, two callers.

config._parse_model_aliases_str (and its sibling _parse_classification_str)
report bad input with ``p.error()``, which exits the process with SystemExit(2).
That is the right behavior for the command line. admin.handle_post_config
passes a throwaway ArgumentParser, so a malformed value in a POST body raises
SystemExit inside the request thread: the client gets no response instead of a
400. A fix that makes the parsers raise something else (ValueError) turns the
admin path green and breaks the command line, which must still exit with code 2
and the usage message. Both callers are checked here; any fix that keeps both
behaviors passes.
"""

import pytest

from anthrouter.config import EDITABLE_FIELDS, Config, parse_args
from anthrouter import admin

BAD_ALIASES = ['garbage', 'a:', ':b', 'ok:fine,broken']
BAD_CLASSIFICATION = ['huge:opus', 'deep', 'deep:']


@pytest.fixture
def cfg(tmp_path):
    return Config(
        upstream_base_url='https://api.anthropic.com',
        enable_ui=True,
        anthrouter_home=str(tmp_path),
        admin_token='sekret',
    )


def full_body(cfg, overrides):
    body = {}
    for name in EDITABLE_FIELDS:
        value = getattr(cfg, name)
        if value is None:
            body[name] = ''
        elif isinstance(value, bool):
            body[name] = 'true' if value else 'false'
        elif isinstance(value, dict):
            body[name] = ','.join(f'{k}:{v}' for k, v in value.items())
        else:
            body[name] = str(value)
    body.update(overrides)
    return body


def post(cfg, overrides):
    applied = []
    status, payload = admin.handle_post_config(
        'sekret', full_body(cfg, overrides), cfg, applied.append)
    return status, payload, applied


@pytest.mark.parametrize('raw', BAD_ALIASES)
def test_admin_post_rejects_malformed_model_aliases_with_400(cfg, raw):
    status, payload, applied = post(cfg, {'model_aliases': raw})
    assert status == 400
    assert payload
    assert applied == []


@pytest.mark.parametrize('raw', BAD_CLASSIFICATION)
def test_admin_post_rejects_malformed_classification_with_400(cfg, raw):
    status, payload, applied = post(cfg, {'auto_model_routing_classification': raw})
    assert status == 400
    assert payload
    assert applied == []


def test_admin_post_still_accepts_well_formed_aliases(cfg):
    status, payload, applied = post(cfg, {'model_aliases': 'fast:haiku,smart:opus'})
    assert status == 200
    assert len(applied) == 1


@pytest.mark.parametrize('raw', BAD_ALIASES)
def test_command_line_exits_2_with_usage_for_malformed_model_aliases(raw, capsys):
    with pytest.raises(SystemExit) as exc:
        parse_args(['--model-aliases', raw])
    assert exc.value.code == 2
    assert '--model-aliases' in capsys.readouterr().err


@pytest.mark.parametrize('raw', BAD_CLASSIFICATION)
def test_command_line_exits_2_with_usage_for_malformed_classification(raw, capsys):
    with pytest.raises(SystemExit) as exc:
        parse_args(['--auto-model-routing-classification', raw])
    assert exc.value.code == 2
    assert '--auto-model-routing-classification' in capsys.readouterr().err
