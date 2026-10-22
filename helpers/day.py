"""Work orders and reminders: a small local store, queried by day.

Times are epoch milliseconds. A repeating order is one row whose due time advances when it is cleared (a reminder
from version 1 also when it fires); repeats keep the local wall-clock time, so a daylight-saving change moves them
correctly. Every clearing is kept as a completion. The shell sends only structured items: capture text is parsed in
core/day.js and filter queries in core/filters.js.
"""
import calendar
import contextlib
import datetime as dt
import json
import os
from pathlib import Path
import re
import sqlite3
import time

from activity import day_bounds
import routines
import day_io
import shift


SCHEMA = 2
TEXT_LIMIT = 500
NOTES_LIMIT = 10000
NAME_LIMIT = 60
ALERT_LIMIT = 20
HISTORY = 50            # undoable changes kept
AWAY_MS = 60000         # a reminder delivered later than this was missed: "While you were away"
LAST_MS = 253402300799999  # 9999-12-31, the last time datetime can show
KINDS = ("todo", "reminder")
ITEM_COLUMNS = ("id", "kind", "text", "created_at", "due_at", "done_at", "position", "notes", "site_id", "section_id",
                "parent_id", "priority", "deadline_at", "all_day", "duration_min", "rule", "rule_from_done",
                "quiet_seconds")
ALERT_COLUMNS = ("id", "item_id", "at", "before_min", "fired_at", "snoozed_until", "breaks_focus")
# The rows Undo can put back; each table has an integer `id`.
TRACKED = ("items", "alerts", "sites", "sections", "tags", "item_tags", "completions", "filters")
STARTERS = (("Quick wins", "no date & !has notes & !p1"), ("Waiting", "@waiting"),
            ("This week, urgent", "ahead 7 & (p1 | p2)"))
# A version 1 reminder's delivery fields are those of its first alert; it is next due when that alert says.
FIRST = "(SELECT {} FROM alerts WHERE alerts.item_id = items.id ORDER BY alerts.id LIMIT 1)"
AT = "COALESCE(" + FIRST.format("snoozed_until") + ", items.due_at)"
WHEN = "COALESCE(a.snoozed_until, a.at, i.due_at - a.before_min * 60000)"
PENDING = "i.done_at IS NULL AND " + WHEN + " IS NOT NULL AND (a.fired_at IS NULL OR a.fired_at < " + WHEN + ")"
SELECT = ("SELECT " + ", ".join("items." + column for column in ITEM_COLUMNS) + ", sites.name, sections.name, "
          "(SELECT COUNT(*) FROM items sub WHERE sub.parent_id = items.id AND sub.done_at IS NULL) FROM items "
          "LEFT JOIN sites ON sites.id = items.site_id LEFT JOIN sections ON sections.id = items.section_id")

# Repeat rules are a small subset of iCalendar's RRULE. Weekday codes in date.weekday() order.
WEEKDAYS = ("MO", "TU", "WE", "TH", "FR", "SA", "SU")
FREQS = ("DAILY", "WEEKLY", "MONTHLY", "YEARLY")
V1_RULES = {"daily": "FREQ=DAILY", "weekdays": "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"}


def camel(name):
    """Snake case in the database, camel case for the shell, as the other helper methods answer."""
    head, *rest = name.split("_")
    return head + "".join(part.title() for part in rest)


def check_repeat(repeat):
    if repeat is None or repeat in ("daily", "weekdays"):
        return repeat
    if isinstance(repeat, str) and len(repeat) == 8 and repeat.startswith("weekly:") and repeat[7] in "0123456":
        return repeat
    raise ValueError("Choose every day, every weekday or one day of the week.")


def v1_rule(repeat):
    """The rule for a version 1 repeat; its day numbers count from Sunday (0), as JavaScript's getDay() does."""
    repeat = check_repeat(repeat)
    if repeat is None:
        return None
    return V1_RULES.get(repeat) or "FREQ=WEEKLY;BYDAY=" + WEEKDAYS[(int(repeat[7]) + 6) % 7]


def v1_repeat(rule):
    """What the hub, which still speaks version 1, calls the rule; None for rules it cannot show."""
    for repeat, known in V1_RULES.items():
        if rule == known:
            return repeat
    match = re.fullmatch("FREQ=WEEKLY;BYDAY=(MO|TU|WE|TH|FR|SA|SU)", rule or "")
    return "weekly:" + str((WEEKDAYS.index(match.group(1)) + 1) % 7) if match else None


def number(text, low, high):
    if not re.fullmatch(r"-?\d{1,4}", text) or not low <= int(text) <= high:
        raise ValueError("Choose a valid repeat.")
    return int(text)


def check_rule(rule):
    """The parts of a rule string, or ValueError for anything outside the subset."""
    if not isinstance(rule, str) or len(rule) > 200:
        raise ValueError("Choose a valid repeat.")
    parts = {}
    for part in rule.split(";"):
        key, sep, value = part.partition("=")
        if not sep or key in parts:
            raise ValueError("Choose a valid repeat.")
        parts[key] = value
    freq = parts.pop("FREQ", None)
    if freq not in FREQS:
        raise ValueError("Choose a valid repeat.")
    parsed = {"freq": freq, "interval": 1, "days": [], "monthday": None, "month": None, "until": None, "count": None}
    for key, value in parts.items():
        if key == "INTERVAL":
            parsed["interval"] = number(value, 1, 99)
        elif key == "BYDAY" and freq in ("WEEKLY", "MONTHLY"):
            for entry in value.split(","):
                match = re.fullmatch(r"(-1|[1-4])?(MO|TU|WE|TH|FR|SA|SU)", entry)
                # Weekly days are plain; a monthly day is one weekday with its place in the month ("last fri").
                if not match or (freq == "WEEKLY") != (match.group(1) is None):
                    raise ValueError("Choose a valid repeat.")
                parsed["days"].append((int(match.group(1)) if match.group(1) else None, match.group(2)))
            if freq == "MONTHLY" and len(parsed["days"]) != 1:
                raise ValueError("Choose a valid repeat.")
        elif key == "BYMONTHDAY" and freq in ("MONTHLY", "YEARLY"):
            parsed["monthday"] = number(value, -1, 31)
            if parsed["monthday"] == 0:
                raise ValueError("Choose a valid repeat.")
        elif key == "BYMONTH" and freq == "YEARLY":
            parsed["month"] = number(value, 1, 12)
        elif key == "UNTIL" and re.fullmatch(r"\d{8}", value):
            try:
                parsed["until"] = dt.date(int(value[:4]), int(value[4:6]), int(value[6:]))
            except ValueError:
                raise ValueError("Choose a valid repeat.") from None
        elif key == "COUNT":
            parsed["count"] = number(value, 1, 999)
        else:
            raise ValueError("Choose a valid repeat.")
    if (parsed["until"] and parsed["count"]) or (parsed["days"] and parsed["monthday"]):
        raise ValueError("Choose a valid repeat.")
    return parsed


def on_rule(date, rule, anchor):
    """Whether the series that started on `anchor` has an occurrence on `date` (not before `anchor`)."""
    if rule["freq"] == "DAILY":
        return (date - anchor).days % rule["interval"] == 0
    if rule["freq"] == "WEEKLY":
        weeks = ((date - anchor).days + anchor.weekday() - date.weekday()) // 7
        days = [code for _, code in rule["days"]] or [WEEKDAYS[anchor.weekday()]]
        return weeks % rule["interval"] == 0 and WEEKDAYS[date.weekday()] in days
    if rule["freq"] == "MONTHLY":
        if ((date.year - anchor.year) * 12 + date.month - anchor.month) % rule["interval"]:
            return False
    elif (date.year - anchor.year) % rule["interval"] or date.month != (rule["month"] or anchor.month):
        return False
    last = calendar.monthrange(date.year, date.month)[1]
    if rule["days"]:
        place, code = rule["days"][0]
        if WEEKDAYS[date.weekday()] != code:
            return False
        return date.day + 7 > last if place == -1 else (date.day - 1) // 7 + 1 == place
    monthday = rule["monthday"] or anchor.day
    return date.day == (last if monthday == -1 else monthday)


def wall_time(date, wall):
    """mktime places a wall time that a daylight-saving jump skipped just after the jump."""
    return int(time.mktime((date.year, date.month, date.day, wall.hour, wall.minute, wall.second, 0, 0, -1)) * 1000)


def later(date, freq, interval):
    if freq in ("DAILY", "WEEKLY"):
        return date + dt.timedelta(days=interval * (7 if freq == "WEEKLY" else 1))
    months = date.month - 1 + interval * (12 if freq == "YEARLY" else 1)
    year, month = date.year + months // 12, months % 12 + 1
    return dt.date(year, month, min(date.day, calendar.monthrange(year, month)[1]))


