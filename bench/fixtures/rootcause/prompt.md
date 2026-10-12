anthrouter no longer answers Claude Code's sub-agent activity-label prompts
locally when a `<system-reminder>` block precedes them in the user message:
`is_activity_label_prompt` returns `False` for text such as

```
<system-reminder>context</system-reminder>
Describe your most recent action in 3-5 words.
```

Find the root cause and fix it where it lives, so that every caller relying on
the same code behaves correctly again, not only this one. Change source code
only, not existing tests.
