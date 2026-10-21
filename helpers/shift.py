"""The shift and momentum rules of the Logbook, as plain functions of dates and counts (docs 15 sections 6 and 7)."""
import datetime as dt

LOOKBACK = 400


def parse_clock(text):
    """'05:00' as minutes after midnight; ValueError for anything else."""
    try:
        hours, minutes = (int(part) for part in str(text).split(":"))
    except ValueError:
        raise ValueError("Write the shift start as hh:mm.") from None
    if not (0 <= hours < 24 and 0 <= minutes < 60):
        raise ValueError("Write the shift start as hh:mm.")
    return hours * 60 + minutes


def shift_due(now, date, start, started):
    """Whether the shift start shows: once a day, from the start time on, until it has been done or skipped.
    `now` is a datetime, `date` the local day it belongs to, `start` the clock text, `started` when it was done."""
    return started is None and now.date() == date and now.hour * 60 + now.minute >= parse_clock(start)


def days_on_target(today, cleared, targets, daily, days_off, stand_down):
    """Consecutive days the target was met, counting back from `today`.

    `cleared` and `targets` map a date to a count (a day with no entry in `targets` uses `daily`); `days_off` holds
    weekday numbers (Monday is 0); `stand_down` holds dates. Days off and stand-down days neither count nor break the
    run, and today does not break it before the day is over. A daily target of 0 turns it all off (None)."""
    if daily <= 0:
        return None
    run = 0
    for back in range(LOOKBACK):
        day = today - dt.timedelta(days=back)
        if day in stand_down or day.weekday() in days_off:
            continue
        target = targets.get(day, daily)
        if target > 0 and cleared.get(day, 0) >= target:
            run += 1
        elif day != today:
            break
    return run


def week_start(day, first):
    """The first day of the week containing `day`; `first` is a weekday number (Monday is 0)."""
    return day - dt.timedelta(days=(day.weekday() - first) % 7)


def reminder_due(now, date, end, reminded):
    """Whether the shift-end reminder fires: once a day, from the end time on, until it has been given."""
    return reminded is None and now.date() == date and now.hour * 60 + now.minute >= parse_clock(end)


def split_days(start, end):
    """Seconds of the span [start, end] (datetimes) on each local day it touches, as {date: seconds}."""
    result = {}
    cursor = start
    while cursor < end:
        midnight = dt.datetime.combine(cursor.date() + dt.timedelta(days=1), dt.time())
        stop = min(end, midnight)
        result[cursor.date()] = result.get(cursor.date(), 0) + (stop - cursor).total_seconds()
        cursor = stop
    return result
