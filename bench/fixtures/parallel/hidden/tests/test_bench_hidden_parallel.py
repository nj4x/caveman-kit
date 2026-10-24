"""caveman-kit bench hidden test (fixture parallel): both planted bugs fixed."""

from anthrouter.http_util import parse_ratelimit_headers
from anthrouter.model_router import parse_classifier_score


def _resp(text):
    return {'content': [{'type': 'text', 'text': text}]}


class _Headers:
    def __init__(self, headers):
        self._headers = {k.lower(): v for k, v in headers.items()}

    def getheader(self, name, default=None):
        return self._headers.get(name.lower(), default)


def test_score_of_100_is_accepted():
    assert parse_classifier_score(_resp('100')) == 100
    assert parse_classifier_score(_resp(' 100\n')) == 100


def test_in_range_scores_still_parse():
    assert parse_classifier_score(_resp('0')) == 0
    assert parse_classifier_score(_resp('42')) == 42
    assert parse_classifier_score(_resp('99')) == 99


def test_out_of_range_and_malformed_scores_are_rejected():
    assert parse_classifier_score(_resp('101')) is None
    assert parse_classifier_score(_resp('-5')) is None
    assert parse_classifier_score(_resp('42/100')) is None


def test_every_remaining_window_is_recorded():
    resp = _Headers({
        'anthropic-ratelimit-requests-remaining': '42',
        'anthropic-ratelimit-tokens-remaining': '1000',
        'anthropic-ratelimit-input-tokens-remaining': '800',
        'anthropic-ratelimit-output-tokens-remaining': '200',
        'anthropic-ratelimit-tokens-reset': '2026-08-31T12:00:00Z',
    })
    assert parse_ratelimit_headers(resp) == {
        'requests_remaining': 42,
        'tokens_remaining': 1000,
        'input_tokens_remaining': 800,
        'output_tokens_remaining': 200,
        'reset_at': '2026-08-31T12:00:00Z',
    }


def test_missing_and_unparseable_values_are_omitted():
    resp = _Headers({'anthropic-ratelimit-requests-remaining': 'n/a'})
    assert parse_ratelimit_headers(resp) == {}
    assert parse_ratelimit_headers(None) == {}
