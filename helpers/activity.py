"""Private, local activity history. Window titles are never accepted or stored.

Time is one timeline of segments. Each segment has a state (active: recent input,
watching: no input but video or an idle inhibitor, idle: unlocked without input),
the focused app, and never crosses local midnight. Locked, asleep and paused time
has no segment. History is kept until the user clears it.
"""
import bisect
import datetime as dt
import os
from pathlib import Path
import sqlite3
import time


SCHEMA = 2
FLICKER_MS = 3000       # focus held shorter than this belongs to the app before it
STITCH_MS = 600000      # a window seen again this soon after a restart continues its row
STREAK_SECONDS = 900    # a streak day needs this much active time


def local_day(timestamp):
    return dt.datetime.fromtimestamp(timestamp).date().isoformat()


def day_bounds(day):
    date = dt.date.fromisoformat(day)
    if not 1970 <= date.year <= 9998:
        raise ValueError("Choose a valid date.")
    start = time.mktime(date.timetuple())
    end = time.mktime((date + dt.timedelta(days=1)).timetuple())
    return int(start * 1000), int(end * 1000)


def hour_totals(spans):
    """Seconds in each local hour of the day (0-23) across [start, end) millisecond spans. The local hour
    starts are worked out once for the whole range, so each span only looks them up."""
    hours = [0.0] * 24
    if not spans:
        return hours
    last = max(end for _, end in spans)
    moment = dt.datetime.fromtimestamp(min(start for start, _ in spans) / 1000).replace(minute=0, second=0, microsecond=0)
    edges, labels = [], []
    while not edges or edges[-1] <= last:
        # max() keeps the edges rising through a daylight-saving change.
        edges.append(max(int(moment.timestamp() * 1000), edges[-1] + 1 if edges else 0))
        labels.append(moment.hour)
        moment = dt.datetime.fromtimestamp(edges[-1] / 1000 + 3600).replace(minute=0, second=0, microsecond=0)
    for start, end in spans:
        index = bisect.bisect_right(edges, start) - 1
        cursor = start
        while cursor < end:
            stop = min(end, edges[index + 1])
            hours[labels[index]] += (stop - cursor) / 1000
            cursor = stop
            index += 1
    return hours


def day_spans(start_ms, end_ms):
    """Split a wall-clock interval at local midnights, including DST days."""
    cursor = start_ms
    while cursor < end_ms:
        day = local_day(cursor / 1000)
        stop = min(end_ms, day_bounds(day)[1])
        if stop <= cursor:
            break
        yield day, cursor, stop
        cursor = stop


def shift_day(day, days):
    return (dt.date.fromisoformat(day) + dt.timedelta(days=days)).isoformat()


def week_first(day, first=1):
    """The first day of the week containing `day`. `first` counts from Sunday (0), as the shell's locale does."""
    if type(first) is not int or not 0 <= first <= 6:
        raise ValueError("Choose the first day of the week.")
    date = dt.date.fromisoformat(day)
    return (date - dt.timedelta(days=(date.isoweekday() - first) % 7)).isoformat()


