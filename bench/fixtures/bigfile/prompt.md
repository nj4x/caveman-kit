anthrouter's model router drops classifier responses that score exactly 100.
When the classifier model replies with the plain-text score `100`, the router
treats the reply as unparseable and falls back to the requested model instead
of routing on the score. Scores from 0 to 99 work as expected.

Find the bug in the `anthrouter` package and fix it. Change source code only,
not existing tests.
