A recent change broke anthrouter's recording of the upstream rate-limit window.
The full test suite shows the regression somewhere in its output. Run it with
`python3 -m pytest tests` (or, without pytest installed,
`uv run --no-project --with pytest python -m pytest tests`); it takes a few
minutes and prints over a thousand results.

Some failures in that run may predate this regression; leave them alone. Find
the regression and fix it in the source code, not in the tests.