def has_history(path):
    """Whether an activity database holds any history, read without creating or changing it."""
    path = Path(path)
    if not path.is_file():
        return False
    try:
        db = sqlite3.connect(path.as_uri() + "?mode=ro", uri=True)
        try:
            tables = {row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
            # v1 kept "intervals" and "days"; v2 keeps segments and legacy daily totals.
            return any(db.execute("SELECT 1 FROM " + table + " LIMIT 1").fetchone()
                       for table in ("segments", "legacy_days", "intervals", "days") if table in tables)
        finally:
            db.close()
    except sqlite3.Error:
        return False


def day_range(first, last):
    date, stop = dt.date.fromisoformat(first), dt.date.fromisoformat(last)
    while date <= stop:
        yield date.isoformat()
        date += dt.timedelta(days=1)


def hour_slots(start, end):
    """Local hour slots of a day; repeated DST hours get a/b labels."""
    slots = []
    cursor = start
    while cursor < end:
        stop = min(cursor + 3600000, end)
        slots.append({"start": cursor, "end": stop, "label": dt.datetime.fromtimestamp(cursor / 1000).strftime("%H:00"),
                      "hour": dt.datetime.fromtimestamp(cursor / 1000).hour, "active": 0, "watching": 0, "unlocked": 0})
        cursor = stop
    labels = [slot["label"] for slot in slots]
    repeats = {label for label in labels if labels.count(label) > 1}
    seen = {}
    for slot in slots:
        label = slot["label"]
        if label in repeats:
            slot["label"] = label[:2] + chr(ord("a") + seen.get(label, 0))
            seen[label] = seen.get(label, 0) + 1
    return slots


def add_to_slots(slots, starts, state, start, end):
    index = max(0, bisect.bisect_right(starts, start) - 1)
    while index < len(slots) and slots[index]["start"] < end:
        overlap = max(0, min(end, slots[index]["end"]) - max(start, slots[index]["start"])) / 1000
        slots[index]["unlocked"] += overlap
        if state != "idle":
            slots[index][state] += overlap
        index += 1


def absorb_flicker(segments):
    """Merge contiguous same-state segments and give sub-threshold focus changes to the app before them.

    Segments are dicts with day/state/app/start/end, sorted by start. Totals are preserved."""
    result = []
    for segment in segments:
        previous = result[-1] if result else None
        joined = previous and previous["end"] == segment["start"] and previous["day"] == segment["day"] and previous["state"] == segment["state"]
        if joined and (previous["app"] == segment["app"] or segment["end"] - segment["start"] < FLICKER_MS):
            previous["end"] = segment["end"]
        else:
            result.append(dict(segment))
    return result


class MigrationError(ValueError):
    pass


class ActivityStore:
    def __init__(self, path, wall=time.time, monotonic=time.monotonic):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.db = sqlite3.connect(self.path)
        os.chmod(self.path, 0o600)
        self.wall = wall
        self.monotonic = monotonic
        tables = {row[0] for row in self.db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        if "intervals" in tables:
            try:
                self._migrate_v1()
            except Exception:
                self.db.close()
                raise
        self.db.executescript("""
            CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS segments (id INTEGER PRIMARY KEY, day TEXT NOT NULL,
                state TEXT NOT NULL CHECK(state IN ('active','watching','idle')), app TEXT, start INTEGER NOT NULL, end INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS windows (id INTEGER PRIMARY KEY, window_key TEXT NOT NULL, app TEXT NOT NULL,
                start INTEGER NOT NULL, end INTEGER, last_seen INTEGER NOT NULL, start_known INTEGER NOT NULL, end_reason TEXT NOT NULL DEFAULT 'open');
            CREATE TABLE IF NOT EXISTS legacy_days (day TEXT PRIMARY KEY, active REAL NOT NULL, unlocked REAL NOT NULL);
            -- Day first, then all the daily totals read: those come from the index alone, without the table.
            DROP INDEX IF EXISTS segments_day;
            CREATE INDEX IF NOT EXISTS segments_daily ON segments(day, state, start, end);
            CREATE INDEX IF NOT EXISTS segments_app ON segments(app, day);
            CREATE INDEX IF NOT EXISTS segments_start ON segments(start);
            CREATE INDEX IF NOT EXISTS windows_start ON windows(start);
            CREATE INDEX IF NOT EXISTS windows_key ON windows(window_key);
        """)
        self._set_meta("schema_version", SCHEMA)
        self.paused = self._meta("paused") == "1"
        self.started = self._meta("started")
        self._reset_runtime()
        # An open window from a former helper may have closed during downtime.
        self.db.execute("UPDATE windows SET end=last_seen, end_reason='gap' WHERE end IS NULL")
        self.db.commit()

    def _reset_runtime(self):
        self.last_wall = None
        self.last_mono = None
        self.current = None        # open segment: {id, day, state, app, start, end}
        self.pending = None        # focus change waiting out the flicker threshold: {app, since}
        self.last_change = None    # when the current state began
        self.windows = {}
        self.initial_snapshot = True

    def _meta(self, key):
        row = self.db.execute("SELECT value FROM meta WHERE key=?", (key,)).fetchone()
        return row[0] if row else None

    def _set_meta(self, key, value):
        self.db.execute("INSERT INTO meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", (key, str(value)))

    # ---- Migration -------------------------------------------------------

    def _migrate_v1(self):
        """Convert the v1 tables (intervals, focus, days) into segments. A backup is written first."""
        self.db.commit()
        backup = self.path.with_name(self.path.name + ".v1-backup")
        try:
            os.close(os.open(backup, os.O_CREAT | os.O_WRONLY, 0o600))
            os.chmod(backup, 0o600)
            target = sqlite3.connect(backup)
            try:
                self.db.backup(target)
            finally:
                target.close()
        except (OSError, sqlite3.Error) as error:
            raise MigrationError("Activity history could not be backed up before upgrading: " + str(error)) from None
        self.db.isolation_level = None
        try:
            self.db.execute("BEGIN IMMEDIATE")
            self._convert_v1()
            self.db.execute("COMMIT")
        except Exception:
            self.db.execute("ROLLBACK")
            raise
        else:
            try:
                self.db.execute("VACUUM")
            except sqlite3.Error:
                pass
        finally:
            self.db.isolation_level = ""

    def _convert_v1(self):
        db = self.db
        db.execute("""CREATE TABLE IF NOT EXISTS segments (id INTEGER PRIMARY KEY, day TEXT NOT NULL,
            state TEXT NOT NULL CHECK(state IN ('active','watching','idle')), app TEXT, start INTEGER NOT NULL, end INTEGER NOT NULL)""")
        db.execute("CREATE TABLE IF NOT EXISTS legacy_days (day TEXT PRIMARY KEY, active REAL NOT NULL, unlocked REAL NOT NULL)")
        db.execute("DELETE FROM segments")

        def merged(rows):
            result = []
            for start, end in sorted(rows):
                if end <= start:
                    continue
                if result and start <= result[-1][1]:
                    result[-1][1] = max(result[-1][1], end)
                else:
                    result.append([start, end])
            return result

        intervals = db.execute("SELECT kind,start,end FROM intervals").fetchall()
        active = merged((s, e) for kind, s, e in intervals if kind == "active")
        present = merged([(s, e) for _, s, e in intervals])
        focus = sorted((s, e, app) for app, s, e in db.execute("SELECT app,start,end FROM focus") if e > s)
        active_starts = [s for s, _ in active]
        focus_starts = [s for s, _, _ in focus]

        def covering(starts, rows, point):
            index = bisect.bisect_right(starts, point) - 1
            return rows[index] if index >= 0 and rows[index][1] > point else None

        boundaries = sorted({p for s, e in active for p in (s, e)} | {p for s, e, _ in focus for p in (s, e)})
        pieces = []
        for start, end in present:
            points = {start, end}
            points.update(boundaries[bisect.bisect_right(boundaries, start):bisect.bisect_left(boundaries, end)])
            for _, s, e in day_spans(start, end):
                points.update((s, e))
            ordered = sorted(points)
            for a, b in zip(ordered, ordered[1:]):
                if b <= a:
                    continue
                if covering(active_starts, active, a):
                    hit = covering(focus_starts, focus, a)
                    pieces.append({"day": local_day(a / 1000), "state": "active", "app": hit[2] if hit else None, "start": a, "end": b})
                else:
                    pieces.append({"day": local_day(a / 1000), "state": "idle", "app": None, "start": a, "end": b})
        db.executemany("INSERT INTO segments(day,state,app,start,end) VALUES(:day,:state,:app,:start,:end)", absorb_flicker(pieces))

        # Rejoin window rows split by former shell restarts.
        rows = db.execute("SELECT id,window_key,app,start,end,last_seen,end_reason FROM windows ORDER BY window_key,app,start").fetchall()
        keep = None
        for row in rows:
            ident, key, app, start, end, seen, reason = row
            if keep and keep[1] == key and keep[2] == app and keep[6] == "gap" and 0 <= start - keep[5] <= STITCH_MS:
                db.execute("UPDATE windows SET end=?,last_seen=?,end_reason=? WHERE id=?", (end, seen, reason, keep[0]))
                db.execute("DELETE FROM windows WHERE id=?", (ident,))
                keep = (keep[0], key, app, keep[3], end, seen, reason)
            else:
                keep = row

        # Daily totals without detail (older than the former 90-day limit) stay as legacy totals.
        expected = {day: (a, u) for day, a, u in db.execute("SELECT day,active,unlocked FROM days")}
        computed = {}
        for day, state, seconds in db.execute("SELECT day,state,SUM(end-start)/1000.0 FROM segments GROUP BY day,state"):
            totals = computed.setdefault(day, [0, 0])
            totals[1] += seconds
            if state == "active":
                totals[0] += seconds
        for day, (a, u) in expected.items():
            if day not in computed:
                db.execute("INSERT OR REPLACE INTO legacy_days(day,active,unlocked) VALUES(?,?,?)", (day, a, u))
                computed[day] = [a, u]
        for day in set(expected) | set(computed):
            want, got = expected.get(day, (0, 0)), computed.get(day, (0, 0))
            if abs(want[0] - got[0]) > 1 or abs(want[1] - got[1]) > 1:
                raise MigrationError("Activity history upgrade stopped: totals for " + day + " did not match. Your history is unchanged.")
        db.execute("DROP TABLE intervals")
        db.execute("DROP TABLE focus")
        db.execute("DROP TABLE days")
        db.execute("DROP INDEX IF EXISTS intervals_start")
        db.execute("DROP INDEX IF EXISTS focus_start")

    # ---- Recording -------------------------------------------------------

    def _insert(self, day, state, app, start, end):
        row = self.db.execute("INSERT INTO segments(day,state,app,start,end) VALUES(?,?,?,?,?)", (day, state, app, start, end))
        return {"id": row.lastrowid, "day": day, "state": state, "app": app, "start": start, "end": end}

    def _open(self, state, app, now):
        self.current = self._insert(local_day(now / 1000), state, app, now, now)

    def _extend(self, end):
        """Advance the open segment to `end`, continuing into a new segment at each local midnight."""
        current = self.current
        while current and end > current["end"]:
            boundary = day_bounds(current["day"])[1]
            stop = min(end, boundary)
            self.db.execute("UPDATE segments SET end=? WHERE id=?", (stop, current["id"]))
            current["end"] = stop
            if end > boundary:
                current = self.current = self._insert(local_day(boundary / 1000), current["state"], current["app"], boundary, boundary)

    def _advance(self, now, mono):
        if self.last_wall is None:
            self.last_wall, self.last_mono = now, mono
            return False
        elapsed = (mono - self.last_mono) * 1000
        wall_elapsed = now - self.last_wall
        gap = elapsed < 0 or elapsed > 90000 or wall_elapsed < 0 or abs(wall_elapsed - elapsed) > 5000
        end = min(now, self.last_wall + min(max(0, elapsed), 60000)) if gap else now
        if end > self.last_wall and not self.paused:
            self._extend(int(end))
        self.last_wall, self.last_mono = now, mono
        if gap:
            self._settle(int(end))
            for ident in self.windows.values():
                self.db.execute("UPDATE windows SET end=last_seen, end_reason='gap' WHERE id=?", (ident,))
            self.windows.clear()
            self.current = None
            self.last_change = None
            self.initial_snapshot = True
        return gap

    def _settle(self, now, keep=False):
        """Commit a pending focus change that outlasted the flicker threshold, retroactively from when it began.

        A shorter one is dropped (its time stays with the app before it) unless `keep` asks to wait longer."""
        pending, current = self.pending, self.current
        if not pending:
            return
        if not current or pending["app"] == current["app"]:
            self.pending = None
            return
        if now - pending["since"] < FLICKER_MS:
            if not keep:
                self.pending = None
            return
        self.pending = None
        since = pending["since"]
        if since <= current["start"]:
            self.db.execute("UPDATE segments SET app=? WHERE id=?", (pending["app"], current["id"]))
            current["app"] = pending["app"]
            return
        since = min(since, current["end"])
        self.db.execute("UPDATE segments SET end=? WHERE id=?", (since, current["id"]))
        self.current = self._insert(current["day"], current["state"], pending["app"], since, current["end"])

    def _reclassify(self, cutoff, state):
        """Time after the last input belongs to the state idle detection revealed, not to active."""
        rows = self.db.execute("SELECT id,day,app,start,end FROM segments WHERE state='active' AND end>? ORDER BY start", (cutoff,)).fetchall()
        for ident, day, app, start, end in rows:
            app = app if state == "watching" else None
            if start >= cutoff:
                self.db.execute("UPDATE segments SET state=?,app=? WHERE id=?", (state, app, ident))
            else:
                self.db.execute("UPDATE segments SET end=? WHERE id=?", (cutoff, ident))
                self._insert(day, state, app, cutoff, end)

    def _update_segment(self, state, app, now, timeout):
        app = app if state in ("active", "watching") else None
        current = self.current
        if current and state == current["state"]:
            if self.pending and self.pending["app"] == app:
                self._settle(now, keep=True)
            else:
                self._settle(now)
                if app != self.current["app"]:
                    self.pending = {"app": app, "since": now}
            return
        self._settle(now)
        if current and current["state"] == "active" and state in ("watching", "idle") and timeout > 0:
            cutoff = max(now - timeout, current["start"] if self.last_change is None else self.last_change)
            if cutoff < now:
                self._reclassify(cutoff, state)
                tail = self.db.execute("SELECT id,day,state,app,start,end FROM segments WHERE end=? AND state=? ORDER BY start DESC LIMIT 1",
                                       (now, state)).fetchone()
                if tail and tail[3] == app and tail[1] == local_day(now / 1000):
                    self.current = dict(zip(("id", "day", "state", "app", "start", "end"), tail))
                    self.last_change = now
                    return
        self.current = None
        self.last_change = now if state else None
        if state:
            self._open(state, app, now)

    def _track_windows(self, present, now):
        for key, ident in list(self.windows.items()):
            if key not in present:
                self.db.execute("UPDATE windows SET end=?,last_seen=?,end_reason='closed' WHERE id=?", (now, now, ident))
                del self.windows[key]
            else:
                self.db.execute("UPDATE windows SET last_seen=? WHERE id=?", (now, ident))
        for key, app in present.items():
            if key in self.windows:
                continue
            if self.initial_snapshot:
                row = self.db.execute("SELECT id FROM windows WHERE window_key=? AND app=? AND end_reason='gap' AND last_seen>=? "
                                      "ORDER BY last_seen DESC LIMIT 1", (key, app, now - STITCH_MS)).fetchone()
                if row:
                    self.db.execute("UPDATE windows SET end=NULL,last_seen=?,end_reason='open' WHERE id=?", (now, row[0]))
                    self.windows[key] = row[0]
                    continue
            row = self.db.execute("INSERT INTO windows(window_key,app,start,last_seen,start_known) VALUES(?,?,?,?,?)",
                                  (key, app, now, now, 0 if self.initial_snapshot else 1))
            self.windows[key] = row.lastrowid

    @staticmethod
    def classify(payload):
        if not payload.get("unlocked"):
            return None
        if not payload.get("idle"):
            return "active"
        if payload.get("inhibited") or payload.get("fullscreenMedia"):
            return "watching"
        return "idle"

    def ingest(self, payload):
        supplied = payload.get("windows", [])
        if not isinstance(supplied, list) or len(supplied) > 500:
            raise ValueError("Invalid window snapshot.")
        timeout = payload.get("idleTimeout", 0)
        if type(timeout) not in (int, float) or not 0 <= timeout <= 3600:
            raise ValueError("Invalid idle timeout.")
        now, mono = int(self.wall() * 1000), self.monotonic()
        self._advance(now, mono)
        if self.paused:
            self.db.commit()
            return self.status()
        if not self.started:
            self.started = str(now)
            self._set_meta("started", self.started)
        state = self.classify(payload)
        present = {}
        for item in supplied:
            if not isinstance(item, dict):
                continue
            key, app = str(item.get("id", ""))[:100], str(item.get("app", ""))[:100]
            if key and app and "\n" not in key and "\n" not in app:
                present[key] = app
        self._track_windows(present, now)
        focus_key = str(payload.get("focused", ""))[:100]
        self._update_segment(state, present.get(focus_key), now, int(timeout * 1000))
        self.initial_snapshot = False
        self.db.commit()
        return self.status()

    def pause(self, value):
        now, mono = int(self.wall() * 1000), self.monotonic()
        self._advance(now, mono)
        self._settle(now)
        self.paused = bool(value)
        self._set_meta("paused", "1" if self.paused else "0")
        self.current = None
        self.last_change = None
        self.windows.clear()
        self.initial_snapshot = True
        self.db.execute("UPDATE windows SET end=?,last_seen=?,end_reason='paused' WHERE end IS NULL", (now, now))
        self.db.commit()
        return self.status()

    def clear(self):
        for table in ("segments", "windows", "legacy_days"):
            self.db.execute("DELETE FROM " + table)
        self.started = None
        self.db.execute("DELETE FROM meta WHERE key='started'")
        self._reset_runtime()
        self.db.commit()
        return self.status()

    def status(self):
        state = self.current["state"] if self.current and not self.paused else None
        return {"paused": self.paused, "started": int(self.started) if self.started else None, "state": state,
                "unlocked": state is not None, "active": state == "active"}

    # ---- Queries ---------------------------------------------------------

    def _today(self):
        return local_day(self.wall())

    def _now(self):
        return int(self.wall() * 1000)

    def _daily(self, first=None, last=None):
        """Seconds per day: {day: {active, watching, unlocked}} including legacy totals."""
        where, args = "", ()
        if first:
            where, args = " WHERE day BETWEEN ? AND ?", (first, last)
        result = {}
        for day, state, ms in self.db.execute("SELECT day,state,SUM(end-start) FROM segments" + where + " GROUP BY day,state", args):
            entry = result.setdefault(day, {"date": day, "active": 0, "watching": 0, "unlocked": 0})
            entry["unlocked"] += ms / 1000
            if state != "idle":
                entry[state] += ms / 1000
        for day, active, unlocked in self.db.execute("SELECT day,active,unlocked FROM legacy_days" + where, args):
            if day not in result:
                result[day] = {"date": day, "active": active, "watching": 0, "unlocked": unlocked, "legacy": True}
        return result

    def _apps(self, first, last):
        rows = self.db.execute("SELECT app,state,SUM(end-start),MIN(start),MAX(end) FROM segments WHERE day BETWEEN ? AND ? "
                               "AND app IS NOT NULL AND state!='idle' GROUP BY app,state", (first, last))
        apps = {}
        for app, state, ms, first_seen, last_seen in rows:
            entry = apps.setdefault(app, {"app": app, "active": 0, "watching": 0, "first": first_seen, "last": last_seen})
            entry[state] = ms / 1000
            entry["first"], entry["last"] = min(entry["first"], first_seen), max(entry["last"], last_seen)
        result = sorted(apps.values(), key=lambda entry: (-(entry["active"] + entry["watching"]), entry["app"]))
        total = sum(entry["active"] + entry["watching"] for entry in result)
        for entry in result:
            entry["total"] = entry["active"] + entry["watching"]
            entry["share"] = entry["total"] / total if total else 0
        return result

    def _tracking_start_day(self):
        days = [local_day(int(self.started) / 1000)] if self.started else []
        row = self.db.execute("SELECT MIN(day) FROM legacy_days").fetchone()
        if row and row[0]:
            days.append(row[0])
        return min(days) if days else None

    def insights(self, daily=None, first=1):
        today = self._today()
        daily = daily if daily is not None else self._daily()
        origin = self._tracking_start_day() or today
        active = lambda day: daily.get(day, {}).get("active", 0)

        def average(count):
            days = [day for day in day_range(shift_day(today, -count), shift_day(today, -1)) if day >= origin]
            return sum(active(day) for day in days) / len(days) if days else None

        week = week_first(today, first)
        this_week = sum(active(day) for day in day_range(week, today))
        last_week = sum(active(day) for day in day_range(shift_day(week, -7), shift_day(today, -7)))
        streak_days = sorted(day for day, entry in daily.items() if entry["active"] >= STREAK_SECONDS)
        longest = run = 0
        previous = None
        for day in streak_days:
            run = run + 1 if previous and shift_day(previous, 1) == day else 1
            longest = max(longest, run)
            previous = day
        current = 0
        cursor = today if active(today) >= STREAK_SECONDS else shift_day(today, -1)
        streak_set = set(streak_days)
        while cursor in streak_set:
            current += 1
            cursor = shift_day(cursor, -1)

        month = shift_day(today, -30)
        starts, ends = [], []
        rows = self.db.execute("SELECT day,MIN(start),MAX(end) FROM segments WHERE state='active' AND day BETWEEN ? AND ? GROUP BY day",
                               (month, shift_day(today, -1))).fetchall()
        for day, start, end in rows:
            midnight = day_bounds(day)[0]
            starts.append((start - midnight) / 60000)
            ends.append((end - midnight) / 60000)
        hours = hour_totals(self.db.execute("SELECT start,end FROM segments WHERE state='active' AND day BETWEEN ? AND ?",
                                            (month, today)).fetchall())
        median = lambda values: sorted(values)[len(values) // 2] if values else None
        return {"today": active(today), "average7": average(7), "average30": average(30), "thisWeek": this_week,
                "lastWeek": last_week if shift_day(today, -7) >= origin else None, "streak": current, "longestStreak": longest,
                "typicalStart": median(starts), "typicalEnd": median(ends),
                "busiestHour": max(range(24), key=lambda hour: hours[hour]) if any(hours) else None}

    def overview(self, first=1):
        daily = self._daily()
        today = self._today()
        return {**self.status(), "days": [daily[day] for day in sorted(daily)], "insights": self.insights(daily, first),
                "topApps": self._apps(week_first(today, first), today)[:5], "firstDay": self._tracking_start_day()}

    def day(self, value, windows=True):
        start, end = day_bounds(value)
        now = self._now()
        totals = self._daily(value, value).get(value, {"active": 0, "watching": 0, "unlocked": 0})
        result = {"date": value, "active": totals["active"], "watching": totals["watching"], "unlocked": totals["unlocked"],
                  "legacy": bool(totals.get("legacy")), "detailAvailable": not totals.get("legacy"),
                  "segments": [], "windows": [], "hours": hour_slots(start, end), "apps": [], "firstActive": None, "lastActive": None}
        starts = [slot["start"] for slot in result["hours"]]
        for state, app, beginning, ending in self.db.execute("SELECT state,app,start,end FROM segments WHERE day=? ORDER BY start", (value,)):
            segments = result["segments"]
            if segments and segments[-1]["end"] == beginning and segments[-1]["state"] == state and segments[-1]["app"] == app:
                segments[-1]["end"] = ending
            else:
                segments.append({"state": state, "app": app, "start": beginning, "end": ending})
            add_to_slots(result["hours"], starts, state, beginning, ending)
            if state == "active":
                result["firstActive"] = beginning if result["firstActive"] is None else min(result["firstActive"], beginning)
                result["lastActive"] = ending if result["lastActive"] is None else max(result["lastActive"], ending)
        result["apps"] = self._apps(value, value)
        if windows:
            for app, beginning, ending, known, reason in self.db.execute(
                    "SELECT app,start,end,start_known,end_reason FROM windows WHERE start<? AND COALESCE(end,?)>? ORDER BY start", (end, now, start)):
                result["windows"].append({"app": app, "start": max(beginning, start), "end": min(ending or now, end),
                    "startKnown": bool(known) and beginning >= start,
                    "endReason": "continues" if ending and ending > end else reason if ending else "open"})
        return result

    def week(self, value, first=1):
        start = week_first(value, first)
        end = shift_day(start, 6)
        return {"start": start, "days": [self.day(day, windows=False) for day in day_range(start, end)], "apps": self._apps(start, end)}

    @staticmethod
    def period(kind, value, week_start=1):
        date = dt.date.fromisoformat(value)
        if kind == "day":
            first = last = date
            previous = (date - dt.timedelta(days=1),) * 2
        elif kind == "week":
            first = dt.date.fromisoformat(week_first(value, week_start))
            last = first + dt.timedelta(days=6)
            previous = (first - dt.timedelta(days=7), first - dt.timedelta(days=1))
        elif kind == "month":
            first = date.replace(day=1)
            last = (first + dt.timedelta(days=32)).replace(day=1) - dt.timedelta(days=1)
            prior = (first - dt.timedelta(days=1)).replace(day=1)
            previous = (prior, first - dt.timedelta(days=1))
        else:
            raise ValueError("Choose day, week or month.")
        return first.isoformat(), last.isoformat(), previous[0].isoformat(), previous[1].isoformat()

    def apps(self, kind, value, week_start=1):
        first, last, before_first, before_last = self.period(kind, value, week_start)
        today = self._today()
        # Compare like with like: an unfinished period is compared with the same number of days before it.
        if first <= today < last:
            span = (dt.date.fromisoformat(today) - dt.date.fromisoformat(first)).days
            before_last = min(before_last, shift_day(before_first, span))
        current = self._apps(first, last)
        previous = {entry["app"]: entry["total"] for entry in self._apps(before_first, before_last)}
        for entry in current:
            entry["previous"] = previous.get(entry["app"], 0)
        daily = self._daily(first, last)
        return {"range": kind, "start": first, "end": last, "apps": current,
                "total": sum(entry["total"] for entry in current),
                "previousTotal": sum(previous.values()),
                "days": [daily.get(day, {"date": day, "active": 0, "watching": 0, "unlocked": 0}) for day in day_range(first, last)]}

    def app(self, name, value):
        name = str(name)[:100]
        if not name:
            raise ValueError("Choose an app.")
        last = value
        first = shift_day(last, -29)
        days = {day: 0 for day in day_range(first, last)}
        hours = [0.0] * 24
        for day, start, end in self.db.execute(
                "SELECT day,start,end FROM segments WHERE app=? AND state!='idle' AND day BETWEEN ? AND ?", (name, first, last)):
            days[day] += (end - start) / 1000
            cursor = start
            while cursor < end:
                moment = dt.datetime.fromtimestamp(cursor / 1000)
                boundary = int((moment.replace(minute=0, second=0, microsecond=0) + dt.timedelta(hours=1)).timestamp() * 1000)
                stop = min(end, max(boundary, cursor + 1))
                hours[moment.hour] += (stop - cursor) / 1000
                cursor = stop
        total, used, first_day, active, watching = self.db.execute(
            "SELECT SUM(end-start)/1000.0,COUNT(DISTINCT day),MIN(day),SUM(CASE WHEN state='active' THEN end-start ELSE 0 END)/1000.0,"
            "SUM(CASE WHEN state='watching' THEN end-start ELSE 0 END)/1000.0 FROM segments WHERE app=? AND state!='idle'", (name,)).fetchone()
        return {"app": name, "days": [{"date": day, "total": seconds} for day, seconds in days.items()], "hours": hours,
                "total": total or 0, "active": active or 0, "watching": watching or 0, "daysUsed": used or 0,
                "firstDay": first_day, "averagePerDay": (total or 0) / used if used else 0}
