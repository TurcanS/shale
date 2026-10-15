"""The bar and control center catalogs the shell arranges against what the helper accepts, and how saved layouts
are merged with the defaults (run in node when it is installed)."""
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "helpers"))
spec = importlib.util.spec_from_file_location("backend", ROOT / "helpers/backend.py")
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)


def run_js(library, code):
    """Evaluates `code` after the QML JavaScript library `library` (its .pragma line dropped); returns its JSON output."""
    source = (ROOT / "core" / library).read_text().replace(".pragma library", "")
    result = subprocess.run(["node", "-e", source + "\nconsole.log(JSON.stringify(" + code + "));"], capture_output=True, text=True, timeout=20)
    if result.returncode:
        raise AssertionError(result.stderr)
    return json.loads(result.stdout)


@unittest.skipUnless(shutil.which("node"), "node is not installed")
class BarLayoutTests(unittest.TestCase):
    def test_catalog_matches_the_helper(self):
        items = run_js("barItems.js", "items")
        self.assertEqual(tuple(item["id"] for item in items), b.BAR_ITEMS)
        self.assertEqual(tuple(item["id"] for item in items if item.get("required")), b.BAR_REQUIRED)

    def test_default_layout(self):
        layout = run_js("barItems.js", "layout({})")
        self.assertEqual(layout["left"], ["launcher", "workspaces", "windowTitle"])
        self.assertEqual(layout["center"], ["clock"])
        self.assertEqual(layout["right"][0], "media")
        self.assertEqual(layout["right"][-1], "control")
        self.assertEqual(layout["hidden"], [])

    def test_saved_layouts_are_merged(self):
        saved = {"left": ["clock", "bogus", "clock"], "right": ["control", "audio"], "hidden": ["recording", "wifi"]}
        layout = run_js("barItems.js", f"layout({json.dumps(saved)})")
        self.assertEqual(layout["left"], ["launcher", "workspaces", "windowTitle", "clock"])
        self.assertEqual(layout["hidden"], ["wifi"])
        # A required item can't hide; unmentioned items go after the ones they follow by default.
        self.assertIn("recording", layout["right"])
        self.assertEqual(layout["right"][:2], ["media", "tray"])
        self.assertEqual(sorted(sum(layout.values(), [])), sorted(b.BAR_ITEMS))
        b.check_setting("barLayout", layout)

    def test_moving_items(self):
        moved = run_js("barItems.js", 'moved({}, "clock", "left", 0)')
        self.assertEqual((moved["left"][-1], moved["center"]), ("clock", []))
        moved = run_js("barItems.js", 'moved({}, "workspaces", "", -1)')
        self.assertEqual(moved["left"][:2], ["workspaces", "launcher"])
        self.assertEqual(run_js("barItems.js", 'moved({}, "launcher", "", -1)')["left"][0], "launcher")
        b.check_setting("barLayout", run_js("barItems.js", 'moved({}, "notifications", "hidden", 0)'))

