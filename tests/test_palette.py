import json
from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "helpers"))
from backend import accent_luminance

# Quantized palettes as the QML ColorQuantizer would report them.
CASES = {
    "deep_blue": ["#0a1440", "#1a2fb0", "#050505"],
    "dark_red": ["#3a0505", "#7a0d0d"],
    "sunset": ["#ff7a18", "#6b2dc2", "#101010"],
    "greyscale": ["#303030", "#8a8a8a", "#d0d0d0"],
    "black": ["#000000", "#0b0b0b"],
    "empty": [],
}

HARNESS = """import QtQuick
import Quickshell
import "palette.js" as Palette
ShellRoot {
    // Quitting from Component.onCompleted is ignored before the configuration finishes loading.
    Timer { running: true; interval: 1; onTriggered: Qt.quit() }
    Component.onCompleted: {
        const cases = %s;
        const result = {};
        for (const name in cases)
            result[name] = Palette.accentFrom(cases[name].map(value => Qt.color(value)));
        console.log("PALETTE " + JSON.stringify(result));
    }
}
"""


@unittest.skipUnless(shutil.which("quickshell"), "quickshell is not installed")
class AccentFromWallpaperTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "shell.qml"
            shutil.copy(ROOT / "core/palette.js", directory)
            config.write_text(HARNESS % json.dumps(CASES))
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", XDG_RUNTIME_DIR=directory, XDG_STATE_HOME=directory, XDG_CACHE_HOME=directory)
            env.pop("WAYLAND_DISPLAY", None)
            result = subprocess.run(["quickshell", "-p", str(config), "--no-color"], env=env, capture_output=True, text=True, timeout=15)
        lines = [line for line in (result.stdout + result.stderr).splitlines() if "PALETTE " in line]
        if not lines:
            raise AssertionError(result.stdout + result.stderr)
        cls.accents = json.loads(lines[-1].split("PALETTE ", 1)[1])

    def test_accents_pass_the_backend_brightness_check(self):
        for name in ("deep_blue", "dark_red", "sunset", "greyscale"):
            with self.subTest(name=name):
                self.assertRegex(self.accents[name], r"^#[0-9a-f]{6}$")
                self.assertGreaterEqual(accent_luminance(self.accents[name]), 0.28)

    def test_accent_keeps_the_wallpaper_hue(self):
        red, green, blue = (int(self.accents["deep_blue"][i:i + 2], 16) for i in (1, 3, 5))
        self.assertTrue(blue > red and blue > green, self.accents["deep_blue"])
        red, green, blue = (int(self.accents["sunset"][i:i + 2], 16) for i in (1, 3, 5))
        self.assertTrue(red > green > blue, self.accents["sunset"])

    def test_greyscale_gives_a_neutral_accent_and_darkness_gives_none(self):
        self.assertEqual(len(set(self.accents["greyscale"][1:].upper()[i:i + 2] for i in (0, 2, 4))), 1)
        self.assertEqual(self.accents["black"], "")
        self.assertEqual(self.accents["empty"], "")


if __name__ == "__main__":
    unittest.main()