def occurrence(due, rule, after, done=None):
    """The first time of the series after `after`, at the due time's local wall-clock time; None when it has ended.
    With `done`, the series counts from the day it was cleared instead ("every! 3 days")."""
    rule = check_rule(rule) if isinstance(rule, str) else rule
    wall = dt.datetime.fromtimestamp(due / 1000)
    if done is not None:
        date = later(dt.datetime.fromtimestamp(done / 1000).date(), rule["freq"], rule["interval"])
        return wall_time(date, wall) if not rule["until"] or date <= rule["until"] else None
    anchor = wall.date()
    date = max(anchor, dt.datetime.fromtimestamp(after / 1000).date())
    # Long enough for a 29 February that comes only every eighth year at the largest interval.
    for _ in range(366 * 8 * rule["interval"]):
        if rule["until"] and date > rule["until"]:
            return None
        if on_rule(date, rule, anchor):
            moment = wall_time(date, wall)
            if moment > after:
                return moment
        date += dt.timedelta(days=1)
    return None


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


def check_notes(value):
    if value is None or value == "":
        return None
    if not isinstance(value, str) or len(value) > NOTES_LIMIT:
        raise ValueError("Keep notes under " + str(NOTES_LIMIT) + " characters.")
    return value


def check_name(value, what):
    name = " ".join(value.split()) if isinstance(value, str) else ""
    # A slash separates a site from its section in "#Home/Garden".
    if not name or len(name) > NAME_LIMIT or "/" in name and what != "tag":
        raise ValueError("Choose a " + what + " name of up to " + str(NAME_LIMIT) + " characters, without a slash.")
    return name


def check_flag(value, what):
    if type(value) is not bool:
        raise ValueError("Choose a valid " + what + ".")
    return value


