Saving model aliases from the anthrouter admin UI hangs when the value is
malformed, for example `garbage` with no `alias:model` colon. The
`POST /admin/config` request never gets a response, and the server log shows an
argparse usage line. The request dies inside `_parse_model_aliases_str`, which
calls `p.error()` on bad input and so exits. A config parser should report bad
input as an error its caller can turn into a message; the admin endpoint should
then answer 400, as it does for other invalid fields.

Fix the bug in the `anthrouter` package. Run the test suite with
`python3 -m pytest tests` (or, without pytest installed, `uv run --no-project
--with pytest python -m pytest tests`). Edit source files; existing tests stay
as they are.
