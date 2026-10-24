// caveman-kit bench — diagnostics from `claude --output-format stream-json`.
//
// Pure: takes the raw stdout text (one JSON event per line), returns the merged
// result event plus per-cell diagnostics. Unparseable lines are skipped.
//
// A run whose background subagents report back after the main thread stopped
// emits one result event per segment (issue #13). Each event's usage and
// num_turns cover its own segment and the main thread only; modelUsage on the
// last one is cumulative and includes the subagents. The returned result is
// the last event with usage replaced by the modelUsage sum (else the sum of
// the segments' usage, when there are several) and num_turns summed. In the
// single-segment b56c077 streams modelUsage equals usage.
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
//   subagentCalls tool_use blocks of the Task or Agent tool (a subagent spawn)
//   subagentStarts SubagentStart hook fires: hook_started system events with
//                 hook_event SubagentStart, once per hook_id (an event without
//                 hook_id counts on its own). The CLI emits
//                 them only under --include-hook-events, so a stream recorded
//                 without that flag reads 0 even when the hook ran (issue #13).
//   turns         result.num_turns (summed), else the count of distinct assistant messages
//   outputTokens  result.usage.output_tokens (whole session, see above)
//   firstCacheRead cache_read_input_tokens of the first assistant message that
//                 carries usage, else null; near 0 means the cell started with
//                 a cold prompt cache (ADR 0010)
'use strict';

const WRITE_TOOLS = new Set(['Edit', 'Write', 'MultiEdit', 'NotebookEdit']);
// CLI 2.1.287 lists the subagent tool as `Task` in its init event but names
// the tool_use blocks `Agent`; both count.
const SUBAGENT_TOOLS = new Set(['Task', 'Agent']);

// [result usage key, modelUsage key]
const USAGE_FIELDS = [
  ['input_tokens', 'inputTokens'],
  ['cache_read_input_tokens', 'cacheReadInputTokens'],
  ['cache_creation_input_tokens', 'cacheCreationInputTokens'],
  ['output_tokens', 'outputTokens'],
];

// Merges the result events of one stream; see the header comment.
function mergeResults(results) {
  if (results.length === 0) return null;
  const last = results[results.length - 1];
  const models = last.modelUsage && typeof last.modelUsage === 'object' ? Object.values(last.modelUsage) : [];
  // A last event without usage stays unusable, as callers expect.
  let usage = last.usage;
  if (!usage) return last;
  if (models.length > 0) {
    usage = Object.fromEntries(USAGE_FIELDS.map(([key, model]) => [key, models.reduce((n, m) => n + (Number(m && m[model]) || 0), 0)]));
  } else if (results.length > 1) {
    usage = Object.fromEntries(USAGE_FIELDS.map(([key]) => [key, results.reduce((n, r) => n + (Number(r.usage && r.usage[key]) || 0), 0)]));
  }
  const turns = results.map(r => r.num_turns);
  const merged = { ...last, usage };
  if (turns.every(Number.isFinite)) merged.num_turns = turns.reduce((a, b) => a + b, 0);
  return merged;
}

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
  const results = [];
  const readIds = new Set();
  const assistantIds = new Set();
  let assistantAnon = 0;
  const covered = new Map(); // path -> [[start, end), ...] since last write
  const pending = new Map(); // Read tool_use id -> { file, range }, until its result arrives
  let readChars = 0;
  let reReads = 0;
  let testRuns = 0;
  let subagentCalls = 0;
  const subagentHooks = new Set(); // hook_id of each SubagentStart hook_started
  let subagentHooksNoId = 0;
  let firstCacheRead = null;

  for (const ev of events) {
    if (ev.type === 'result') { results.push(ev); continue; }
    if (ev.type === 'system' && ev.subtype === 'hook_started' && ev.hook_event === 'SubagentStart') {
      if (ev.hook_id) subagentHooks.add(ev.hook_id); else subagentHooksNoId += 1;
      continue;
    }
    const message = ev.message;
    if (!message || !Array.isArray(message.content)) continue;
    if (ev.type === 'assistant') {
      if (message.id) assistantIds.add(message.id); else assistantAnon += 1;
      if (firstCacheRead === null && message.usage) firstCacheRead = Number(message.usage.cache_read_input_tokens) || 0;
      for (const block of message.content) {
        if (!block || block.type !== 'tool_use') continue;
        const input = block.input || {};
        if (block.name === 'Bash' && isTestCommand(input.command)) testRuns += 1;
        if (SUBAGENT_TOOLS.has(block.name)) subagentCalls += 1;
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

  const result = mergeResults(results);
  const usage = (result && result.usage) || null;
  return {
    result,
    diagnostics: {
      readChars,
      reReads,
      testRuns,
      subagentCalls,
      subagentStarts: subagentHooks.size + subagentHooksNoId,
      turns: result && Number.isFinite(result.num_turns) ? result.num_turns : assistantIds.size + assistantAnon,
      outputTokens: usage ? Number(usage.output_tokens) || 0 : 0,
      firstCacheRead,
    },
  };
}

module.exports = { analyze, isTestCommand, parseEvents };
