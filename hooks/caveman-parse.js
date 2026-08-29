#!/usr/bin/env node
// caveman-kit — parses a user prompt for a caveman mode change.
'use strict';

const { VALID_MODES, getDefaultMode } = require('./caveman-config');

// Returns { action: 'set', mode } | { action: 'clear' } | null.
function parseModeChange(promptRaw) {
  const prompt = (promptRaw || '').trim().toLowerCase().replace(/\s+/g, ' ');
  if (!prompt) return null;

  // Deactivation checked first so "turn caveman mode off" never falls through
  // to an activation pattern below.
  const wantsOff =
    /\b(stop|disable|deactivate|quit|exit|kill)\s+(the\s+)?caveman\b/.test(prompt) ||
    /\bcaveman(\s+mode)?\s+(off|stop|disabled?)\b/.test(prompt) ||
    /\bturn\s+off\s+(the\s+)?caveman\b/.test(prompt) ||
    // "normal mode" only as a leading command, or paired with "caveman" —
    // never mid-sentence (e.g. vim's normal mode).
    /^(please\s+)?(go\s+|back\s+to\s+|switch\s+(back\s+)?to\s+|return\s+to\s+)?normal\s+mode\b/.test(prompt) ||
    (/\bnormal\s+mode\b/.test(prompt) && /\bcaveman\b/.test(prompt));
  if (wantsOff) return { action: 'clear' };

  // Questions about caveman are not activation commands.
  const isQuestion = /^(what|whats|what's|how|why|when|where|who|does|do|did|is|are|can|could|would|should|tell me|explain)\b/.test(prompt);
  if (!isQuestion) {
    if (/\b(activate|enable|start|turn on|use|switch to|want|give me)\b[^.]{0,40}\bcaveman\b/.test(prompt) ||
        /\btalk like\b[^.]{0,40}\bcaveman\b/.test(prompt) ||
        /\bcaveman\s+mode\s+(on|please|now)\b/.test(prompt) ||
        /^caveman(\s+mode)?\s*[.!]*$/.test(prompt) ||
        /\b(less tokens|fewer tokens|be brief|be terse|shorter answers)\b(?!\s+(in|for|on|about|when|during|with)\b)/.test(prompt)) {
      const mode = getDefaultMode();
      return mode !== 'off' ? { action: 'set', mode } : null;
    }
  }

  if (prompt.startsWith('/caveman')) {
    const parts = prompt.split(/\s+/);
    if (parts[0] !== '/caveman') return null; // e.g. /caveman-foo — not us
    const arg = parts[1] || '';
    if (!arg) {
      const mode = getDefaultMode();
      return mode === 'off' ? { action: 'clear' } : { action: 'set', mode };
    }
    if (arg === 'off' || arg === 'stop' || arg === 'disable') return { action: 'clear' };
    if (VALID_MODES.includes(arg)) return { action: 'set', mode: arg };
    return null; // unknown level — leave flag untouched
  }

  return null;
}

module.exports = { parseModeChange };