def check_number(value, low, high, what, empty=True):
    if value is None and empty:
        return None
    if type(value) is not int or not low <= value <= high:
        raise ValueError("Choose a valid " + what + ".")
    return value


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
        self._migrate(version)
        # Added after the first run of version 2: when the shift start was done or skipped on that day.
        if "shift_started" not in [row[1] for row in self.db.execute("PRAGMA table_info(days)")]:
            self.db.execute("ALTER TABLE days ADD COLUMN shift_started INTEGER")
            self.db.commit()
        self.db.execute("CREATE TABLE IF NOT EXISTS quiet_log (start INTEGER PRIMARY KEY, end INTEGER NOT NULL)")
        # When a notification arrived and from which app: grains in the Dig. Never its text.
        self.db.execute("CREATE TABLE IF NOT EXISTS signals (at INTEGER NOT NULL, app TEXT, urgency INTEGER NOT NULL DEFAULT 1)")
        self.db.execute("CREATE INDEX IF NOT EXISTS signals_at ON signals(at)")
        self.db.execute("CREATE TABLE IF NOT EXISTS routine_alerts (routine_id INTEGER NOT NULL, date TEXT NOT NULL, UNIQUE(routine_id, date))")
        for table, column in (("quiet_log", "order_id INTEGER"), ("routines", "times INTEGER"), ("routines", "alert INTEGER NOT NULL DEFAULT 0"),
                              ("routines", "created_at INTEGER")):
            if column.split()[0] not in [row[1] for row in self.db.execute("PRAGMA table_info(" + table + ")")]:
                self.db.execute("ALTER TABLE " + table + " ADD COLUMN " + column)
        if "shift_reminded" not in [row[1] for row in self.db.execute("PRAGMA table_info(days)")]:
            self.db.execute("ALTER TABLE days ADD COLUMN shift_reminded INTEGER")
        self.db.commit()
        self._record()

    def _migrate(self, version):
        """Each step brings an older file up to the next version, in one transaction."""
        self.db.execute("BEGIN")
        try:
            self.db.execute("""CREATE TABLE IF NOT EXISTS items (id INTEGER PRIMARY KEY,
                kind TEXT NOT NULL CHECK(kind IN ('todo','reminder')), text TEXT NOT NULL,
                created_at INTEGER NOT NULL, due_at INTEGER, repeat TEXT, done_at INTEGER, fired_at INTEGER,
                snoozed_until INTEGER, breaks_focus INTEGER NOT NULL DEFAULT 0, position INTEGER NOT NULL DEFAULT 0,
                CHECK(kind = 'todo' OR due_at IS NOT NULL), CHECK(repeat IS NULL OR kind = 'reminder'))""")
            self.db.execute("CREATE INDEX IF NOT EXISTS items_due ON items(due_at)")
            self.db.execute("CREATE INDEX IF NOT EXISTS items_done ON items(done_at)")
            if version < 2:
                self._version2()
            self.db.execute("PRAGMA user_version = " + str(SCHEMA))
            self.db.commit()
        except BaseException:
            self.db.rollback()
            self.db.close()
            raise

    def _version2(self):
        """Orders: the version 1 columns stay, so the hub keeps working; repeat, fired_at, snoozed_until and
        breaks_focus are emptied as they move to `rule` and `alerts`. Each reminder becomes an order with one alert at
        its time."""
        have = {row[1] for row in self.db.execute("PRAGMA table_info(items)")}
        for column in ("notes TEXT", "site_id INTEGER", "section_id INTEGER", "parent_id INTEGER",
                       "priority INTEGER NOT NULL DEFAULT 1", "deadline_at INTEGER", "all_day INTEGER NOT NULL DEFAULT 0",
                       "duration_min INTEGER", "rule TEXT", "rule_from_done INTEGER NOT NULL DEFAULT 0",
                       "quiet_seconds INTEGER NOT NULL DEFAULT 0"):
            if column.split()[0] not in have:
                self.db.execute("ALTER TABLE items ADD COLUMN " + column)
        for statement in (
                "CREATE TABLE IF NOT EXISTS sites (id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE COLLATE NOCASE, "
                "color TEXT, position INTEGER NOT NULL DEFAULT 0, archived INTEGER NOT NULL DEFAULT 0)",
                "CREATE TABLE IF NOT EXISTS sections (id INTEGER PRIMARY KEY, site_id INTEGER NOT NULL, "
                "name TEXT NOT NULL COLLATE NOCASE, position INTEGER NOT NULL DEFAULT 0, "
                "archived INTEGER NOT NULL DEFAULT 0, UNIQUE(site_id, name))",
                "CREATE TABLE IF NOT EXISTS tags (id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE COLLATE NOCASE)",
                "CREATE TABLE IF NOT EXISTS item_tags (id INTEGER PRIMARY KEY, item_id INTEGER NOT NULL, "
                "tag_id INTEGER NOT NULL, UNIQUE(item_id, tag_id))",
                "CREATE TABLE IF NOT EXISTS alerts (id INTEGER PRIMARY KEY, item_id INTEGER NOT NULL, at INTEGER, "
                "before_min INTEGER, fired_at INTEGER, snoozed_until INTEGER, breaks_focus INTEGER NOT NULL DEFAULT 0, "
                "CHECK((at IS NULL) != (before_min IS NULL)))",
                "CREATE INDEX IF NOT EXISTS alerts_item ON alerts(item_id)",
                "CREATE TABLE IF NOT EXISTS completions (id INTEGER PRIMARY KEY, item_id INTEGER NOT NULL, "
                "done_at INTEGER NOT NULL, due_at INTEGER)",
                "CREATE INDEX IF NOT EXISTS completions_done ON completions(done_at)",
                "CREATE TABLE IF NOT EXISTS routines (id INTEGER PRIMARY KEY, name TEXT NOT NULL, rule TEXT, "
                "minute INTEGER, position INTEGER NOT NULL DEFAULT 0, archived INTEGER NOT NULL DEFAULT 0)",
                "CREATE TABLE IF NOT EXISTS routine_checks (id INTEGER PRIMARY KEY, routine_id INTEGER NOT NULL, "
                "date TEXT NOT NULL, at INTEGER NOT NULL, UNIQUE(routine_id, date))",
                "CREATE TABLE IF NOT EXISTS days (date TEXT PRIMARY KEY, target INTEGER, cleared INTEGER NOT NULL "
                "DEFAULT 0, note TEXT, stand_down INTEGER NOT NULL DEFAULT 0)",
                "CREATE TABLE IF NOT EXISTS filters (id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE COLLATE NOCASE, "
                "query TEXT NOT NULL, position INTEGER NOT NULL DEFAULT 0)",
                "CREATE TABLE IF NOT EXISTS history (id INTEGER PRIMARY KEY, label TEXT NOT NULL, at INTEGER NOT NULL, "
                "undone INTEGER NOT NULL DEFAULT 0)",
                "CREATE TABLE IF NOT EXISTS changes (id INTEGER PRIMARY KEY, step INTEGER NOT NULL, tbl TEXT NOT NULL, "
                "row_id INTEGER NOT NULL, old TEXT, new TEXT)"):
            self.db.execute(statement)
        rows = self.db.execute("SELECT id, kind, repeat, fired_at, snoozed_until, breaks_focus FROM items "
                               "WHERE kind = 'reminder' OR repeat IS NOT NULL").fetchall()
        for item_id, kind, repeat, fired, snoozed, breaks in rows:
            if kind == "reminder" and not self.db.execute("SELECT 1 FROM alerts WHERE item_id = ?", (item_id,)).fetchone():
                self.db.execute("INSERT INTO alerts (item_id, before_min, fired_at, snoozed_until, breaks_focus) "
                                "VALUES (?, 0, ?, ?, ?)", (item_id, fired, snoozed, breaks))
            self.db.execute("UPDATE items SET rule = COALESCE(?, rule), repeat = NULL, fired_at = NULL, "
                            "snoozed_until = NULL, breaks_focus = 0 WHERE id = ?", (v1_rule(repeat), item_id))
        if not self.db.execute("SELECT 1 FROM filters").fetchone():
            self.db.executemany("INSERT INTO filters (name, query, position) VALUES (?, ?, ?)",
                                [(name, query, position) for position, (name, query) in enumerate(STARTERS)])

    def _record(self):
        """Temporary triggers log every row a change writes, old and new, under the current history step; nothing is
        logged while no step is open (migration, delivering alerts, Undo itself)."""
        self.db.execute("CREATE TEMP TABLE recording (step INTEGER)")
        self.db.execute("INSERT INTO recording VALUES (NULL)")
        for table in TRACKED:
            columns = [row[1] for row in self.db.execute("PRAGMA main.table_info(" + table + ")")]

            def state(ref):
                return "json_object(" + ", ".join("'" + column + "', " + ref + "." + column for column in columns) + ")"
            for event, row, old, new in (("INSERT", "NEW", "NULL", state("NEW")), ("UPDATE", "OLD", state("OLD"), state("NEW")),
                                         ("DELETE", "OLD", state("OLD"), "NULL")):
                self.db.execute("CREATE TEMP TRIGGER " + table + "_" + event.lower() + " AFTER " + event + " ON main." + table +
                                " WHEN (SELECT step FROM recording) IS NOT NULL BEGIN INSERT INTO changes "
                                "(step, tbl, row_id, old, new) VALUES ((SELECT step FROM recording), '" + table + "', " +
                                row + ".id, " + old + ", " + new + "); END")
        self.db.commit()

    @contextlib.contextmanager
    def _change(self, label):
        """One undoable change. A new change ends what Redo could bring back; a refused one leaves no trace."""
        try:
            self.db.execute("DELETE FROM changes WHERE step IN (SELECT id FROM history WHERE undone = 1)")
            self.db.execute("DELETE FROM history WHERE undone = 1")
            step = self.db.execute("INSERT INTO history (label, at) VALUES (?, ?)", (label, self.now())).lastrowid
            self.db.execute("UPDATE recording SET step = ?", (step,))
            yield
            self.db.execute("UPDATE recording SET step = NULL")
            if not self.db.execute("SELECT 1 FROM changes WHERE step = ?", (step,)).fetchone():
                self.db.execute("DELETE FROM history WHERE id = ?", (step,))
            self.db.execute("DELETE FROM history WHERE id NOT IN (SELECT id FROM history ORDER BY id DESC LIMIT ?)", (HISTORY,))
            self.db.execute("DELETE FROM changes WHERE step NOT IN (SELECT id FROM history)")
            self.db.commit()
        except BaseException:
            self.db.rollback()
            raise

    def now(self):
        return int(self.wall() * 1000)

    def _items(self, rows):
        items = []
        for row in rows:
            item = {camel(column): value for column, value in zip(ITEM_COLUMNS, row)}
            item["allDay"], item["ruleFromDone"] = bool(item["allDay"]), bool(item["ruleFromDone"])
            item["site"], item["section"], item["openSubOrders"] = row[-3:]
            items.append(item)
        ids = [item["id"] for item in items]
        marks = ",".join("?" * len(ids))
        alerts, tags = {}, {}
        for row in self.db.execute("SELECT " + ", ".join(ALERT_COLUMNS) + " FROM alerts WHERE item_id IN (" + marks + ") ORDER BY id", ids):
            alert = {camel(column): value for column, value in zip(ALERT_COLUMNS, row)}
            alert["breaksFocus"] = bool(alert["breaksFocus"])
            alerts.setdefault(alert.pop("itemId"), []).append(alert)
        for item_id, name in self.db.execute("SELECT item_tags.item_id, tags.name FROM item_tags JOIN tags ON tags.id = item_tags.tag_id "
                                             "WHERE item_tags.item_id IN (" + marks + ") ORDER BY tags.name COLLATE NOCASE", ids):
            tags.setdefault(item_id, []).append(name)
        for item in items:
            item["alerts"], item["tags"] = alerts.get(item["id"], []), tags.get(item["id"], [])
            first = item["alerts"][0] if item["alerts"] else {}
            item["firedAt"], item["snoozedUntil"] = first.get("firedAt"), first.get("snoozedUntil")
            item["breaksFocus"] = first.get("breaksFocus", False)
            item["repeat"] = v1_repeat(item["rule"])
            item["at"] = item["snoozedUntil"] or item["dueAt"]
        return items

    def _select(self, where, args=(), order=AT + ", items.id"):
        return self._items(self.db.execute(SELECT + " WHERE " + where + " ORDER BY " + order, args).fetchall())

    def get(self, item_id):
        if type(item_id) is not int:
            raise ValueError("Choose an item.")
        found = self._select("items.id = ?", (item_id,))
        if not found:
            raise ValueError("That item no longer exists.")
        return found[0]

    def _named(self, table, name, site=None):
        """The id of a site, section or tag by name, created when first used."""
        where, args = ("name = ?", (name,)) if site is None else ("site_id = ? AND name = ?", (site, name))
        found = self.db.execute("SELECT id FROM " + table + " WHERE " + where, args).fetchone()
        if found:
            return found[0]
        if table == "tags":
            return self.db.execute("INSERT INTO tags (name) VALUES (?)", (name,)).lastrowid
        position = self.db.execute("SELECT COALESCE(MAX(position), -1) + 1 FROM " + table + ("" if site is None else " WHERE site_id = ?"),
                                   () if site is None else (site,)).fetchone()[0]
        if site is None:
            return self.db.execute("INSERT INTO sites (name, position) VALUES (?, ?)", (name, position)).lastrowid
        return self.db.execute("INSERT INTO sections (site_id, name, position) VALUES (?, ?, ?)", (site, name, position)).lastrowid

    def _row(self, table, row_id, what):
        if type(row_id) is not int:
            raise ValueError("Choose a " + what + ".")
        row = self.db.execute("SELECT * FROM " + table + " WHERE id = ?", (row_id,)).fetchone()
        if not row:
            raise ValueError("That " + what + " no longer exists.")
        return row

    def _parent(self, value, item):
        if value is None:
            return None
        parent = self.get(value) if type(value) is int else None
        if parent is None:
            raise ValueError("Choose a parent order.")
        if parent["parentId"] is not None:
            raise ValueError("Sub-orders go one level deep.")
        if item and value == item["id"]:
            raise ValueError("An order cannot be its own sub-order.")
        if item and self.db.execute("SELECT 1 FROM items WHERE parent_id = ?", (item["id"],)).fetchone():
            raise ValueError("An order with sub-orders cannot become one.")
        return value

    def _order(self, fields, item):
        """The checked columns of an order: `fields` over the current values of `item` (None for a new order)."""
        old = item or {"kind": fields.get("kind"), "priority": 1, "allDay": False, "ruleFromDone": False, "quietSeconds": 0}
        if old["kind"] not in KINDS:
            raise ValueError("Choose a to-do or a reminder.")

        def pick(key, check, *args):
            return check(fields[key], *args) if key in fields else old.get(key)
        values = {
            "text": check_text(fields.get("text")) if "text" in fields or item is None else item["text"],
            "notes": pick("notes", check_notes),
            "due_at": pick("dueAt", check_time, "time"),
            "all_day": pick("allDay", check_flag, "all-day choice"),
            "deadline_at": pick("deadlineAt", check_time, "deadline"),
            "duration_min": pick("durationMin", check_number, 1, 1440, "duration"),
            "priority": pick("priority", check_number, 1, 4, "magnitude", False),
            "rule": old.get("rule"),
            "rule_from_done": pick("ruleFromDone", check_flag, "repeat"),
            "quiet_seconds": pick("quietSeconds", check_number, 0, 10 ** 9, "recorded time", False),
            "parent_id": pick("parentId", self._parent, item),
            "site_id": old.get("siteId"),
            "section_id": old.get("sectionId"),
        }
        if "repeat" in fields:
            values["rule"] = v1_rule(fields["repeat"])
            if values["rule"] and old["kind"] != "reminder":
                raise ValueError("Only reminders can repeat.")
        if "rule" in fields:
            values["rule"] = fields["rule"] if fields["rule"] is None or check_rule(fields["rule"]) else None
        if old["kind"] == "reminder" and values["due_at"] is None:
            raise ValueError("A reminder needs a time.")
        if values["rule"] and values["due_at"] is None:
            raise ValueError("A repeat needs a due date.")
        if values["rule"]:
            rule = check_rule(values["rule"])
            due = values["due_at"]
            if not on_rule(dt.datetime.fromtimestamp(due / 1000).date(), rule, dt.datetime.fromtimestamp(due / 1000).date()):
                values["due_at"] = occurrence(due, rule, due)
                if values["due_at"] is None:
                    raise ValueError("The repeat ends before it starts.")
        if "siteId" in fields or "site" in fields:
            site = fields.get("siteId", fields.get("site"))
            if site is not None and "siteId" in fields:
                self._row("sites", site, "site")
            values["site_id"] = None if site is None else site if "siteId" in fields else self._named("sites", check_name(site, "site"))
            values["section_id"] = None
        if "sectionId" in fields or "section" in fields:
            section = fields.get("sectionId", fields.get("section"))
            if section is not None and values["site_id"] is None:
                raise ValueError("Choose a site for the section.")
            if section is not None and "sectionId" in fields and self._row("sections", section, "section")[1] != values["site_id"]:
                raise ValueError("That section belongs to another site.")
            values["section_id"] = (None if section is None else section if "sectionId" in fields
                                    else self._named("sections", check_name(section, "section"), values["site_id"]))
        return values

    def _alerts(self, item_id, fields, kind, timing):
        """A reminder keeps its one alert at its time; an order's alerts are replaced when given."""
        if kind == "reminder":
            if not self.db.execute("SELECT 1 FROM alerts WHERE item_id = ?", (item_id,)).fetchone():
                self.db.execute("INSERT INTO alerts (item_id, before_min) VALUES (?, 0)", (item_id,))
            if "breaksFocus" in fields:
                self.db.execute("UPDATE alerts SET breaks_focus = ? WHERE item_id = ?", (int(fields["breaksFocus"] is True), item_id))
        elif "alerts" in fields:
            alerts = fields["alerts"]
            if not isinstance(alerts, list) or len(alerts) > ALERT_LIMIT or not all(isinstance(alert, dict) for alert in alerts):
                raise ValueError("Choose up to " + str(ALERT_LIMIT) + " alerts.")
            due, all_day = self.db.execute("SELECT due_at, all_day FROM items WHERE id = ?", (item_id,)).fetchone()
            self.db.execute("DELETE FROM alerts WHERE item_id = ?", (item_id,))
            for alert in alerts:
                at = check_time(alert.get("at"), "alert time")
                before = check_number(alert.get("beforeMin"), 0, 10080, "alert")
                if (at is None) == (before is None):
                    raise ValueError("Choose a time for the alert, or minutes before the due time.")
                if before is not None and (due is None or all_day):
                    raise ValueError("An alert before the due time needs a due time.")
                self.db.execute("INSERT INTO alerts (item_id, at, before_min, breaks_focus) VALUES (?, ?, ?, ?)",
                                (item_id, at, before, int(alert.get("breaksFocus") is True)))
        # A new time is a new appointment: it fires again, and an old snooze no longer applies.
        if timing:
            self.db.execute("UPDATE alerts SET fired_at = NULL, snoozed_until = NULL WHERE item_id = ? AND before_min IS NOT NULL", (item_id,))

    def _tags(self, item_id, fields):
        if "tags" not in fields:
            return
        tags = fields["tags"]
        if not isinstance(tags, list) or len(tags) > 50:
            raise ValueError("Choose up to 50 tags.")
        ids = [self._named("tags", check_name(tag, "tag")) for tag in tags]
        self.db.execute("DELETE FROM item_tags WHERE item_id = ?", (item_id,))
        self.db.executemany("INSERT OR IGNORE INTO item_tags (item_id, tag_id) VALUES (?, ?)", [(item_id, tag) for tag in ids])

    def add(self, fields):
        with self._change("Add"):
            values = self._order(fields, None)
            values.update(kind=fields["kind"], created_at=self.now(), position=self.db.execute(
                "SELECT COALESCE(MAX(position), -1) + 1 FROM items WHERE kind = 'todo'").fetchone()[0])
            item_id = self.db.execute("INSERT INTO items (" + ", ".join(values) + ") VALUES (" + ", ".join("?" * len(values)) + ")",
                                      tuple(values.values())).lastrowid
            self._alerts(item_id, fields, values["kind"], False)
            self._tags(item_id, fields)
        return self.get(item_id)

    def update(self, item_id, fields):
        item = self.get(item_id)
        with self._change("Edit"):
            values = self._order(fields, item)
            self.db.execute("UPDATE items SET " + ", ".join(column + " = ?" for column in values) + " WHERE id = ?",
                            (*values.values(), item_id))
            self._alerts(item_id, fields, item["kind"], values["due_at"] != item["dueAt"] or values["rule"] != item["rule"])
            self._tags(item_id, fields)
        return self.get(item_id)

    def _clear(self, item):
        """Clears one order. A repeating one moves on to its next occurrence unless its series has ended."""
        if item["doneAt"] is not None:
            return
        now = self.now()
        self.db.execute("INSERT INTO completions (item_id, done_at, due_at) VALUES (?, ?, ?)", (item["id"], now, item["dueAt"]))
        following = None
        if item["rule"]:
            rule = check_rule(item["rule"])
            count = self.db.execute("SELECT COUNT(*) FROM completions WHERE item_id = ?", (item["id"],)).fetchone()[0]
            if not rule["count"] or count < rule["count"]:
                following = (occurrence(item["dueAt"], rule, now, done=now) if item["ruleFromDone"]
                             else occurrence(item["dueAt"], rule, max(now, item["dueAt"])))
        if following is None:
            self.db.execute("UPDATE items SET done_at = ? WHERE id = ?", (now, item["id"]))
        else:
            self.db.execute("UPDATE items SET due_at = ? WHERE id = ?", (following, item["id"]))
            self.db.execute("UPDATE alerts SET fired_at = NULL, snoozed_until = NULL WHERE item_id = ?", (item["id"],))

    def done(self, item_id):
        item = self.get(item_id)
        with self._change("Clear"):
            self._clear(item)
        return self.get(item_id)

    def complete(self, item_id, sub_orders=None):
        """Clears an order; one with open sub-orders asks first (`ask` is how many) unless `sub_orders` says whether
        to clear them too."""
        item = self.get(item_id)
        children = self._select("items.parent_id = ? AND items.done_at IS NULL", (item_id,), "items.position, items.id")
        if children and sub_orders is None:
            return {"item": item, "ask": len(children)}
        if sub_orders is not None:
            check_flag(sub_orders, "choice")
        with self._change("Clear"):
            for child in children if sub_orders else []:
                self._clear(child)
            self._clear(item)
        return {"item": self.get(item_id), "ask": 0}

    def undone(self, item_id):
        item = self.get(item_id)
        with self._change("Reopen"):
            if item["doneAt"] is not None:
                self.db.execute("DELETE FROM completions WHERE id = (SELECT MAX(id) FROM completions WHERE item_id = ?)", (item_id,))
            self.db.execute("UPDATE items SET done_at = NULL WHERE id = ?", (item_id,))
        return self.get(item_id)

    def delete(self, item_id):
        """Returns the removed item, so the shell can offer Undo by adding it again. Sub-orders go with it."""
        item = self.get(item_id)
        with self._change("Delete"):
            ids = [item_id] + [row[0] for row in self.db.execute("SELECT id FROM items WHERE parent_id = ?", (item_id,))]
            marks = ",".join("?" * len(ids))
            for table, column in (("alerts", "item_id"), ("item_tags", "item_id"), ("items", "id")):
                self.db.execute("DELETE FROM " + table + " WHERE " + column + " IN (" + marks + ")", ids)
        return item

    def snooze(self, item_id, until, alert_id=None):
        item = self.get(item_id)
        until = check_time(until, "snooze time")
        if not item["alerts"]:
            raise ValueError("Only reminders can be snoozed.")
        if until is None or until <= self.now():
            raise ValueError("Choose a later time.")
        alert = next((alert for alert in item["alerts"] if alert["id"] == alert_id), item["alerts"][0] if alert_id is None else None)
        if alert is None:
            raise ValueError("That alert no longer exists.")
        with self._change("Snooze"):
            # A one-off reminder simply moves; a repeating one, or an order, keeps its due time and the alert waits.
            due = until if item["kind"] == "reminder" and not item["rule"] else item["dueAt"]
            self.db.execute("UPDATE items SET due_at = ?, done_at = NULL WHERE id = ?", (due, item_id))
            self.db.execute("UPDATE alerts SET snoozed_until = ? WHERE id = ?", (until, alert["id"]))
        return self.get(item_id)

    def reorder(self, ids):
        if not isinstance(ids, list) or any(type(item_id) is not int for item_id in ids) or len(set(ids)) != len(ids):
            raise ValueError("Choose the to-dos to order.")
        todos = {row[0] for row in self.db.execute("SELECT id FROM items WHERE kind = 'todo'")}
        if not set(ids) <= todos:
            raise ValueError("Only to-dos can be ordered.")
        with self._change("Reorder"):
            self.db.executemany("UPDATE items SET position = ? WHERE id = ?", [(position, item_id) for position, item_id in enumerate(ids)])
        return self.todos()

    def todos(self):
        return self._select("items.kind = 'todo' AND items.done_at IS NULL", order="items.position, items.id")

    def list(self, day):
        """What belongs to one local day (due, snoozed to or done on it), plus every open to-do."""
        start, end = day_bounds(day)
        items = self._select("(" + AT + " >= ? AND " + AT + " < ?) OR (items.done_at >= ? AND items.done_at < ?)", (start, end, start, end))
        return {"date": day, "start": start, "end": end, "items": items, "todos": self.todos()}

    def orders(self, since=None):
        """Every open order, and those cleared since `since`: what core/filters.js and the views query."""
        since = check_time(since, "time")
        return self._select("items.done_at IS NULL OR items.done_at >= ?", (since or LAST_MS,), "items.position, items.id")

    def search(self, text):
        """Orders whose title, notes, site, section or tag name contain the text; title matches first, open before
        cleared, then by due time."""
        words = text.split() if isinstance(text, str) else []
        if not words or len(text) > 200:
            raise ValueError("Type what to search for.")
        score = []
        args = []
        for word in words:
            like = "%" + word.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"
            score.append("(CASE WHEN items.text LIKE ? ESCAPE '\\' THEN 4 WHEN sites.name LIKE ? ESCAPE '\\' OR sections.name LIKE ? "
                         "ESCAPE '\\' OR EXISTS (SELECT 1 FROM item_tags JOIN tags ON tags.id = item_tags.tag_id WHERE "
                         "item_tags.item_id = items.id AND tags.name LIKE ? ESCAPE '\\') THEN 2 WHEN items.notes LIKE ? "
                         "ESCAPE '\\' THEN 1 ELSE 0 END)")
            args += [like] * 5
        # Every word has to match somewhere; the order is by the sum of where each matched.
        where = " AND ".join(part + " > 0" for part in score)
        order = "(" + " + ".join(score) + ") DESC, items.done_at IS NOT NULL, items.due_at IS NULL, items.due_at, items.id"
        return self._select(where, args + args, order)

    def next(self):
        """The item the bar shows next, and when the next alert is due (the service's timer aims at it)."""
        now = self.now()
        pending = self.db.execute("SELECT DISTINCT a.item_id, " + WHEN + " FROM alerts a JOIN items i ON i.id = a.item_id WHERE " +
                                  PENDING + " ORDER BY 2, a.id").fetchall()
        items = {item["id"]: item for item in self._select("items.id IN (" + ",".join(str(row[0]) for row in pending) + ")")} if pending else {}
        upcoming = [dict(items[item_id], at=at) for item_id, at in pending]
        upcoming += self._select("items.kind = 'todo' AND items.done_at IS NULL AND items.all_day = 0 AND items.due_at > ? "
                                 "AND NOT EXISTS (SELECT 1 FROM alerts WHERE alerts.item_id = items.id)", (now,))
        upcoming.sort(key=lambda item: (item["at"], item["id"]))
        return {"item": upcoming[0] if upcoming else None, "fireAt": pending[0][1] if pending else None}

    def fire(self):
        """Marks every alert that is due as fired and returns its item, each exactly once. One delivered more than a
        minute late (the shell was off, asleep or locked) is marked `away`, with the time it was due."""
        now = self.now()
        fired = []
        for alert_id, at, item_id in self.db.execute("SELECT a.id, " + WHEN + ", a.item_id FROM alerts a JOIN items i ON i.id = a.item_id "
                                                     "WHERE " + PENDING + " AND " + WHEN + " <= ? ORDER BY 2, a.id", (now,)).fetchall():
            item = dict(self.get(item_id), at=at, alertId=alert_id, away=now - at > AWAY_MS)
            if item["kind"] == "reminder" and item["rule"]:
                # Missed occurrences are reported once, not one by one: the series resumes after now.
                following = occurrence(item["dueAt"], item["rule"], now)
                if following is not None:
                    self.db.execute("UPDATE items SET due_at = ? WHERE id = ?", (following, item_id))
            self.db.execute("UPDATE alerts SET fired_at = ?, snoozed_until = NULL WHERE id = ?", (now, alert_id))
            fired.append(item)
        self.db.commit()
        return fired

    def completions(self, start, end):
        start, end = check_time(start, "start"), check_time(end, "end")
        if start is None or end is None or end <= start:
            raise ValueError("Choose a valid period.")
        rows = self.db.execute("SELECT id, item_id, done_at, due_at FROM completions WHERE done_at >= ? AND done_at < ? ORDER BY done_at",
                               (start, end))
        return [{"id": row[0], "itemId": row[1], "doneAt": row[2], "dueAt": row[3]} for row in rows]

    # Sites, sections, tags and saved filters.

    def sites(self):
        sites = [{"id": row[0], "name": row[1], "color": row[2], "position": row[3], "archived": bool(row[4]), "sections": []}
                 for row in self.db.execute("SELECT id, name, color, position, archived FROM sites ORDER BY position, id")]
        by_id = {site["id"]: site for site in sites}
        for row in self.db.execute("SELECT id, site_id, name, position, archived FROM sections ORDER BY position, id"):
            if row[1] in by_id:
                by_id[row[1]]["sections"].append({"id": row[0], "name": row[2], "position": row[3], "archived": bool(row[4])})
        return sites

    def _edit(self, table, row_id, fields, what, columns):
        """Renames, recolours, moves or archives a site, section or filter."""
        row = self._row(table, row_id, what)
        with self._change("Edit " + what):
            for key, column in columns:
                if key not in fields:
                    continue
                value = fields[key]
                if key == "name":
                    value = check_name(value, what)
                    clash = self.db.execute("SELECT 1 FROM " + table + " WHERE name = ? AND id <> ?" +
                                            (" AND site_id = ?" if table == "sections" else ""),
                                            (value, row_id) + ((row[1],) if table == "sections" else ())).fetchone()
                    if clash:
                        raise ValueError("That " + what + " already exists.")
                elif key == "color":
                    value = None if value is None else check_name(value, "colour")
                elif key == "archived":
                    value = int(check_flag(value, "choice"))
                elif key == "query":
                    if not isinstance(value, str) or not value.strip() or len(value) > 500:
                        raise ValueError("Write the filter's query.")
                else:
                    value = check_number(value, 0, 10 ** 6, "position", False)
                self.db.execute("UPDATE " + table + " SET " + column + " = ? WHERE id = ?", (value, row_id))
        return row_id

    def handle_sites(self, method, p):
        if method == "day.sites.list":
            return self.sites()
        if method == "day.sites.add":
            name = check_name(p.get("name"), "site")
            if self.db.execute("SELECT 1 FROM sites WHERE name = ?", (name,)).fetchone():
                raise ValueError("That site already exists.")
            color = None if p.get("color") is None else check_name(p["color"], "colour")
            with self._change("Add site"):
                site = self._named("sites", name)
                self.db.execute("UPDATE sites SET color = ? WHERE id = ?", (color, site))
            return site
        if method == "day.sites.update":
            return self._edit("sites", p.get("id"), p, "site", (("name", "name"), ("color", "color"), ("position", "position"),
                                                               ("archived", "archived")))
        if method == "day.sites.delete":
            # Its orders stay, in Intake.
            self._row("sites", p.get("id"), "site")
            with self._change("Delete site"):
                self.db.execute("UPDATE items SET site_id = NULL, section_id = NULL WHERE site_id = ?", (p["id"],))
                self.db.execute("DELETE FROM sections WHERE site_id = ?", (p["id"],))
                self.db.execute("DELETE FROM sites WHERE id = ?", (p["id"],))
            return p["id"]
        if method == "day.sections.add":
            site = self._row("sites", p.get("siteId"), "site")[0]
            name = check_name(p.get("name"), "section")
            if self.db.execute("SELECT 1 FROM sections WHERE site_id = ? AND name = ?", (site, name)).fetchone():
                raise ValueError("That section already exists.")
            with self._change("Add section"):
                return self._named("sections", name, site)
        if method == "day.sections.update":
            return self._edit("sections", p.get("id"), p, "section", (("name", "name"), ("position", "position"), ("archived", "archived")))
        if method == "day.sections.delete":
            self._row("sections", p.get("id"), "section")
            with self._change("Delete section"):
                self.db.execute("UPDATE items SET section_id = NULL WHERE section_id = ?", (p["id"],))
                self.db.execute("DELETE FROM sections WHERE id = ?", (p["id"],))
            return p["id"]
        raise ValueError("Unknown day operation.")

    def tags(self):
        return [{"id": row[0], "name": row[1], "count": row[2]} for row in self.db.execute(
            "SELECT tags.id, tags.name, (SELECT COUNT(*) FROM item_tags JOIN items ON items.id = item_tags.item_id "
            "WHERE item_tags.tag_id = tags.id AND items.done_at IS NULL) FROM tags ORDER BY tags.name COLLATE NOCASE")]

    def handle_tags(self, method, p):
        if method == "day.tags.list":
            return self.tags()
        if method == "day.tags.rename":
            return self._edit("tags", p.get("id"), {"name": p.get("name")}, "tag", (("name", "name"),))
        if method == "day.tags.delete":
            self._row("tags", p.get("id"), "tag")
            with self._change("Delete tag"):
                self.db.execute("DELETE FROM item_tags WHERE tag_id = ?", (p["id"],))
                self.db.execute("DELETE FROM tags WHERE id = ?", (p["id"],))
            return p["id"]
        raise ValueError("Unknown day operation.")

    def filters(self):
        return [{"id": row[0], "name": row[1], "query": row[2], "position": row[3]}
                for row in self.db.execute("SELECT id, name, query, position FROM filters ORDER BY position, id")]

    def handle_filters(self, method, p):
        """Saved filters; their queries are checked and run by core/filters.js, which the views share."""
        if method == "day.filters.list":
            return self.filters()
        if method == "day.filters.add":
            name = check_name(p.get("name"), "filter")
            if self.db.execute("SELECT 1 FROM filters WHERE name = ?", (name,)).fetchone():
                raise ValueError("That filter already exists.")
            query = p.get("query")
            if not isinstance(query, str) or not query.strip() or len(query) > 500:
                raise ValueError("Write the filter's query.")
            with self._change("Add filter"):
                position = self.db.execute("SELECT COALESCE(MAX(position), -1) + 1 FROM filters").fetchone()[0]
                return self.db.execute("INSERT INTO filters (name, query, position) VALUES (?, ?, ?)", (name, query, position)).lastrowid
        if method == "day.filters.update":
            return self._edit("filters", p.get("id"), p, "filter", (("name", "name"), ("query", "query"), ("position", "position")))
        if method == "day.filters.delete":
            self._row("filters", p.get("id"), "filter")
            with self._change("Delete filter"):
                self.db.execute("DELETE FROM filters WHERE id = ?", (p["id"],))
            return p["id"]
        raise ValueError("Unknown day operation.")

    # Undo and Redo across every change kind.

    def _restore(self, table, row_id, state):
        if table not in TRACKED:
            raise ValueError("The change history is damaged.")
        if state is None:
            self.db.execute("DELETE FROM " + table + " WHERE id = ?", (row_id,))
            return
        values = json.loads(state)
        self.db.execute("INSERT OR REPLACE INTO " + table + " (" + ", ".join(values) + ") VALUES (" + ", ".join("?" * len(values)) + ")",
                        tuple(values.values()))

    def undo(self, redo=False):
        """Puts back the rows of the last change (or brings back the last undone one); returns its label."""
        step = self.db.execute("SELECT id, label FROM history WHERE undone = ? ORDER BY id " + ("ASC" if redo else "DESC") + " LIMIT 1",
                               (int(redo),)).fetchone()
        if not step:
            raise ValueError("Nothing to redo." if redo else "Nothing to undo.")
        try:
            for table, row_id, old, new in self.db.execute("SELECT tbl, row_id, old, new FROM changes WHERE step = ? ORDER BY id " +
                                                          ("ASC" if redo else "DESC"), (step[0],)).fetchall():
                self._restore(table, row_id, new if redo else old)
            self.db.execute("UPDATE history SET undone = ? WHERE id = ?", (int(not redo), step[0]))
            self.db.commit()
        except BaseException:
            self.db.rollback()
            raise
        return {"label": step[1], "redo": redo}

    def history(self):
        return [{"id": row[0], "label": row[1], "at": row[2], "undone": bool(row[3])}
                for row in self.db.execute("SELECT id, label, at, undone FROM history ORDER BY id DESC")]

    # The shift and momentum (docs 15 sections 6 and 7).

    def _day(self, date):
        row = self.db.execute("SELECT target, note, stand_down, shift_started, shift_reminded FROM days WHERE date = ?", (date,)).fetchone()
        return {"date": date, "target": row[0] if row else None, "note": row[1] if row else None,
                "standDown": bool(row[2]) if row else False, "shiftStarted": row[3] if row else None,
                "shiftReminded": row[4] if row else None}

    def _set_day(self, date, **columns):
        self.db.execute("INSERT OR IGNORE INTO days (date) VALUES (?)", (date,))
        for column, value in columns.items():
            self.db.execute("UPDATE days SET " + column + " = ? WHERE date = ?", (value, date))
        self.db.commit()

    @staticmethod
    def _date(value):
        try:
            return dt.date.fromisoformat(value)
        except (TypeError, ValueError):
            raise ValueError("Choose a valid day.") from None

    def day_state(self, date, fields=None):
        """A day's record; `fields` (target, note, standDown) are saved first. A note keeps up to 500 characters."""
        self._date(date)
        if fields:
            columns = {}
            if "target" in fields:
                columns["target"] = None if fields["target"] is None else check_number(fields["target"], 0, 1000, "target", False)
            if "note" in fields:
                note = fields["note"]
                if note is not None and (not isinstance(note, str) or len(note) > 500):
                    raise ValueError("Keep the day's note under 500 characters.")
                columns["note"] = note or None
            if "standDown" in fields:
                columns["stand_down"] = int(check_flag(fields["standDown"], "stand-down choice"))
            self._set_day(date, **columns)
        return self._day(date)

    def shift_state(self, date, start, now=None):
        """Whether the shift start shows for `date` (once a day, after `start`), and the day's record."""
        day = self._date(date)
        moment = dt.datetime.fromtimestamp((now if now is not None else self.now()) / 1000)
        return {"due": shift.shift_due(moment, day, start, self._day(date)["shiftStarted"]), "day": self._day(date)}

    def shift_reminder(self, date, end, now=None):
        """True once a day, from the shift end time on: the reminder is due, and is marked as given."""
        day = self._date(date)
        moment = dt.datetime.fromtimestamp((now if now is not None else self.now()) / 1000)
        if not shift.reminder_due(moment, day, end, self._day(date)["shiftReminded"]):
            return {"due": False}
        self._set_day(date, shift_reminded=self.now())
        return {"due": True}

    # What the Dig reads (docs 02 section 3.5).

    def signal_log(self, at, app, urgency):
        """Keeps the arrival of one notification: its time, app and urgency, nothing else."""
        at = check_time(at, "time")
        if at is None:
            raise ValueError("Choose a valid time.")
        app = str(app or "")[:100]
        urgency = urgency if type(urgency) is int and 0 <= urgency <= 2 else 1
        self.db.execute("INSERT INTO signals (at, app, urgency) VALUES (?, ?, ?)", (at, app, urgency))
        self.db.execute("DELETE FROM signals WHERE at < ?", (at - 400 * 86400000,))
        self.db.commit()
        return {"logged": True}

    def clear_signals(self):
        self.db.execute("DELETE FROM signals")
        self.db.commit()

    def signals(self, start, end):
        return self.db.execute("SELECT at, app, urgency FROM signals WHERE at >= ? AND at < ? ORDER BY at", (start, end)).fetchall()

    def quiet_sessions(self, start, end):
        return self.db.execute("SELECT start, end, order_id FROM quiet_log WHERE start >= ? AND start < ? ORDER BY start", (start, end)).fetchall()

    def cleared_times(self, start, end):
        return [row[0] for row in self.db.execute(
            "SELECT done_at FROM completions WHERE done_at >= ? AND done_at < ? ORDER BY done_at", (start, end))]

    def notes(self, first, last):
        """The shift-report note of each day between two dates, as {date: text}."""
        return {row[0]: row[1] for row in self.db.execute(
            "SELECT date, note FROM days WHERE date BETWEEN ? AND ? AND note IS NOT NULL AND note != ''", (first, last))}

    def quiet_log(self, start, end, order_id=None):
        """Keeps one Quiet session (keyed by its start, so a resumed session replaces its earlier end). One started on an
        order logs its seconds on it: the order's total is always the sum of its sessions."""
        start, end = check_time(start, "start"), check_time(end, "end")
        if start is None or end is None or end <= start or end - start > 24 * 3600 * 1000:
            raise ValueError("Choose a valid Quiet period.")
        if order_id is not None:
            self.get(order_id)
        self.db.execute("INSERT OR REPLACE INTO quiet_log (start, end, order_id) VALUES (?, ?, ?)", (start, end, order_id))
        for (linked,) in self.db.execute("SELECT DISTINCT order_id FROM quiet_log WHERE order_id IS NOT NULL").fetchall():
            self.db.execute("UPDATE items SET quiet_seconds = (SELECT COALESCE(SUM(end - start), 0) / 1000 FROM quiet_log WHERE order_id = ?) "
                            "WHERE id = ?", (linked, linked))
        self.db.execute("DELETE FROM quiet_log WHERE start < ?", (start - 420 * 86400000,))
        self.db.commit()
        return {"logged": True}

    def shift_start(self, date, target=None):
        """Marks the shift start as done (or skipped) and keeps the day's target when one is given."""
        self._date(date)
        if target is None:
            self._set_day(date, shift_started=self.now())
        else:
            self._set_day(date, shift_started=self.now(), target=check_number(target, 0, 1000, "target", False))
        return self._day(date)

    def carry_list(self, date):
        """Open orders that were due before `date` and not cleared: the carry-over screen."""
        start, _ = day_bounds(date)
        return self._select("items.done_at IS NULL AND items.parent_id IS NULL AND items.due_at IS NOT NULL AND items.due_at < ?",
                            (start,), "items.due_at, items.id")

    def carry_apply(self, date, choices):
        """Applies one choice per order in one undoable step: keep (due today, the time of day kept), move (1 to 7
        days from today), intake (no site, no date) or drop (deleted)."""
        self._date(date)
        if not isinstance(choices, list) or len(choices) > 500:
            raise ValueError("Choose what to do with each order.")
        today = dt.date.fromisoformat(date)
        for choice in choices:
            if not isinstance(choice, dict) or choice.get("action") not in ("keep", "move", "intake", "drop"):
                raise ValueError("Choose keep, move, intake or drop.")
            if choice["action"] == "move":
                check_number(choice.get("days"), 1, 7, "number of days", False)
        with self._change("Carry over"):
            for choice in choices:
                item = self.get(choice["id"])
                action = choice["action"]
                if action == "drop":
                    self.db.execute("DELETE FROM alerts WHERE item_id = ?", (item["id"],))
                    self.db.execute("DELETE FROM item_tags WHERE item_id = ?", (item["id"],))
                    self.db.execute("DELETE FROM items WHERE id = ? OR parent_id = ?", (item["id"], item["id"]))
                elif action == "intake":
                    self.db.execute("UPDATE items SET site_id = NULL, section_id = NULL, due_at = NULL, all_day = 0 WHERE id = ?", (item["id"],))
                elif item["dueAt"] is not None:
                    target = today + dt.timedelta(days=choice["days"] if action == "move" else 0)
                    old = dt.datetime.fromtimestamp(item["dueAt"] / 1000)
                    moved = dt.datetime.combine(target, old.time())
                    self.db.execute("UPDATE items SET due_at = ? WHERE id = ?", (int(time.mktime(moved.timetuple()) * 1000), item["id"]))
        return {"carried": len(choices)}

    def carry_auto(self, date):
        """The automatic carry-over: orders due on an earlier day with no time of day (all-day ones) move to `date`,
        in one undoable step. Orders with a time are left for the shift start's own screen."""
        orders = [item for item in self.carry_list(date) if item["allDay"]]
        if orders:
            self.carry_apply(date, [{"id": item["id"], "action": "keep"} for item in orders])
        return {"carried": len(orders)}

    def momentum(self, date, daily, weekly, days_off=(), first=0, weeks=4):
        """Targets and streaks as of `date`: today's count and target, the week, days on target, cleared per day (and by
        site) over `weeks` weeks. `daily` 0 turns targets off: then `onTarget` and `daysOnTarget` are None."""
        today = self._date(date)
        daily = check_number(daily, 0, 1000, "daily target", False) or 0
        weekly = check_number(weekly, 0, 10000, "weekly target", False) or 0
        if not all(isinstance(day, int) and 0 <= day <= 6 for day in days_off) or not isinstance(first, int) or not 0 <= first <= 6:
            raise ValueError("Choose weekdays from Monday to Sunday.")
        horizon = today - dt.timedelta(days=shift.LOOKBACK)
        low, _ = day_bounds(horizon.isoformat())
        cleared, by_site = {}, {}
        for done_at, site in self.db.execute(
                "SELECT completions.done_at, COALESCE(sites.name, '') FROM completions JOIN items ON items.id = completions.item_id "
                "LEFT JOIN sites ON sites.id = items.site_id WHERE completions.done_at >= ?", (low,)):
            day = dt.datetime.fromtimestamp(done_at / 1000).date()
            cleared[day] = cleared.get(day, 0) + 1
            by_site.setdefault(day, {})
            by_site[day][site] = by_site[day].get(site, 0) + 1
        records = {self._date(row[0]): row for row in self.db.execute("SELECT date, target, stand_down FROM days WHERE date >= ?", (horizon.isoformat(),))}
        targets = {day: row[1] for day, row in records.items() if row[1] is not None}
        stand = {day for day, row in records.items() if row[2]}
        today_target = targets.get(today, daily)
        begin = shift.week_start(today, first)
        span = (today - dt.timedelta(days=weeks * 7 - 1))
        per_day = [{"date": (span + dt.timedelta(days=n)).isoformat(), "cleared": cleared.get(span + dt.timedelta(days=n), 0),
                    "bySite": by_site.get(span + dt.timedelta(days=n), {})} for n in range(weeks * 7)]
        quiet = {}
        for q_start, q_end in self.db.execute("SELECT start, end FROM quiet_log WHERE end >= ?", (low,)):
            for day, seconds in shift.split_days(dt.datetime.fromtimestamp(q_start / 1000), dt.datetime.fromtimestamp(q_end / 1000)).items():
                quiet[day] = quiet.get(day, 0) + seconds
        for entry in per_day:
            entry["quietMinutes"] = round(quiet.get(dt.date.fromisoformat(entry["date"]), 0) / 60)
        count = cleared.get(today, 0)
        return {"date": date, "enabled": daily > 0, "cleared": count, "target": today_target,
                "onTarget": None if daily <= 0 else (today_target > 0 and count >= today_target),
                "weekCleared": sum(n for day, n in cleared.items() if begin <= day <= today), "weekTarget": weekly,
                "daysOnTarget": shift.days_on_target(today, cleared, targets, daily, set(days_off), stand),
                "standDown": today in stand, "dayOff": today.weekday() in days_off, "perDay": per_day,
                "last7": [cleared.get(today - dt.timedelta(days=n), 0) for n in range(6, -1, -1)]}

    def report(self, date):
        """The shift report's figures: orders cleared on `date`, those due that day still open, and the day's note."""
        start, end = day_bounds(date)
        done = self._select("items.done_at >= ? AND items.done_at < ?", (start, end), "items.done_at")
        left = self._select("items.done_at IS NULL AND items.due_at IS NOT NULL AND items.due_at < ?", (end,), "items.due_at, items.id")
        return {"date": date, "cleared": done, "open": left, "day": self._day(date)}

    # Routines (docs 15 section 8).

    def _routine(self, routine_id):
        row = self.db.execute("SELECT id, name, rule, times, minute, alert, position, created_at FROM routines WHERE id = ? AND archived = 0",
                              (routine_id,)).fetchone()
        if not row:
            raise ValueError("That routine does not exist.")
        return row

    def routine_add(self, p):
        name = check_name(p.get("name"), "routine")
        rule, times = p.get("rule"), routines.times_a_week(p.get("rule"))
        if times is None:
            check_rule(rule)
        minute = check_number(p.get("minute"), 0, 1439, "time")
        alert = check_flag(p.get("alert", False), "alert choice")
        if alert and minute is None:
            raise ValueError("An alert needs a time.")
        position = self.db.execute("SELECT COALESCE(MAX(position), -1) + 1 FROM routines").fetchone()[0]
        routine_id = self.db.execute("INSERT INTO routines (name, rule, times, minute, alert, position, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                                     (name, rule, times, minute, int(alert), position, self.now())).lastrowid
        self.db.commit()
        return routine_id

    def routine_update(self, p):
        row = self._routine(p.get("id"))
        name = check_name(p["name"], "routine") if "name" in p else row[1]
        minute = check_number(p["minute"], 0, 1439, "time") if "minute" in p else row[4]
        alert = check_flag(p["alert"], "alert choice") if "alert" in p else bool(row[5])
        if alert and minute is None:
            raise ValueError("An alert needs a time.")
        self.db.execute("UPDATE routines SET name = ?, minute = ?, alert = ? WHERE id = ?", (name, minute, int(alert), row[0]))
        self.db.commit()
        return row[0]

    def routine_delete(self, routine_id):
        self._routine(routine_id)
        self.db.execute("UPDATE routines SET archived = 1 WHERE id = ?", (routine_id,))
        self.db.commit()
        return routine_id

    def routine_check(self, routine_id, date, checked):
        """Checks a routine in (or takes the check back) for a day."""
        self._routine(routine_id)
        self._date(date)
        if checked:
            self.db.execute("INSERT OR IGNORE INTO routine_checks (routine_id, date, at) VALUES (?, ?, ?)", (routine_id, date, self.now()))
        else:
            self.db.execute("DELETE FROM routine_checks WHERE routine_id = ? AND date = ?", (routine_id, date))
        self.db.commit()
        return {"id": routine_id, "date": date, "checked": bool(checked)}

    def routine_list(self, date, days_off=(), first=0, weeks=26):
        """Every routine with what is due on `date`, its streaks and its heat map. A dated rule is due on the days it
        names; 'N times a week' is due all week until it has N checks. Days off and a stand-down pause streaks."""
        today = self._date(date)
        if not all(isinstance(day, int) and 0 <= day <= 6 for day in days_off) or not isinstance(first, int) or not 0 <= first <= 6:
            raise ValueError("Choose weekdays from Monday to Sunday.")
        stand = {self._date(row[0]) for row in self.db.execute("SELECT date FROM days WHERE stand_down = 1")}
        begin = shift.week_start(today, first)

        def skip(day):
            return day.weekday() in days_off or day in stand
        result = []
        for row in self.db.execute("SELECT id FROM routines WHERE archived = 0 ORDER BY position, id").fetchall():
            routine_id, name, rule, times, minute, alert, position, created = self._routine(row[0])
            checked = {self._date(day[0]) for day in self.db.execute("SELECT date FROM routine_checks WHERE routine_id = ?", (routine_id,))}
            start = dt.datetime.fromtimestamp((created or self.now()) / 1000).date()
            start = min([start] + sorted(checked)[:1])
            week = sum(1 for day in checked if begin <= day <= today)
            if times:
                current, best = routines.week_streak(today, start, checked, times, first)
                due, unit = week < times and not skip(today), "weeks"
            else:
                parsed = check_rule(rule)
                anchor = dt.datetime.fromtimestamp((created or self.now()) / 1000).date()
                current, best = routines.day_streak(today, start, checked, lambda day: on_rule(day, parsed, anchor), skip)
                due, unit = on_rule(today, parsed, anchor) and not skip(today), "days"
            result.append({"id": routine_id, "name": name, "rule": rule, "times": times, "minute": minute, "alert": bool(alert),
                           "dueToday": due or today in checked, "checkedToday": today in checked, "weekChecks": week,
                           "streak": current, "best": best, "unit": unit,
                           "history": sorted(day.isoformat() for day in checked if day >= today - dt.timedelta(days=weeks * 7))})
        return result

    def routine_alerts(self, date, now=None):
        """Routines with an alert whose time has come, not yet checked in or alerted today; each is given once."""
        today = self._date(date)
        moment = dt.datetime.fromtimestamp((now if now is not None else self.now()) / 1000)
        if moment.date() != today:
            return []
        given = []
        for row in self.db.execute("SELECT id FROM routines WHERE archived = 0 AND alert = 1 AND minute IS NOT NULL AND minute <= ?",
                                   (moment.hour * 60 + moment.minute,)).fetchall():
            routine_id, name, rule, times, minute, alert, position, created = self._routine(row[0])
            if self.db.execute("SELECT 1 FROM routine_checks WHERE routine_id = ? AND date = ?", (routine_id, date)).fetchone():
                continue
            if self.db.execute("SELECT 1 FROM routine_alerts WHERE routine_id = ? AND date = ?", (routine_id, date)).fetchone():
                continue
            if not times:
                anchor = dt.datetime.fromtimestamp((created or self.now()) / 1000).date()
                if not on_rule(today, check_rule(rule), anchor):
                    continue
            self.db.execute("INSERT INTO routine_alerts (routine_id, date) VALUES (?, ?)", (routine_id, date))
            given.append({"id": routine_id, "name": name})
        self.db.commit()
        return given

    def handle(self, method, p):
        """The day.* methods of the helper protocol."""
        if method == "day.list":
            return self.list(str(p.get("date", "")))
        if method == "day.add":
            return self.add(p)
        if method == "day.update":
            return self.update(p.get("id"), {key: value for key, value in p.items() if key not in ("id", "kind")})
        if method == "day.done":
            return self.done(p.get("id"))
        if method == "day.complete":
            return self.complete(p.get("id"), p.get("subOrders"))
        if method == "day.undone":
            return self.undone(p.get("id"))
        if method == "day.delete":
            return self.delete(p.get("id"))
        if method == "day.snooze":
            return self.snooze(p.get("id"), p.get("until"), p.get("alertId"))
        if method == "day.reorder":
            return self.reorder(p.get("ids"))
        if method == "day.days.get":
            return self.day_state(p.get("date"), {key: p[key] for key in ("target", "note", "standDown") if key in p})
        if method == "day.shift.state":
            return self.shift_state(p.get("date"), p.get("start", "05:00"), p.get("now"))
        if method == "day.shift.start":
            return self.shift_start(p.get("date"), p.get("target"))
        if method == "day.carry.list":
            return self.carry_list(p.get("date"))
        if method == "day.carry.apply":
            return self.carry_apply(p.get("date"), p.get("choices"))
        if method == "day.carry.auto":
            return self.carry_auto(p.get("date"))
        if method == "day.shift.reminder":
            return self.shift_reminder(p.get("date"), p.get("end", "18:00"), p.get("now"))
        if method == "day.signal.log":
            return self.signal_log(p.get("at"), p.get("app"), p.get("urgency"))
        if method == "day.quiet.log":
            return self.quiet_log(p.get("start"), p.get("end"), p.get("orderId"))
        if method == "day.momentum":
            return self.momentum(p.get("date"), p.get("daily", 5), p.get("weekly", 25), p.get("daysOff", []), p.get("weekStart", 0))
        if method == "day.report":
            return self.report(p.get("date"))
        if method == "day.routines.list":
            return self.routine_list(p.get("date"), p.get("daysOff", []), p.get("weekStart", 0))
        if method == "day.routines.add":
            return self.routine_add(p)
        if method == "day.routines.update":
            return self.routine_update(p)
        if method == "day.routines.delete":
            return self.routine_delete(p.get("id"))
        if method == "day.routines.check":
            return self.routine_check(p.get("id"), p.get("date"), check_flag(p.get("checked", True), "check"))
        if method == "day.routines.alerts":
            return self.routine_alerts(p.get("date"), p.get("now"))
        if method == "day.next":
            return self.next()
        if method == "day.fire":
            return self.fire()
        if method == "day.orders":
            return self.orders(p.get("since"))
        if method == "day.search":
            return self.search(p.get("text"))
        if method == "day.completions":
            return self.completions(p.get("start"), p.get("end"))
        if method in ("day.history.undo", "day.history.redo"):
            return self.undo(method.endswith("redo"))
        if method == "day.history.list":
            return self.history()
        if method == "day.export":
            return day_io.export(self, p.get("format"), p.get("path"))
        if method == "day.import":
            return day_io.import_file(self, p.get("source"), p.get("path"))
        if method == "day.restore":
            return day_io.restore(self, p.get("path"))
        if method == "day.backup":
            return day_io.backup(self, p.get("path"))
        if method.startswith(("day.sites.", "day.sections.")):
            return self.handle_sites(method, p)
        if method.startswith("day.tags."):
            return self.handle_tags(method, p)
        if method.startswith("day.filters."):
            return self.handle_filters(method, p)
        raise ValueError("Unknown day operation.")
