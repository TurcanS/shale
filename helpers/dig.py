"""The Dig: a stretch of days read as layers, with the marks that belong in them (docs 02 section 3.4 and 3.5).

Every mark here is read from something that was recorded: grains from the arrival log, veins from Quiet sessions,
flecks from completions, glints from the modification times of the saved captures, fossils from the pinned apps.
"""
import datetime as dt
from pathlib import Path

from activity import day_bounds, day_range, shift_day, week_first

LEVELS = ("week", "month", "year")
GRAIN_KEEP_DAYS = 400
GLINT_LIMIT = 4000
GLINT_KINDS = {".png": "shot", ".jpg": "shot", ".jpeg": "shot", ".webp": "shot",
               ".mp4": "recording", ".mkv": "recording", ".webm": "recording", ".mov": "recording", ".gif": "recording"}
BAND_MIN_MS = 60000  # a stretch shorter than this is not drawn in a week's band


def normalize(app):
    """The same app id however it is spelled: "Firefox", "firefox" and "firefox.desktop" are one app."""
    return str(app or "").strip().lower().removesuffix(".desktop")


def period(level, value, first=1):
    """First and last day (ISO) of the week, month or year that holds `value`; `first` counts from Sunday (0)."""
    if level not in LEVELS:
        raise ValueError("Choose week, month or year.")
    date = dt.date.fromisoformat(value)
    if level == "week":
        start = week_first(value, first)
        return start, shift_day(start, 6)
    if level == "month":
        begin = date.replace(day=1)
        return begin.isoformat(), ((begin + dt.timedelta(days=32)).replace(day=1) - dt.timedelta(days=1)).isoformat()
    return date.replace(month=1, day=1).isoformat(), date.replace(month=12, day=31).isoformat()


def glints(folders, start, end):
    """Capture times in [start, end) from the files in `folders`, as sorted {at, kind}.

    A file's own extension decides the kind. Only the modification time is read, never the file."""
    found = []
    for folder in folders:
        try:
            entries = list(Path(folder).expanduser().iterdir())
        except OSError:
            continue
        for entry in entries:
            kind = GLINT_KINDS.get(entry.suffix.lower())
            if not kind:
                continue
            try:
                at = int(entry.stat().st_mtime * 1000)
            except OSError:
                continue
            if start <= at < end:
                found.append({"at": at, "kind": kind})
    found.sort(key=lambda glint: glint["at"])
    return found[:GLINT_LIMIT]


def _bands(rows):
    """A day's recorded stretches as {start, end, state, app}, joining neighbours that match and dropping flickers."""
    bands = []
    for state, app, start, end in rows:
        if bands and bands[-1]["end"] == start and bands[-1]["state"] == state and bands[-1]["app"] == app:
            bands[-1]["end"] = end
        else:
            bands.append({"state": state, "app": app, "start": start, "end": end})
    return [band for band in bands if band["end"] - band["start"] >= BAND_MIN_MS]


def build(store, day_store, level, value, first=1, pinned=(), folders=(), now_ms=None):
    """The layers of one week, month or year: a list of days, newest-last, each with its totals and marks.

    `store` is the ActivityStore, `day_store` the DayStore. A year carries counts instead of every mark, so it stays
    small; a week also carries the bands of each day."""
    begin, finish = period(level, value, first)
    low, high = day_bounds(begin)[0], day_bounds(finish)[1]
    pins = {normalize(app) for app in pinned if normalize(app)}
    days = {day: {"date": day, "active": 0, "watching": 0, "apps": {}, "bands": [], "fossils": set()} for day in day_range(begin, finish)}
    for day, state, app, ms in store.db.execute(
            "SELECT day, state, app, SUM(end - start) FROM segments WHERE day BETWEEN ? AND ? AND state != 'idle' GROUP BY day, state, app",
            (begin, finish)):
        entry = days[day]
        entry[state] += ms / 1000
        if app:
            entry["apps"][app] = entry["apps"].get(app, 0) + ms / 1000
            if normalize(app) in pins:
                entry["fossils"].add(normalize(app))
    if level == "week":
        for day in days:
            days[day]["bands"] = _bands(store.db.execute("SELECT state, app, start, end FROM segments WHERE day = ? ORDER BY start", (day,)))
    for entry in days.values():
        ranked = sorted(entry["apps"].items(), key=lambda pair: (-pair[1], pair[0]))
        entry["dominant"] = ranked[0][0] if ranked else None
        entry["apps"] = [{"app": app, "seconds": seconds} for app, seconds in ranked[:3]]
        entry["fossils"] = sorted(entry["fossils"])
    detailed = level != "year"
    marks = {day: {"grains": [], "veins": [], "flecks": [], "glints": []} for day in days}

    def place(at, kind, mark):
        day = dt.datetime.fromtimestamp(at / 1000).date().isoformat()
        if day in marks:
            marks[day][kind].append(mark)

    for at, app, urgency in day_store.signals(low, high):
        place(at, "grains", {"at": at, "app": app, "urgency": urgency})
    for start, end, order_id in day_store.quiet_sessions(low, high):
        place(start, "veins", {"start": start, "end": end, "orderId": order_id})
    known = {vein["start"] for day in marks.values() for vein in day["veins"]}
    for start, end in store.db.execute("SELECT start, end FROM focus_sessions WHERE start >= ? AND start < ? ORDER BY start", (low, high)):
        if start not in known:
            place(start, "veins", {"start": start, "end": end, "orderId": None})
    for at in day_store.cleared_times(low, high):
        place(at, "flecks", {"at": at})
    for glint in glints(folders, low, high):
        place(glint["at"], "glints", glint)
    notes = day_store.notes(begin, finish)
    for day, entry in days.items():
        entry["note"] = notes.get(day)
        for kind, items in marks[day].items():
            entry[kind + "Count"] = len(items)
            entry[kind] = items if detailed else []
    return {"level": level, "start": begin, "end": finish, "days": [days[day] for day in sorted(days)]}
