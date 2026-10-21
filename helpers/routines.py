"""Streak rules for routines (docs 15 section 8), as plain functions of dates, so they can be tested without a store."""
import datetime as dt
import re

LOOKBACK = 800


def times_a_week(rule):
    """N for a 'TIMES=N' schedule ('3 times a week'), None for a dated rule; ValueError for a bad count."""
    match = re.fullmatch(r"TIMES=(\d+)", rule or "")
    if not match:
        return None
    count = int(match.group(1))
    if not 1 <= count <= 7:
        raise ValueError("Choose between one and seven times a week.")
    return count


def day_streak(today, start, checked, due, skip):
    """(current, best) runs of due days that were checked. `due(day)` says whether the routine is due that day,
    `skip(day)` whether it is paused (a day off, a stand-down); paused days neither count nor break a run, and today
    does not break it before the day is over. A check on a day that was not due changes nothing."""
    run = best = 0
    day = max(start, today - dt.timedelta(days=LOOKBACK))
    while day <= today:
        if not skip(day) and due(day):
            if day in checked:
                run += 1
                best = max(best, run)
            elif day != today:
                run = 0
        day += dt.timedelta(days=1)
    return run, best


def week_streak(today, start, checked, wanted, first):
    """(current, best) runs of weeks with at least `wanted` checks; the running week does not break the run."""
    def begin(day):
        return day - dt.timedelta(days=(day.weekday() - first) % 7)
    counts = {}
    for day in checked:
        counts[begin(day)] = counts.get(begin(day), 0) + 1
    run = best = 0
    week = begin(max(start, today - dt.timedelta(days=LOOKBACK)))
    this = begin(today)
    while week <= this:
        if counts.get(week, 0) >= wanted:
            run += 1
            best = max(best, run)
        elif week != this:
            run = 0
        week += dt.timedelta(days=7)
    return run, best
