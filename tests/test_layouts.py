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


@unittest.skipUnless(shutil.which("node"), "node is not installed")
class ControlLayoutTests(unittest.TestCase):
    def test_catalog_matches_the_helper(self):
        parts = run_js("controlItems.js", "{tiles, sections, footer}")
        self.assertEqual(tuple(item["id"] for item in parts["tiles"]), b.CONTROL_TILES)
        self.assertEqual(tuple(item["id"] for item in parts["sections"]), b.CONTROL_SECTIONS)
        self.assertEqual(tuple(item["id"] for item in parts["footer"]), b.CONTROL_FOOTER)

    def test_default_and_saved_layouts(self):
        default = run_js("controlItems.js", "layout({})")
        self.assertEqual([t["id"] for t in default["tiles"]], list(b.CONTROL_TILES))
        self.assertTrue(all(t["shown"] for t in default["tiles"] + default["footer"]))
        self.assertEqual(default["sections"], {"focus": True, "levels": True, "media": True})
        saved = {"tiles": ["dnd", "wifi"], "hiddenTiles": ["lid"], "sections": {"media": False}, "hiddenFooter": ["settings", "lock"]}
        layout = run_js("controlItems.js", f"layout({json.dumps(saved)})")
        self.assertEqual([t["id"] for t in layout["tiles"]], ["dnd", "wifi", "bluetooth", "awake", "grayscale", "lid"])
        self.assertEqual([t["id"] for t in layout["tiles"] if not t["shown"]], ["lid"])
        self.assertEqual([f["id"] for f in layout["footer"] if not f["shown"]], ["lock"])
        self.assertFalse(layout["sections"]["media"])

    def test_changes_save_as_the_helper_accepts(self):
        for code in ('changed({}, "tiles", "grayscale", -2)', 'changed({}, "tiles", "wifi", 0, false)', 'changed({}, "footer", "settings", 0, false)',
                     'changed({}, "footer", "session", -3)', 'section({}, "focus", false)'):
            with self.subTest(code=code):
                value = run_js("controlItems.js", code)
                b.check_setting("controlLayout", value)
        self.assertEqual(run_js("controlItems.js", 'changed({}, "tiles", "grayscale", -2)')["tiles"][:4], ["wifi", "bluetooth", "grayscale", "dnd"])
        self.assertEqual(run_js("controlItems.js", 'changed({}, "footer", "settings", 0, false)')["hiddenFooter"], [])
        self.assertEqual(run_js("controlItems.js", 'changed({}, "tiles", "wifi", 0, false)')["hiddenTiles"], ["wifi"])
