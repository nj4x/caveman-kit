// caveman-kit bench — proxy preflight (ADR 0011).
//
// When ANTHROPIC_BASE_URL points at an anthproxy instance, that proxy may
// change the requested model (auto model routing, or a model lock). Such a
// run measures the wrong model. This module asks the proxy for its status
// with its local `proxy-status` command (answered by the proxy, no upstream
// call) and refuses to start when routing is on. Lock state is not reported by
// proxy-status; the README documents how to check it in the proxy log.
'use strict';

const { BenchError } = require('./isolation');

const STATUS_PROMPT = 'proxy-status';
const TIMEOUT_MS = 5000;

// Returns the base URL the run will call, or null when the run goes direct.
function proxyBaseUrl(env) {
  const url = (env.ANTHROPIC_BASE_URL || '').trim();
  return url === '' ? null : url.replace(/\/+$/, '');
}

// Resolves { routing: 'off' | 'on' } from the proxy's status text, or throws.
// fetchImpl is the test seam (global fetch by default).
async function checkProxy(baseUrl, fetchImpl = fetch) {
  let text;
  try {
    const res = await fetchImpl(`${baseUrl}/v1/messages`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ model: 'sonnet', max_tokens: 10, messages: [{ role: 'user', content: STATUS_PROMPT }] }),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    const body = await res.json();
    text = ((body && body.content) || []).map(b => (b && b.text) || '').join('\n');
  } catch (e) {
    throw new BenchError(`ANTHROPIC_BASE_URL is set to ${baseUrl}, but the proxy did not answer proxy-status: ${e.message}`);
  }
  const m = /\*\*Model routing:\*\*\s*(on|off)\b/.exec(text);
  if (!m) {
    throw new BenchError(`ANTHROPIC_BASE_URL is set to ${baseUrl}, but its proxy-status reply has no routing line; is it anthproxy?`);
  }
  if (m[1] === 'on') {
    throw new BenchError(
      `proxy at ${baseUrl} has model routing on: it changes the requested model. ` +
      'Restart it with --backends anthropic --lock-requested-model off (see bench/README.md, "Routing proxy").');
  }
  return { routing: m[1] };
}

module.exports = { proxyBaseUrl, checkProxy, STATUS_PROMPT };
