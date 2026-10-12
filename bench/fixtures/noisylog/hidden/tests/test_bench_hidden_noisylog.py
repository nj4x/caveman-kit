"""caveman-kit bench hidden test (fixture noisylog): rate-limit header parsing."""

from anthrouter.http_util import parse_ratelimit_headers


class _Resp:
    def __init__(self, headers):
        self._headers = {k.lower(): v for k, v in headers.items()}

    def getheader(self, name, default=None):
        return self._headers.get(name.lower(), default)


def test_every_remaining_window_is_recorded():
    resp = _Resp({
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
    resp = _Resp({'anthropic-ratelimit-requests-remaining': 'n/a'})
    assert parse_ratelimit_headers(resp) == {}
    assert parse_ratelimit_headers(None) == {}
