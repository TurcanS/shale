"""To-dos and reminders: a small local store, queried by day.

Times are epoch milliseconds. A repeating reminder is one row whose due time advances when it fires or is done;
repeats keep the local wall-clock time, so a daylight-saving change moves them correctly. The shell sends only
structured items: capture text is parsed in core/day.js.
"""
import datetime as dt
import os
from pathlib import Path
import sqlite3
import time

from activity import day_bounds


SCHEMA = 1
TEXT_LIMIT = 200
AWAY_MS = 60000         # a reminder delivered later than this was missed: "While you were away"
LAST_MS = 253402300799999  # 9999-12-31, the last time datetime can show
KINDS = ("todo", "reminder")
COLUMNS = ("id", "kind", "text", "created_at", "due_at", "repeat", "done_at", "fired_at", "snoozed_until",
           "breaks_focus", "position")
# Snake case in the database, camel case for the shell, as the other helper methods answer.
NAMES = {"id": "id", "kind": "kind", "text": "text", "created_at": "createdAt", "due_at": "dueAt", "repeat": "repeat",
         "done_at": "doneAt", "fired_at": "firedAt", "snoozed_until": "snoozedUntil", "breaks_focus": "breaksFocus",
         "position": "position"}
# When a reminder is next due: a snooze takes over from the due time until it fires.
AT = "COALESCE(snoozed_until, due_at)"
PENDING = "kind='reminder' AND done_at IS NULL AND (fired_at IS NULL OR fired_at < " + AT + ")"


def check_repeat(repeat):
    if repeat is None or repeat in ("daily", "weekdays"):
        return repeat
    if isinstance(repeat, str) and len(repeat) == 8 and repeat.startswith("weekly:") and repeat[7] in "0123456":
        return repeat
    raise ValueError("Choose every day, every weekday or one day of the week.")


def check_time(value, name):
    if value is None:
        return None
    if type(value) is not int or not 0 < value <= LAST_MS:
        raise ValueError("Choose a valid " + name + ".")
    return value


def check_text(value):
    text = " ".join(str(value).split()) if isinstance(value, str) else ""
    if not text:
        raise ValueError("Write what the item is.")
    if len(text) > TEXT_LIMIT:
        raise ValueError("Keep it under " + str(TEXT_LIMIT) + " characters.")
    return text


def matches(date, repeat):
    if repeat == "daily":
        return True
    if repeat == "weekdays":
        return date.weekday() < 5
    # Day numbers count from Sunday (0), as JavaScript's getDay() does.
    return date.isoweekday() % 7 == int(repeat[7])


def occurrence(due, repeat, after):
    """The first time of the series after `after`: the due time's local wall-clock time on the next matching day.
    mktime places a wall time that a daylight-saving jump skipped just after the jump."""
    wall = dt.datetime.fromtimestamp(due / 1000)
    date = max(wall.date(), dt.datetime.fromtimestamp(after / 1000).date())
    for _ in range(9):
        if matches(date, repeat):
            moment = int(time.mktime((date.year, date.month, date.day, wall.hour, wall.minute, wall.second, 0, 0, -1)) * 1000)
            if moment > after:
                return moment
        date += dt.timedelta(days=1)
    raise ValueError("Choose a valid repeat.")


