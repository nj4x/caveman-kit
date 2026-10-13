<!-- Context Diet: kit-authored, idea credited to Chisle (skills/chisle/SKILL.md). ADR 0009. -->
## Context Diet

Tool output gets re-sent every turn. Read less.
- Grep symbol first. Then Read with offset/limit, not whole file.
- Narrow at source: `ls dir`, `head`, `tail`.
- Build/test: show failures + summary only.
- Never re-read unchanged file.
- Before edit: read every line edit touches, plus context to place it.
