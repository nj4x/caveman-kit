The critic skill's helper script `skills/planning/critic/scripts/critic_ledger.py`
needs a `flagged` subcommand:

```
critic_ledger.py flagged <flagged-file>
```

The file holds the flagged-decisions JSON a critic agent wrote: an array of
objects, each with a `decision` and a `why_flagged` key. Agents often wrap that
JSON in a Markdown code fence (```` ```json ... ``` ````); the subcommand must
accept that too.

- Valid input: print the array as JSON on stdout, exit 0.
- Unreadable file or invalid JSON: exit 1 with a one-line reason on stderr
  starting with `PARSE_ERROR:`.
- Not an array, or an item without both keys: exit 1 with a one-line reason
  on stderr starting with `FLAGGED_DECISIONS_PARSE_ERROR:`.

Follow the script's existing conventions.
