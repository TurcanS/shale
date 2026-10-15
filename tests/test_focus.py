"""Focus sessions as Activity records them, running services/Focus.qml's own functions in node."""
import json
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]

# Stand-ins for what the functions use from the shell; Activity's records are collected in `spans`.
PRELUDE = '''
let startedAt = 0, endsAt = 0, recordedUntil = 0, now = 0, digest = null;
const lastMinutes = 25;
let time = 1792058400000, undo = null, saved = {};
Date.now = () => time;
Object.defineProperty(globalThis, "active", {get: () => endsAt > 0});
const spans = [];
const ShellState = {setting: key => key === "activityTracking" ? "on" : saved[key], setSetting: (key, value) => saved[key] = value,
                    message: (text, kind, action) => { if (action) undo = action.run; }};
const Services = {notifications: []};
const Backend = {request: (method, params) => spans.push(params)};
const root = {resume: (...args) => resume(...args)};
function chime() {}
'''


def run(steps):
    source = (ROOT / "services/Focus.qml").read_text()
    functions = source[source.index("    function start(minutes)"):source.index("    property int timerSerial")]
    result = subprocess.run(["node", "-e", PRELUDE + functions + steps + "\nconsole.log(JSON.stringify({spans, saved}));"],
                            capture_output=True, text=True, timeout=20)
    if result.returncode:
        raise AssertionError(result.stderr)
    return json.loads(result.stdout)


@unittest.skipUnless(shutil.which("node"), "node is not installed")
class FocusRecordTests(unittest.TestCase):
    def minutes(self, spans):
        return sum(span["end"] - span["start"] for span in spans) / 60000

    def test_undo_records_each_minute_once(self):
        result = run("start(25); time += 10 * 60000; end(true); undo(); time += 15 * 60000; end(false);")
        self.assertEqual(self.minutes(result["spans"]), 25)
        first, second = result["spans"]
        self.assertLessEqual(first["end"], second["start"])

    def test_repeated_undo_and_a_short_first_part(self):
        # Ended after 30 s (too short to record), resumed, ended again and resumed again, then finished.
        result = run("start(25); time += 30000; end(true); undo(); time += 9.5 * 60000; end(true); undo();"
                     "time += 5 * 60000; end(true); undo(); time += 10 * 60000; end(false);")
        self.assertEqual(self.minutes(result["spans"]), 25)

    def test_a_resumed_session_saves_where_its_record_ends(self):
        result = run("start(25); time += 10 * 60000; end(true); undo();")
        session = result["saved"]["focusSession"]
        self.assertEqual(session["recorded"] - session["started"], 10 * 60000)
        self.assertEqual(run("start(25); time += 10 * 60000;")["saved"]["focusSession"].get("recorded"), None)


if __name__ == "__main__":
    unittest.main()
