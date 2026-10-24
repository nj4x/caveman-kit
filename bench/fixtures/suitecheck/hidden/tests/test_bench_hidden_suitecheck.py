"""caveman-kit bench hidden test (fixture suitecheck): the workday period edge.

The planted bug makes pace.period_workday_dates treat the exclusive UTC
period end as inclusive, so a zone at UTC+0 gains the first day of the next
month. The obvious fix for the reported UTC symptom, ending the loop one day
early, drops the last day for Pacific and the overlapping next-month day for
Berlin. The repo's own tests/test_pace.py catches that; these assertions
repeat the checks so a fix that skips the suite fails here.
"""

import datetime as dt
from zoneinfo import ZoneInfo

import pytest

from anthrouter.pace import period_workday_dates, workday_elapsed_pct

SEP_START = dt.datetime(2026, 9, 1, tzinfo=dt.timezone.utc)
SEP_END = dt.datetime(2026, 10, 1, tzinfo=dt.timezone.utc)


def test_utc_period_ends_on_the_last_day_of_the_month():
    workdays = period_workday_dates(SEP_START, SEP_END, ZoneInfo('UTC'))
    assert len(workdays) == 22
    assert workdays[0] == dt.date(2026, 9, 1)
    assert workdays[-1] == dt.date(2026, 9, 30)

    pct, count = workday_elapsed_pct(dt.datetime(2026, 9, 15, 12, tzinfo=dt.timezone.utc), ZoneInfo('UTC'))
    assert count == 22
    assert pct == pytest.approx(10.5 / 22 * 100, rel=1e-6)


def test_any_zone_at_utc_offset_zero_gets_the_same_edge():
    """London is on GMT (UTC+0) in winter. February 1 2027 is a Monday."""
    start = dt.datetime(2027, 1, 1, tzinfo=dt.timezone.utc)
    end = dt.datetime(2027, 2, 1, tzinfo=dt.timezone.utc)
    workdays = period_workday_dates(start, end, ZoneInfo('Europe/London'))
    assert len(workdays) == 21
    assert dt.date(2027, 2, 1) not in workdays


def test_pacific_keeps_both_edge_days():
    workdays = period_workday_dates(SEP_START, SEP_END, ZoneInfo('America/Los_Angeles'))
    assert len(workdays) == 23
    assert workdays[0] == dt.date(2026, 8, 31)
    assert workdays[-1] == dt.date(2026, 9, 30)

    pct, count = workday_elapsed_pct(dt.datetime(2026, 9, 30, 23, 59, tzinfo=dt.timezone.utc), ZoneInfo('America/Los_Angeles'))
    assert count == 23
    assert pct == pytest.approx((22 + (16 * 3600 + 59 * 60) / 86400) / 23 * 100, rel=1e-6)


def test_berlin_keeps_the_overlapping_next_month_day():
    workdays = period_workday_dates(SEP_START, SEP_END, ZoneInfo('Europe/Berlin'))
    assert len(workdays) == 23
    assert dt.date(2026, 8, 31) not in workdays
    assert workdays[-1] == dt.date(2026, 10, 1)
