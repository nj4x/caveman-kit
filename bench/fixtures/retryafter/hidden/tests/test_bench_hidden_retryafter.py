"""caveman-kit bench hidden test (fixture retryafter): honoring upstream retry guidance.

The planted bugs sit in two files. http_util.should_retry inverts the 429
check, so a 429 with timing guidance is surfaced and one without is retried.
The repo's tests/test_transport.py catches that. transport._send_with_retries
also ignores the upstream delay and sleeps the exponential backoff instead;
no repo test records how long a retry waits, so only the sleep assertions
here catch it. A fix that stops at the inversion fails them.
"""

import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

from anthrouter.http_util import RETRY_BASE_DELAY, should_retry
from anthrouter.mapper.common import AnthropicRequestError
from anthrouter.transport import AnthropicTransport

CREDS = {'auth': ('x-api-key', 'sk-ant-secret'), 'forward': {}}


class FakeResp:
    def __init__(self, headers):
        self._headers = {k.lower(): v for k, v in headers.items()}

    def getheader(self, name, default=None):
        return self._headers.get(name.lower(), default)


class StubUpstream:
    """A local HTTP server answering with a scripted status sequence."""

    def __init__(self, script):
        self.script = list(script)
        self.requests = 0
        outer = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = 'HTTP/1.1'

            def do_POST(self):
                self.rfile.read(int(self.headers.get('content-length') or 0))
                outer.requests += 1
                status, headers = outer.script[min(outer.requests, len(outer.script)) - 1]
                payload = json.dumps({'type': 'message', 'stop_reason': 'end_turn'}).encode()
                self.send_response(status)
                for name, value in headers.items():
                    self.send_header(name, value)
                self.send_header('content-length', str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)

            def log_message(self, *args):
                pass

        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *exc):
        self.server.shutdown()
        self.server.server_close()

    @property
    def base_url(self):
        return f'http://127.0.0.1:{self.server.server_address[1]}'


@pytest.fixture
def sleeps(monkeypatch):
    recorded = []
    monkeypatch.setattr('anthrouter.transport.time.sleep', recorded.append)
    return recorded


def send(stub):
    return AnthropicTransport(stub.base_url).send_message({'model': 'sonnet', 'messages': []}, CREDS)


def test_should_retry_follows_the_timing_guidance_on_429():
    assert should_retry(429, FakeResp({'retry-after-ms': '1500'}))
    assert should_retry(429, FakeResp({'Retry-After': '7'}))
    assert not should_retry(429, FakeResp({}))
    assert not should_retry(429, None)


def test_5xx_is_always_retried_and_other_statuses_are_not():
    assert should_retry(503, FakeResp({}))
    assert should_retry(500, None)
    assert not should_retry(400, FakeResp({'retry-after-ms': '1500'}))


def test_429_with_retry_after_ms_waits_that_long_then_retries(sleeps):
    with StubUpstream([(429, {'retry-after-ms': '1500'}), (200, {})]) as stub:
        result = send(stub)
    assert result['stop_reason'] == 'end_turn'
    assert stub.requests == 2
    assert sleeps == [pytest.approx(1.5)]


def test_429_with_retry_after_seconds_waits_that_long_then_retries(sleeps):
    with StubUpstream([(429, {'Retry-After': '7'}), (200, {})]) as stub:
        send(stub)
    assert stub.requests == 2
    assert sleeps == [pytest.approx(7.0)]


def test_5xx_without_guidance_backs_off_exponentially(sleeps):
    with StubUpstream([(503, {}), (503, {}), (200, {})]) as stub:
        send(stub)
    assert stub.requests == 3
    assert sleeps == [pytest.approx(RETRY_BASE_DELAY), pytest.approx(RETRY_BASE_DELAY * 2)]


def test_429_without_guidance_surfaces_at_once(sleeps):
    with StubUpstream([(429, {})]) as stub:
        with pytest.raises(AnthropicRequestError) as exc:
            send(stub)
    assert exc.value.status_code == 429
    assert stub.requests == 1
    assert sleeps == []
