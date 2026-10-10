import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "helpers"))
import clipboard_watch as cw


class Child:
    def __init__(self, pid):
        self.pid, self.alive = pid, True

    def poll(self):
        return None if self.alive else 0

    def terminate(self):
        self.alive = False


class ClipboardWatchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.proc = Path(self.temp.name)
        self.spawned = []

    def process(self, pid, *args):
        (self.proc / str(pid)).mkdir()
        (self.proc / str(pid) / "cmdline").write_bytes(b"\0".join(a.encode() for a in args) + b"\0")

    def watcher(self, tools=True, which=None):
        def spawn(command, **options):
            self.spawned.append(command)
            return Child(1000 + len(self.spawned))
        return cw.ClipboardWatcher(proc=self.proc, which=which or (lambda name: tools), spawn=spawn)

    def test_command_lines(self):
        self.assertEqual(cw.watched_kinds(b"wl-paste\0--type\0text\0--watch\0cliphist\0store\0"), {"text"})
        self.assertEqual(cw.watched_kinds(b"/usr/bin/wl-paste\0-t\0image/png\0--watch\0cliphist\0store\0"), {"image"})
        self.assertEqual(cw.watched_kinds(b"wl-paste\0--watch\0cliphist\0store\0"), {"text", "image"})
        self.assertEqual(cw.watched_kinds(b"wl-paste\0--watch\0clipman\0store\0"), set())
        self.assertEqual(cw.watched_kinds(b"cliphist\0list\0"), set())

    def test_starts_both_watchers_on_a_fresh_session(self):
        self.watcher().ensure()
        self.assertEqual(sorted(c[c.index("--type") + 1] for c in self.spawned), ["image", "text"])
        self.assertEqual(self.spawned[0][:4], ["setpriv", "--pdeathsig", "TERM", "--"])

    def test_without_setpriv_it_says_so_once_and_still_starts_watchers(self):
        looked_up = []

        def which(name):
            looked_up.append(name)
            return name != "setpriv"
        watcher = self.watcher(which=which)
        with patch("sys.stderr") as stderr:
            watcher.ensure()
            watcher.children["text"].alive = False
            watcher.ensure()
        self.assertEqual([c[0] for c in self.spawned], ["wl-paste"] * 3)
        self.assertEqual(looked_up.count("setpriv"), 1)
        self.assertIn("setpriv", "".join(call.args[0] for call in stderr.write.call_args_list))

    def test_leaves_an_existing_watcher_alone(self):
        self.process(4242, "wl-paste", "--type", "text", "--watch", "cliphist", "store")
        self.watcher().ensure()
        self.assertEqual([c[c.index("--type") + 1] for c in self.spawned], ["image"])

    def test_nothing_without_cliphist(self):
        self.watcher(tools=False).ensure()
        self.assertEqual(self.spawned, [])

    def test_restarts_a_crashed_watcher_and_stops_its_own(self):
        watcher = self.watcher()
        watcher.ensure()
        watcher.ensure()
        self.assertEqual(len(self.spawned), 2)  # its own running watchers don't count as external
        watcher.children["text"].alive = False
        watcher.ensure()
        self.assertEqual(len(self.spawned), 3)
        children = list(watcher.children.values())
        watcher.stop()
        self.assertTrue(all(not child.alive for child in children))


if __name__ == "__main__":
    unittest.main()
