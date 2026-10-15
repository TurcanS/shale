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

    def test_focus_and_timer_call_the_focus_target(self):
        shell = f"{self.home}/.config/quickshell/shale"
        for args, call in ((("focus",), "start 0"), (("focus", "50"), "start 50"), (("focus", "end"), "end"),
                           (("timer", "90"), "timer 90 "), (("timer", "10m", "Tea"), "timer 600 Tea"), (("timer", "2h"), "timer 7200 ")):
            with self.subTest(args=args):
                result, calls = self.run_shale(*args)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(calls[-1], f"quickshell ipc -p {shell} call focus {call}")

    def test_focus_and_timer_refuse_bad_lengths(self):
        for args in (("focus", "0"), ("focus", "241"), ("focus", "5; rm"), ("timer", ""), ("timer", "0"), ("timer", "10x"),
                     ("timer", "25h"), ("timer", "999999"), ("timer", "-5m")):
            with self.subTest(args=args):
                result, calls = self.run_shale(*args)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(calls, [])

    def test_restart_reloads_units_an_update_changed(self):
        result, calls = self.run_shale("restart")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, ["systemctl --user daemon-reload", "systemctl --user reset-failed shale.service",
                                 "systemctl --user restart shale.service"])

    def test_version_and_status(self):
        self.assertEqual(self.run_shale("--version")[0].stdout, "Shale unknown\n")
        shell = self.home / ".config/quickshell/shale"
        shell.mkdir(parents=True)
        (shell / "COMMIT").write_text("a97d3ee-modified\n")
        self.assertEqual(self.run_shale("--version")[0].stdout, "Shale a97d3ee-modified\n")
        self.assertEqual(self.run_shale("version")[0].stdout, "Shale a97d3ee-modified\n")
        result, calls = self.run_shale("status")
        self.assertEqual(json.loads(result.stdout), {"version": "a97d3ee-modified", "panel": "", "helperReady": True})
        self.assertEqual(calls[-1], f"quickshell ipc -p {shell} call shell status")
        # A shell that isn't running fails the way quickshell does.
        self.stub("quickshell", "echo 'No running instances' >&2; exit 1")
        result, _ = self.run_shale("status")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")


class RunTests(unittest.TestCase):
    """`shale run` starts the shell with Mesa's EGL alone only when Hyprland's GPU is a Mesa one."""
    stub = SessionTests.stub

    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        self.home, self.bin, self.log = root / "home", root / "bin", root / "log"
        self.bin.mkdir()
        self.sysfs, self.vendors, self.dev = root / "sys", root / "egl", root / "dev/dri"
        self.vendors.mkdir()
        for name in ("10_nvidia.json", "50_mesa.json"):
            (self.vendors / name).write_text("{}")
        self.dev.mkdir(parents=True)
        # card0 is the NVIDIA GPU, card1 the integrated Intel one that the firmware booted on.
        for card, driver, boot in (("card0", "nvidia", "0"), ("card1", "i915", "1")):
            pci = root / "devices" / card
            (pci / "drivers").mkdir(parents=True)
            (pci / "drivers" / driver).mkdir()
            (pci / "boot_vga").write_text(boot + "\n")
            (pci / "driver").symlink_to(pci / "drivers" / driver)
            (self.sysfs / "class/drm" / card).mkdir(parents=True)
            (self.sysfs / "class/drm" / card / "device").symlink_to(pci)
            (self.dev / card).write_text("")
        self.stub("quickshell", 'echo "${__EGL_VENDOR_LIBRARY_FILENAMES:-}|${__GLX_VENDOR_LIBRARY_NAME:-}|${SHALE_CHILD_UNSET:-}" >> "%s"' % self.log)

    def egl(self, **env):
        result = subprocess.run(["/bin/sh", str(SHALE), "run"], capture_output=True, text=True,
                                env={"HOME": str(self.home), "PATH": f"{self.bin}:/usr/bin:/bin", "SHALE_SYSFS": str(self.sysfs),
                                     "SHALE_EGL_VENDORS": str(self.vendors), **env})
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.log.read_text().splitlines()
        self.log.unlink()
        self.assertEqual(calls[0], f"quickshell --path {self.home}/.config/quickshell/shale --no-duplicate")
        return tuple(calls[1].split("|"))

    def test_mesa_alone_when_hyprland_renders_on_the_integrated_gpu(self):
        mesa = (f"{self.vendors}/50_mesa.json", "mesa", "__EGL_VENDOR_LIBRARY_FILENAMES __GLX_VENDOR_LIBRARY_NAME")
        self.assertEqual(self.egl(), mesa)
        self.assertEqual(self.egl(AQ_DRM_DEVICES=f"{self.dev}/card1:{self.dev}/card0"), mesa)
        # A GLX choice of the user's own stays, and launched apps keep it.
        self.assertEqual(self.egl(__GLX_VENDOR_LIBRARY_NAME="nvidia"), (f"{self.vendors}/50_mesa.json", "nvidia", "__EGL_VENDOR_LIBRARY_FILENAMES"))

    def test_left_alone_when_hyprland_renders_on_nvidia(self):
        self.assertEqual(self.egl(AQ_DRM_DEVICES=f"{self.dev}/card0:{self.dev}/card1"), ("", "", ""))
        (self.sysfs.parent / "devices/card0/boot_vga").write_text("1\n")
        (self.sysfs.parent / "devices/card1/boot_vga").write_text("0\n")
        self.assertEqual(self.egl(), ("", "", ""))

    def test_left_alone_without_nvidia_or_with_a_user_choice(self):
        self.assertEqual(self.egl(__EGL_VENDOR_LIBRARY_FILENAMES="/custom.json"), ("/custom.json", "", ""))
        self.assertEqual(self.egl(__EGL_VENDOR_LIBRARY_DIRS="/custom"), ("", "", ""))
        (self.vendors / "10_nvidia.json").unlink()
        self.assertEqual(self.egl(), ("", "", ""))
        self.assertEqual(self.egl(AQ_DRM_DEVICES="/missing/card9"), ("", "", ""))


if __name__ == "__main__":
    unittest.main()
