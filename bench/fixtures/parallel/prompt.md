Two unrelated bugs were reported against anthrouter:

1. The model router drops classifier responses that score exactly 100. When
   the classifier model replies with the plain-text score `100`, the router
   treats the reply as unparseable and falls back to the requested model.
   Scores from 0 to 99 work as expected.
2. anthrouter no longer records how many upstream requests remain in the
   current rate-limit window. The token windows are still recorded.

The two bugs are independent. Investigate them in parallel: start one
subagent per bug with the Task tool, each one finding the cause and reporting
the fix. Then apply both fixes. Change source code only, not existing tests.
