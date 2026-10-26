anthrouter returns a 429 from upstream straight to the client when the 429
carries `retry-after-ms: 1500`. It should honor that delay and retry, as it
does for 5xx responses.

Find the bug in the `anthrouter` package and fix it. Check the fix end to end,
not only in the function you change. Run the test suite with
`python3 -m pytest tests` (or, without pytest installed, `uv run --no-project
--with pytest python -m pytest tests`). Change source code only, not existing
tests.
