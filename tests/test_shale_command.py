import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SHALE = Path(__file__).resolve().parents[1] / "scripts/shale"


class ShaleCommandTests(unittest.TestCase):
    def run_shale(self, *args):
        return subprocess.run(["sh", str(SHALE), *args], capture_output=True, text=True)

    def test_unknown_commands_print_the_full_usage(self):
        result = self.run_shale("bogus")
        self.assertEqual(result.returncode, 2)
        for command in ("page PAGE", "color", "stop-recording", "status", "screenshot"):
            self.assertIn(command, result.stderr)

    def test_page_only_accepts_control_center_pages(self):
        for page in ("", "settings", "wifi; rm"):
            with self.subTest(page=page):
                result = self.run_shale("page", page)
                self.assertEqual(result.returncode, 2)
                self.assertIn("wifi|bluetooth|audio|power|media|tray", result.stderr)

    def test_screenshot_only_accepts_the_modes_the_shell_handles(self):
        for mode in ("window", "regionx", "output; rm"):
            with self.subTest(mode=mode):
                result = self.run_shale("screenshot", mode)
                self.assertEqual(result.returncode, 2)
                self.assertIn("shale screenshot [region|output]", result.stderr)



class SessionTests(unittest.TestCase):
    """Runs the command with stand-ins for every program it calls, so no real service is touched."""

    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.home, self.bin = Path(temp.name) / "home", Path(temp.name) / "bin"
        self.bin.mkdir()
        self.log = Path(temp.name) / "log"
        # systemctl answers "no" to cat/is-active/is-enabled; everything else succeeds. Each call is logged.
        self.stub("systemctl", 'case "$2" in cat|is-active|is-enabled) exit 1 ;; esac')
        self.stub("dbus-update-activation-environment")
        self.stub("quickshell", 'printf \'{"panel":"","helperReady":true}\\n\'')

    def stub(self, name, body=""):
        path = self.bin / name
        path.write_text(f'#!/bin/sh\necho "{name} $*" >> "{self.log}"\n{body}\n')
        path.chmod(0o755)

    def run_shale(self, *args):
        result = subprocess.run(["/bin/sh", str(SHALE), *args], capture_output=True, text=True,
                                env={"HOME": str(self.home), "PATH": str(self.bin)})
        calls = self.log.read_text().splitlines() if self.log.exists() else []
        return result, calls

    def test_start_clears_a_failed_start_limit_first(self):
        result, calls = self.run_shale("start")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls[-2:], ["systemctl --user reset-failed shale.service", "systemctl --user start shale.service"])

    def test_restart_reloads_units_an_update_changed(self):
        result, calls = self.run_shale("restart")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, ["systemctl --user daemon-reload", "systemctl --user reset-failed shale.service",
                                 "systemctl --user restart shale.service"])

    def test_version_and_status(self):
        self.assertEqual(self.run_shale("--version")[0].stdout, "Shale unknown\n")
        shell = self.home / ".config/quickshell/shale"
        shell.mkdir(parents=True)
        (shell / "VERSION").write_text("1.2.3\n")
        self.assertEqual(self.run_shale("--version")[0].stdout, "Shale 1.2.3\n")
        self.assertEqual(self.run_shale("version")[0].stdout, "Shale 1.2.3\n")
        result, calls = self.run_shale("status")
        self.assertEqual(json.loads(result.stdout), {"version": "1.2.3", "panel": "", "helperReady": True})
        self.assertEqual(calls[-1], f"quickshell ipc -p {shell} call shell status")
        # A shell that isn't running fails the way quickshell does.
        self.stub("quickshell", "echo 'No running instances' >&2; exit 1")
        result, _ = self.run_shale("status")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
