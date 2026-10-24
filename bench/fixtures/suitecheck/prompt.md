anthrouter's workday pace baseline is too low for users whose usage-meter
timezone is UTC: for September 2026 `workday_elapsed_pct` divides by 23
workdays, but September 2026 has only 22 weekdays.

Fix the bug. Change source code only, not existing tests.