class DayStore:
    def __init__(self, path, wall=time.time):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.db = sqlite3.connect(self.path)
        os.chmod(self.path, 0o600)
        self.wall = wall
        version = self.db.execute("PRAGMA user_version").fetchone()[0]
        if version > SCHEMA:
            self.db.close()
            raise ValueError("The to-do list was saved by a newer version of the shell.")
        # Each step brings an older file up to the next version; every step can run again safely.
        self.db.executescript("""
            CREATE TABLE IF NOT EXISTS items (id INTEGER PRIMARY KEY,
                kind TEXT NOT NULL CHECK(kind IN ('todo','reminder')), text TEXT NOT NULL,
                created_at INTEGER NOT NULL, due_at INTEGER, repeat TEXT, done_at INTEGER, fired_at INTEGER,
                snoozed_until INTEGER, breaks_focus INTEGER NOT NULL DEFAULT 0, position INTEGER NOT NULL DEFAULT 0,
                CHECK(kind = 'todo' OR due_at IS NOT NULL), CHECK(repeat IS NULL OR kind = 'reminder'));
            CREATE INDEX IF NOT EXISTS items_due ON items(due_at);
            CREATE INDEX IF NOT EXISTS items_done ON items(done_at);
        """)
        self.db.execute("PRAGMA user_version = " + str(SCHEMA))
        self.db.commit()

    def now(self):
        return int(self.wall() * 1000)

    def _item(self, row):
        item = {NAMES[name]: value for name, value in zip(COLUMNS, row)}
        item["breaksFocus"] = bool(item["breaksFocus"])
        item["at"] = item["snoozedUntil"] or item["dueAt"]
        return item

    def _select(self, where, args=(), order=AT + ", id"):
        rows = self.db.execute("SELECT " + ", ".join(COLUMNS) + " FROM items WHERE " + where + " ORDER BY " + order, args)
        return [self._item(row) for row in rows]

    def get(self, item_id):
        if type(item_id) is not int:
            raise ValueError("Choose an item.")
        found = self._select("id=?", (item_id,))
        if not found:
            raise ValueError("That item no longer exists.")
        return found[0]

    def add(self, fields):
        kind = fields.get("kind")
        if kind not in KINDS:
            raise ValueError("Choose a to-do or a reminder.")
        text = check_text(fields.get("text"))
        due = check_time(fields.get("dueAt"), "time")
        repeat = check_repeat(fields.get("repeat"))
        if kind == "reminder" and due is None:
            raise ValueError("A reminder needs a time.")
        if repeat and kind != "reminder":
            raise ValueError("Only reminders can repeat.")
        if repeat and due is not None and not matches(dt.datetime.fromtimestamp(due / 1000).date(), repeat):
            due = occurrence(due, repeat, due)
        position = self.db.execute("SELECT COALESCE(MAX(position), -1) + 1 FROM items WHERE kind='todo'").fetchone()[0]
        cursor = self.db.execute("INSERT INTO items (kind, text, created_at, due_at, repeat, breaks_focus, position) VALUES (?, ?, ?, ?, ?, ?, ?)",
                                 (kind, text, self.now(), due, repeat, int(fields.get("breaksFocus") is True), position))
        self.db.commit()
        return self.get(cursor.lastrowid)

    def update(self, item_id, fields):
        item = self.get(item_id)
        text = check_text(fields["text"]) if "text" in fields else item["text"]
        due = check_time(fields["dueAt"], "time") if "dueAt" in fields else item["dueAt"]
        repeat = check_repeat(fields["repeat"]) if "repeat" in fields else item["repeat"]
        breaks = fields["breaksFocus"] is True if "breaksFocus" in fields else item["breaksFocus"]
        if item["kind"] == "reminder" and due is None:
            raise ValueError("A reminder needs a time.")
        if repeat and item["kind"] != "reminder":
            raise ValueError("Only reminders can repeat.")
        if repeat and due is not None and not matches(dt.datetime.fromtimestamp(due / 1000).date(), repeat):
            due = occurrence(due, repeat, due)
        # A new time is a new appointment: it fires again, and an old snooze no longer applies.
        timing = due != item["dueAt"] or repeat != item["repeat"]
        self.db.execute("UPDATE items SET text=?, due_at=?, repeat=?, breaks_focus=?, fired_at=?, snoozed_until=? WHERE id=?",
                        (text, due, repeat, int(breaks), None if timing else item["firedAt"],
                         None if timing else item["snoozedUntil"], item_id))
        self.db.commit()
        return self.get(item_id)

    def done(self, item_id):
        item = self.get(item_id)
        if item["repeat"]:
            # Done with this occurrence: the series moves on to the next one.
            after = max(self.now(), item["dueAt"])
            self.db.execute("UPDATE items SET due_at=?, fired_at=NULL, snoozed_until=NULL WHERE id=?",
                            (occurrence(item["dueAt"], item["repeat"], after), item_id))
        elif item["doneAt"] is None:
            self.db.execute("UPDATE items SET done_at=? WHERE id=?", (self.now(), item_id))
        self.db.commit()
        return self.get(item_id)

    def undone(self, item_id):
        self.get(item_id)
        self.db.execute("UPDATE items SET done_at=NULL WHERE id=?", (item_id,))
        self.db.commit()
        return self.get(item_id)

    def delete(self, item_id):
        """Returns the removed item, so the shell can offer Undo by adding it again."""
        item = self.get(item_id)
        self.db.execute("DELETE FROM items WHERE id=?", (item_id,))
        self.db.commit()
        return item

    def snooze(self, item_id, until):
        item = self.get(item_id)
        until = check_time(until, "snooze time")
        if item["kind"] != "reminder":
            raise ValueError("Only reminders can be snoozed.")
        if until is None or until <= self.now():
            raise ValueError("Choose a later time.")
        # A one-off reminder simply moves; a repeating one keeps its series and is snoozed until it fires.
        due = item["dueAt"] if item["repeat"] else until
        self.db.execute("UPDATE items SET due_at=?, snoozed_until=?, done_at=NULL WHERE id=?", (due, until, item_id))
        self.db.commit()
        return self.get(item_id)

    def reorder(self, ids):
        if not isinstance(ids, list) or any(type(item_id) is not int for item_id in ids) or len(set(ids)) != len(ids):
            raise ValueError("Choose the to-dos to order.")
        todos = {row[0] for row in self.db.execute("SELECT id FROM items WHERE kind='todo'")}
        if not set(ids) <= todos:
            raise ValueError("Only to-dos can be ordered.")
        self.db.executemany("UPDATE items SET position=? WHERE id=?", [(position, item_id) for position, item_id in enumerate(ids)])
        self.db.commit()
        return self.todos()

    def todos(self):
        return self._select("kind='todo' AND done_at IS NULL", order="position, id")

    def list(self, day):
        """What belongs to one local day (due, snoozed to or done on it), plus every open to-do."""
        start, end = day_bounds(day)
        items = self._select("(" + AT + " >= ? AND " + AT + " < ?) OR (done_at >= ? AND done_at < ?)", (start, end, start, end))
        return {"date": day, "start": start, "end": end, "items": items, "todos": self.todos()}

    def next(self):
        """The item the bar shows next, and when the next reminder is due (the service's timer aims at it)."""
        now = self.now()
        pending = self._select(PENDING)
        timed = self._select("kind='todo' AND done_at IS NULL AND due_at > ?", (now,))
        upcoming = sorted(pending + timed, key=lambda item: (item["at"], item["id"]))
        return {"item": upcoming[0] if upcoming else None, "fireAt": pending[0]["at"] if pending else None}

    def fire(self):
        """Marks every reminder that is due as fired and returns them, each exactly once. One delivered more than a
        minute late (the shell was off, asleep or locked) is marked `away`, with the time it was due."""
        now = self.now()
        fired = []
        for item in self._select(PENDING + " AND " + AT + " <= ?", (now,)):
            item["away"] = now - item["at"] > AWAY_MS
            if item["repeat"]:
                # Missed occurrences are reported once, not one by one: the series resumes after now.
                self.db.execute("UPDATE items SET due_at=?, fired_at=?, snoozed_until=NULL WHERE id=?",
                                (occurrence(item["dueAt"], item["repeat"], now), now, item["id"]))
            else:
                self.db.execute("UPDATE items SET fired_at=?, snoozed_until=NULL WHERE id=?", (now, item["id"]))
            fired.append(item)
        self.db.commit()
        return fired

    def handle(self, method, p):
        """The day.* methods of the helper protocol."""
        if method == "day.list":
            return self.list(str(p.get("date", "")))
        if method == "day.add":
            return self.add(p)
        if method == "day.update":
            return self.update(p.get("id"), {key: p[key] for key in ("text", "dueAt", "repeat", "breaksFocus") if key in p})
        if method == "day.done":
            return self.done(p.get("id"))
        if method == "day.undone":
            return self.undone(p.get("id"))
        if method == "day.delete":
            return self.delete(p.get("id"))
        if method == "day.snooze":
            return self.snooze(p.get("id"), p.get("until"))
        if method == "day.reorder":
            return self.reorder(p.get("ids"))
        if method == "day.next":
            return self.next()
        if method == "day.fire":
            return self.fire()
        raise ValueError("Unknown day operation.")
