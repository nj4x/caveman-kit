// caveman-kit bench — diagnostics from `claude --output-format stream-json`.
//
// Pure: takes the raw stdout text (one JSON event per line), returns the final
// result event plus per-cell diagnostics. Unparseable lines are skipped.
//
//   readChars     characters in the tool_result of every Read call
//   reReads       Read calls whose line range is already covered by an earlier
//                 successful Read of the same path (no limit = first 2000
//                 lines), with no Edit/Write/MultiEdit/NotebookEdit of that
//                 path in between (a change made through Bash is not seen)
//   testRuns      Bash calls whose command invokes a test runner (isTestCommand);
//                 0 means the agent never ran tests through Bash, so "skipped
//                 verification" shows even when the hidden test passes (issue #12).
//                 A runner hidden inside a script the agent calls is not seen.
//   turns         result.num_turns, else the count of distinct assistant messages
//   outputTokens  result.usage.output_tokens
//   firstCacheRead cache_read_input_tokens of the first assistant message that
//                 carries usage, else null; near 0 means the cell started with
//                 a cold prompt cache (ADR 0010)
'use strict';

const WRITE_TOOLS = new Set(['Edit', 'Write', 'MultiEdit', 'NotebookEdit']);

// The match errs toward counting. A bare runner name (`pytest`, `tox`, `bats`,
// `jest`, ...) counts as a command word: at the start of a line, after a
// separator or quote (`cd x && pytest`, `bash -c 'pytest'`), or after a
// launcher (`uv run`, `exec`, `timeout 300`, `env X=1`), skipping flags,
// numbers and VAR=value words. An unquoted bare name inside another program's
// arguments (`cat pytest.ini`, `rg -n pytest`) does not count, but a quoted one
// does (`rg "pytest" .`). The two-word forms (`python -m pytest`, `make test`,
// `make check`, `npm test`, `go test`) count wherever they appear, so a quoted
// mention such as `grep "make test" Makefile` counts too.
// The skipped-word alternatives start with disjoint characters (`-`, a digit,
// a letter or `_`), so each word parses one way only: overlapping ones
// backtrack exponentially on a long run of `--key=value` words.
const TEST_COMMAND_RE = new RegExp([
  String.raw`(?:^|[\n;&|(\x60'"]|\b(?:run|exec|timeout|env|nice|time|xargs|npx)\b)\s*(?:(?:-\S+|\d\S*|[A-Za-z_]\w*=\S*)\s+)*(?:\S*/)?(?:pytest|py\.test|tox|nox|bats|jest|vitest|mocha|rspec)(?=\s|$|[;&|)'"])`,
  String.raw`\bpython[\d.]*\b[^;&|\n]*?\s-m\s+(?:pytest|unittest)\b`,
  String.raw`\bmake\b[^;&|\n]*?\s(?:test|check)\b`,
  String.raw`\b(?:npm|yarn|pnpm)\s+(?:run\s+)?test\b`,
  String.raw`\b(?:go|cargo)\s+test\b`,
].join('|'), 'm');

function isTestCommand(command) {
  return typeof command === 'string' && TEST_COMMAND_RE.test(command);
}

function parseEvents(text) {
  const events = [];
  for (const line of String(text || '').split('\n')) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    try { events.push(JSON.parse(trimmed)); } catch (e) { /* skip */ }
  }
  return events;
}

function contentLength(content) {
  if (typeof content === 'string') return content.length;
  if (Array.isArray(content)) {
    return content.reduce((n, part) => n + (typeof part === 'string' ? part.length : (part && typeof part.text === 'string' ? part.text.length : 0)), 0);
  }
  return 0;
}

// The Read tool returns at most this many lines when no limit is given.
const DEFAULT_READ_LINES = 2000;

// Read range as [start, end) in line numbers.
function readRange(input) {
  const num = (v, fallback) => (v !== undefined && v !== null && Number.isFinite(Number(v)) ? Number(v) : fallback);
  const start = Math.max(1, num(input.offset, 1));
  return [start, start + num(input.limit, DEFAULT_READ_LINES)];
}

function analyze(text) {
  const events = parseEvents(text);
  let result = null;
  const readIds = new Set();
  const assistantIds = new Set();
  let assistantAnon = 0;
  const covered = new Map(); // path -> [[start, end), ...] since last write
  const pending = new Map(); // Read tool_use id -> { file, range }, until its result arrives
  let readChars = 0;
  let reReads = 0;
  let testRuns = 0;
  let firstCacheRead = null;

  for (const ev of events) {
    if (ev.type === 'result') { result = ev; continue; }
    const message = ev.message;
    if (!message || !Array.isArray(message.content)) continue;
    if (ev.type === 'assistant') {
      if (message.id) assistantIds.add(message.id); else assistantAnon += 1;
      if (firstCacheRead === null && message.usage) firstCacheRead = Number(message.usage.cache_read_input_tokens) || 0;
      for (const block of message.content) {
        if (!block || block.type !== 'tool_use') continue;
        const input = block.input || {};
        if (block.name === 'Bash' && isTestCommand(input.command)) testRuns += 1;
        const file = input.file_path || input.notebook_path;
        if (block.name === 'Read' && typeof file === 'string') {
          readIds.add(block.id);
          const [start, end] = readRange(input);
          const seen = covered.get(file) || [];
          if (seen.some(([s, e]) => s <= start && e >= end)) reReads += 1;
          pending.set(block.id, { file, range: [start, end] });
        } else if (WRITE_TOOLS.has(block.name) && typeof file === 'string') {
          covered.delete(file);
          for (const [id, p] of pending) if (p.file === file) pending.delete(id);
        }
      }
    } else if (ev.type === 'user') {
      for (const block of message.content) {
        if (block && block.type === 'tool_result' && readIds.has(block.tool_use_id)) {
          readChars += contentLength(block.content);
          // Only a successful Read covers lines; an errored one gave the model nothing.
          const p = pending.get(block.tool_use_id);
          pending.delete(block.tool_use_id);
          if (p && !block.is_error) covered.set(p.file, [...(covered.get(p.file) || []), p.range]);
        }
      }
    }
  }

  const usage = (result && result.usage) || null;
  return {
    result,
    diagnostics: {
      readChars,
      reReads,
      testRuns,
      turns: result && Number.isFinite(result.num_turns) ? result.num_turns : assistantIds.size + assistantAnon,
      outputTokens: usage ? Number(usage.output_tokens) || 0 : 0,
      firstCacheRead,
    },
  };
}

module.exports = { analyze, isTestCommand, parseEvents };
