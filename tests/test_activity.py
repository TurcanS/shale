import datetime as dt
import os
from pathlib import Path
import sqlite3
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "helpers"))
from activity import ActivityStore, MigrationError, day_bounds, has_history, local_day, week_first


class Clock:
    def __init__(self, at):
        self.wall_value = at
        self.mono_value = 100.0

    def wall(self):
        return self.wall_value

    def mono(self):
        return self.mono_value

    def tick(self, seconds, wall_seconds=None):
        self.wall_value += seconds if wall_seconds is None else wall_seconds
        self.mono_value += seconds


V1_SCHEMA = """
    CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
    CREATE TABLE days (day TEXT PRIMARY KEY, active REAL NOT NULL DEFAULT 0, unlocked REAL NOT NULL DEFAULT 0);
    CREATE TABLE intervals (id INTEGER PRIMARY KEY, kind TEXT NOT NULL, start INTEGER NOT NULL, end INTEGER NOT NULL);
    CREATE TABLE windows (id INTEGER PRIMARY KEY, window_key TEXT NOT NULL, app TEXT NOT NULL,
        start INTEGER NOT NULL, end INTEGER, last_seen INTEGER NOT NULL, start_known INTEGER NOT NULL, end_reason TEXT NOT NULL DEFAULT 'open');
    CREATE TABLE focus (id INTEGER PRIMARY KEY, app TEXT NOT NULL, start INTEGER NOT NULL, end INTEGER NOT NULL);
    CREATE INDEX intervals_start ON intervals(start);
    CREATE INDEX focus_start ON focus(start);
"""


class ActivityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.clock = Clock(dt.datetime(2025, 6, 3, 10, 0).timestamp())
        self.path = Path(self.temp.name) / "history" / "activity.sqlite3"
        self.store = ActivityStore(self.path, self.clock.wall, self.clock.mono)

    def tearDown(self):
        self.store.db.close()
        self.temp.cleanup()

    def reopen(self):
        self.store.db.close()
        self.store = ActivityStore(self.path, self.clock.wall, self.clock.mono)

    def sample(self, unlocked=True, idle=False, windows=None, focused="", **extra):
        return {"unlocked": unlocked, "idle": idle,
                "windows": windows if windows is not None else [], "focused": focused, **extra}

    def hold(self, seconds, **sample):
        """Advance like the shell does: a snapshot at least every 30 seconds."""
        while seconds > 0:
            step = min(30, seconds)
            self.clock.tick(step)
            self.store.ingest(self.sample(**sample))
            seconds -= step

    def apps(self, day="2025-06-03"):
        return {entry["app"]: entry for entry in self.store.day(day)["apps"]}

    def test_time_excludes_idle_lock_and_pause(self):
        self.store.ingest(self.sample())
        self.clock.tick(30)
        self.store.ingest(self.sample(idle=True))
        self.clock.tick(20)
        self.store.ingest(self.sample(unlocked=False))
        self.clock.tick(10)
        self.store.ingest(self.sample(unlocked=True, idle=False))
        self.clock.tick(15)
        self.store.pause(True)
        self.clock.tick(20)
        self.store.ingest(self.sample())
        self.store.pause(False)
        self.store.ingest(self.sample())
        self.clock.tick(5)
        self.store.ingest(self.sample())
        day = self.store.day("2025-06-03")
        self.assertEqual(day["active"], 50)
        self.assertEqual(day["unlocked"], 70)
        self.assertEqual(sum(hour["active"] for hour in day["hours"]), 50)
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.path.parent.stat().st_mode & 0o777, 0o700)

    def test_idle_detection_delay_is_not_active_time(self):
        windows = [{"id": "a", "app": "editor"}]
        self.store.ingest(self.sample(windows=windows, focused="a", idleTimeout=120))
        for _ in range(10):
            self.clock.tick(30)
            self.store.ingest(self.sample(windows=windows, focused="a", idleTimeout=120))
        self.store.ingest(self.sample(windows=windows, focused="a", idle=True, idleTimeout=120))
        self.clock.tick(60)
        self.store.ingest(self.sample(windows=windows, focused="a", idle=True, idleTimeout=120))
        day = self.store.day("2025-06-03")
        self.assertEqual((day["active"], day["unlocked"]), (180, 360))
        self.assertEqual(self.apps()["editor"]["active"], 180)
        self.assertEqual([segment["state"] for segment in day["segments"]], ["active", "idle"])
        self.assertEqual(self.store.status()["state"], "idle")

    def test_watching_needs_an_inhibitor_or_fullscreen_media(self):
        video = [{"id": "v", "app": "zen"}]
        self.store.ingest(self.sample(windows=video, focused="v", idleTimeout=120))
        self.hold(150, windows=video, focused="v", idleTimeout=120)
        self.store.ingest(self.sample(windows=video, focused="v", idle=True, inhibited=True, idleTimeout=120))
        self.hold(100, windows=video, focused="v", idle=True, inhibited=True, idleTimeout=120)
        self.hold(50, windows=video, focused="v", idle=True, fullscreenMedia=True, idleTimeout=120)
        self.store.ingest(self.sample(windows=video, focused="v", idle=True, idleTimeout=120))
        self.hold(40, windows=video, focused="v", idle=True, idleTimeout=120)
        day = self.store.day("2025-06-03")
        self.assertEqual((day["active"], day["watching"], day["unlocked"]), (30, 270, 340))
        self.assertEqual((self.apps()["zen"]["active"], self.apps()["zen"]["watching"]), (30, 270))
        self.assertEqual([segment["state"] for segment in day["segments"]], ["active", "watching", "idle"])

    def test_focus_flicker_stays_with_the_app_before_it(self):
        windows = [{"id": "a", "app": "zen"}, {"id": "b", "app": "fuzzel"}, {"id": "c", "app": "kitty"}, {"id": "d", "app": "code"}]
        self.store.ingest(self.sample(windows=windows, focused="a"))
        self.clock.tick(10)
        self.store.ingest(self.sample(windows=windows, focused="b"))
        self.clock.tick(1)
        self.store.ingest(self.sample(windows=windows, focused="a"))
        self.clock.tick(20)
        self.store.ingest(self.sample(windows=windows, focused="c"))
        self.clock.tick(10)
        self.store.ingest(self.sample(windows=windows, focused="d"))
        self.clock.tick(30)
        self.store.ingest(self.sample(windows=windows, focused="d"))
        apps = self.apps()
        self.assertNotIn("fuzzel", apps)
        self.assertEqual({app: entry["active"] for app, entry in apps.items()}, {"zen": 31, "kitty": 10, "code": 30})
        self.assertEqual([segment["app"] for segment in self.store.day("2025-06-03")["segments"]], ["zen", "kitty", "code"])
        self.assertAlmostEqual(apps["zen"]["share"] + apps["kitty"]["share"] + apps["code"]["share"], 1)

    def test_windows_focus_and_restart_mark_uncertainty(self):
        self.store.ingest(self.sample(windows=[{"id": "a", "app": "firefox", "title": "SECRET"}], focused="a"))
        self.clock.tick(20)
        self.store.ingest(self.sample(windows=[{"id": "a", "app": "firefox"}, {"id": "b", "app": "terminal"}], focused="b"))
        self.clock.tick(10)
        self.store.ingest(self.sample(windows=[{"id": "b", "app": "terminal"}], focused="b"))
        self.clock.tick(10)
        self.store.ingest(self.sample(windows=[], focused=""))
        detail = self.store.day("2025-06-03")
        self.assertEqual([(w["app"], w["startKnown"], w["endReason"]) for w in detail["windows"]],
                         [("firefox", False, "closed"), ("terminal", True, "closed")])
        self.assertEqual({app: entry["active"] for app, entry in self.apps().items()}, {"firefox": 20, "terminal": 20})
        self.assertNotIn(b"SECRET", self.path.read_bytes())
        self.store.ingest(self.sample(windows=[{"id": "c", "app": "editor"}]))
        self.clock.tick(3600)
        self.reopen()
        self.assertEqual(self.store.day("2025-06-03")["windows"][-1]["endReason"], "gap")

    def test_restart_continues_open_windows(self):
        windows = [{"id": "a", "app": "kitty"}]
        self.store.ingest(self.sample(windows=windows, focused="a"))
        self.clock.tick(30)
        self.store.ingest(self.sample(windows=windows, focused="a"))
        self.reopen()
        self.clock.tick(20)
        self.store.ingest(self.sample(windows=windows, focused="a"))
        self.clock.tick(30)
        self.store.ingest(self.sample(windows=windows, focused="a"))
        detail = self.store.day("2025-06-03")
        self.assertEqual([(w["app"], w["startKnown"], w["endReason"], (w["end"] - w["start"]) // 1000) for w in detail["windows"]],
                         [("kitty", False, "open", 80)])

    def test_gap_caps_credit_and_clear_resets_history(self):
        self.store.ingest(self.sample())
        self.clock.tick(180)
        self.store.ingest(self.sample())
        self.assertEqual(self.store.day("2025-06-03")["active"], 60)
        self.clock.tick(30, wall_seconds=3600)
        self.store.ingest(self.sample())
        self.assertEqual(self.store.day("2025-06-03")["active"], 90)
        self.store.clear()
        self.assertIsNone(self.store.overview()["started"])
        self.assertEqual(self.store.overview()["days"], [])

    def test_local_midnight_and_dst_hours(self):
        # Re-read TZ only after patch.dict has restored it, so later tests see the real zone.
        self.addCleanup(time.tzset)
        with patch.dict(os.environ, {"TZ": "Europe/Chisinau"}):
            time.tzset()
            spring_start, spring_end = day_bounds("2025-03-30")
            fall_start, fall_end = day_bounds("2025-10-26")
            self.assertEqual((spring_end - spring_start) // 3600000, 23)
            self.assertEqual((fall_end - fall_start) // 3600000, 25)
            self.assertEqual(len(self.store.day("2025-03-30")["hours"]), 23)
            self.assertEqual(len(self.store.day("2025-10-26")["hours"]), 25)
            labels = [hour["label"] for hour in self.store.day("2025-10-26")["hours"]]
            self.assertEqual(len(set(labels)), 25)
            self.store.clear()
            self.clock.wall_value = day_bounds("2025-10-25")[1] / 1000 - 20
            windows = [{"id": "a", "app": "kitty"}]
            self.store.ingest(self.sample(windows=windows, focused="a"))
            self.clock.tick(40)
            self.store.ingest(self.sample(windows=windows, focused="a"))
            self.assertEqual(self.store.day("2025-10-25")["active"], 20)
            self.assertEqual(self.store.day("2025-10-26")["active"], 20)
            self.assertEqual(self.store.day("2025-10-26")["apps"][0]["app"], "kitty")

    def test_history_is_kept(self):
        day = local_day(self.clock.wall())
        self.store.ingest(self.sample(windows=[{"id": "a", "app": "editor"}], focused="a"))
        self.clock.tick(30)
        self.store.ingest(self.sample(windows=[]))
        self.clock.tick(400 * 86400)
        self.store.ingest(self.sample())
        self.assertEqual(self.store.day(day)["active"], 90)
        self.assertTrue(self.store.day(day)["detailAvailable"])
        self.assertEqual(self.store.day(day)["windows"][0]["app"], "editor")
        self.assertTrue(any(entry["date"] == day for entry in self.store.overview()["days"]))
        self.assertEqual(self.store.app("editor", local_day(self.clock.wall()))["total"], 30)

    def test_app_ranking_trends_and_insights(self):
        windows = [{"id": "a", "app": "zen"}, {"id": "b", "app": "kitty"}]
        for offset in range(3):
            self.store.ingest(self.sample(windows=windows, focused="a"))
            self.hold(30 * 60, windows=windows, focused="a")
            self.store.ingest(self.sample(windows=windows, focused="b"))
            self.hold(5 * 60 * (offset + 1), windows=windows, focused="b")
            self.store.ingest(self.sample(unlocked=False))
            self.clock.tick(86400 - 30 * 60 - 5 * 60 * (offset + 1))
        today = local_day(self.clock.wall())
        week = self.store.apps("week", "2025-06-05")
        self.assertEqual([entry["app"] for entry in week["apps"]], ["zen", "kitty"])
        self.assertEqual(week["apps"][0]["total"], 3 * 1800)
        day = self.store.apps("day", "2025-06-05")
        self.assertEqual((day["apps"][1]["total"], day["apps"][1]["previous"]), (900, 600))
        detail = self.store.app("kitty", "2025-06-05")
        self.assertEqual(detail["total"], 1800)
        self.assertEqual(detail["daysUsed"], 3)
        self.assertEqual(detail["firstDay"], "2025-06-03")
        self.assertEqual(sum(detail["hours"]), 1800)
        self.assertEqual(sum(day["total"] for day in detail["days"]), 1800)
        insights = self.store.overview()["insights"]
        self.assertEqual(today, "2025-06-06")
        self.assertEqual(insights["streak"], 3)
        self.assertEqual(insights["longestStreak"], 3)
        self.assertEqual(insights["busiestHour"], 10)
        self.assertEqual(insights["typicalStart"], 600)
        with self.assertRaises(ValueError):
            self.store.apps("year", "2025-06-05")

    def test_weeks_start_on_the_locale_first_day(self):
        # 2025-06-03 is a Tuesday; 0 is Sunday, as the shell's locale reports it.
        self.assertEqual([week_first("2025-06-03", first) for first in (0, 1, 6)], ["2025-06-01", "2025-06-02", "2025-05-31"])
        self.assertEqual(week_first("2025-06-01", 1), "2025-05-26")
        windows = [{"id": "a", "app": "zen"}]
        self.clock.wall_value = dt.datetime(2025, 6, 1, 10, 0).timestamp()  # Sunday
        self.store.ingest(self.sample(windows=windows, focused="a"))
        self.hold(600, windows=windows, focused="a")
        self.store.ingest(self.sample(unlocked=False))
        self.clock.wall_value = dt.datetime(2025, 6, 3, 10, 0).timestamp()
        self.store.ingest(self.sample(windows=windows, focused="a"))
        self.hold(300, windows=windows, focused="a")
        sunday, monday = self.store.overview(0), self.store.overview()
        self.assertEqual((sunday["insights"]["thisWeek"], monday["insights"]["thisWeek"]), (900, 300))
        self.assertEqual((sunday["topApps"][0]["total"], monday["topApps"][0]["total"]), (900, 300))
        self.assertEqual(self.store.week("2025-06-03", 0)["start"], "2025-06-01")
        self.assertEqual([day["date"] for day in self.store.week("2025-06-03")["days"]][::6], ["2025-06-02", "2025-06-08"])
        period = self.store.apps("week", "2025-06-03", 0)
        self.assertEqual((period["start"], period["end"], period["total"]), ("2025-06-01", "2025-06-07", 900))
        for bad in (7, -1, "0", True, None):
            with self.subTest(first=bad), self.assertRaises(ValueError):
                self.store.week("2025-06-03", bad)

    def test_history_is_detected_without_changing_the_database(self):
        self.assertFalse(has_history(self.path.with_name("missing.sqlite3")))
        self.assertFalse(has_history(self.path))
        self.store.ingest(self.sample())
        self.clock.tick(30)
        self.store.ingest(self.sample())
        before = self.path.read_bytes()
        self.assertTrue(has_history(self.path))
        self.assertEqual(self.path.read_bytes(), before)
        self.assertFalse(has_history(self.path.parent))
        broken = self.path.with_name("broken.sqlite3")
        broken.write_text("not a database")
        self.assertFalse(has_history(broken))


class MigrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.clock = Clock(dt.datetime(2025, 6, 4, 12, 0).timestamp())
        self.path = Path(self.temp.name) / "activity.sqlite3"
        self.base = day_bounds("2025-06-03")[0]

    def tearDown(self):
        self.temp.cleanup()

    def at(self, minutes):
        return self.base + int(minutes * 60000)

    def write_v1(self, active_total=None):
        db = sqlite3.connect(self.path)
        db.executescript(V1_SCHEMA)
        db.execute("INSERT INTO meta VALUES('started', ?)", (str(self.at(-60 * 24 * 200)),))
        # 10:00–11:00 unlocked; active 10:00–10:40; zen, a 1-second fuzzel flick, zen, kitty.
        db.execute("INSERT INTO intervals(kind,start,end) VALUES('unlocked',?,?)", (self.at(600), self.at(660)))
        db.execute("INSERT INTO intervals(kind,start,end) VALUES('active',?,?)", (self.at(600), self.at(640)))
        focus = [("zen", self.at(600), self.at(610)), ("fuzzel", self.at(610), self.at(610) + 1000),
                 ("zen", self.at(610) + 1000, self.at(620)), ("kitty", self.at(620), self.at(640))]
        db.executemany("INSERT INTO focus(app,start,end) VALUES(?,?,?)", focus)
        db.execute("INSERT INTO days VALUES('2025-06-03', ?, 3600)", (2400 if active_total is None else active_total,))
        db.execute("INSERT INTO days VALUES('2024-12-01', 7200, 9000)")
        windows = [("0xa", "zen", self.at(590), self.at(605), self.at(605), 0, "gap"),
                   ("0xa", "zen", self.at(606), None, self.at(650), 0, "open"),
                   ("0xb", "kitty", self.at(615), self.at(640), self.at(640), 1, "closed")]
        db.executemany("INSERT INTO windows(window_key,app,start,end,last_seen,start_known,end_reason) VALUES(?,?,?,?,?,?,?)", windows)
        db.commit()
        db.close()

    def test_v1_history_is_converted_and_backed_up(self):
        self.write_v1()
        store = ActivityStore(self.path, self.clock.wall, self.clock.mono)
        try:
            day = store.day("2025-06-03")
            self.assertEqual((day["active"], day["unlocked"]), (2400, 3600))
            self.assertEqual([(s["state"], s["app"]) for s in day["segments"]], [("active", "zen"), ("active", "kitty"), ("idle", None)])
            self.assertEqual({entry["app"]: entry["active"] for entry in day["apps"]}, {"zen": 1200, "kitty": 1200})
            self.assertEqual([(w["app"], w["endReason"]) for w in day["windows"]], [("zen", "gap"), ("kitty", "closed")])
            legacy = store.day("2024-12-01")
            self.assertEqual((legacy["active"], legacy["unlocked"], legacy["detailAvailable"]), (7200, 9000, False))
            self.assertIn("2024-12-01", [entry["date"] for entry in store.overview()["days"]])
            tables = {row[0] for row in store.db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
            self.assertFalse(tables & {"intervals", "focus", "days"})
        finally:
            store.db.close()
        backup = self.path.with_name("activity.sqlite3.v1-backup")
        self.assertEqual(backup.stat().st_mode & 0o777, 0o600)
        with sqlite3.connect(backup) as db:
            self.assertEqual(db.execute("SELECT COUNT(*) FROM focus").fetchone()[0], 4)
        reopened = ActivityStore(self.path, self.clock.wall, self.clock.mono)
        self.assertEqual(reopened.day("2025-06-03")["active"], 2400)
        reopened.db.close()

    def test_v1_history_counts_as_history(self):
        self.write_v1()
        self.assertTrue(has_history(self.path))

    def test_mismatched_totals_leave_v1_untouched(self):
        self.write_v1(active_total=9999)
        with self.assertRaises(MigrationError):
            ActivityStore(self.path, self.clock.wall, self.clock.mono)
        with sqlite3.connect(self.path) as db:
            tables = {row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
            self.assertTrue({"intervals", "focus", "days"} <= tables)
            self.assertNotIn("segments", tables)
            self.assertEqual(db.execute("SELECT COUNT(*) FROM windows").fetchone()[0], 3)


if __name__ == "__main__":
    unittest.main()
