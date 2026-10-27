With auto model routing on, anthrouter sends some opus requests to haiku. In
one Claude Code conversation the request log shows a user turn requested as
`claude-sonnet-5-5` and routed to `claude-haiku-5-5` (classification
`trivial`). A later turn in the same conversation, requested as
`claude-opus-5-5`, also went to `claude-haiku-5-5`. That opus turn should not
have been served by haiku.

Fix the bug in the `anthrouter` package. Run the test suite with
`python3 -m pytest tests` (or, without pytest installed, `uv run --no-project
--with pytest python -m pytest tests`). Edit source files; existing tests stay
as they are.
