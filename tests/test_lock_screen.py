import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

# Drives features/LockScreen.qml with stand-in PAM services (pam_deny / pam_permit),
# so no real password or faillock counter is involved.
HARNESS = """import QtQuick
import Quickshell
import "core"
import "features"

ShellRoot {
    id: shell
    property int step: 0
    LockScreen {
        id: lockScreen
        pamDirectory: "%s"
    }
    Timer {
        interval: 200
        running: true
        repeat: true
        onTriggered: {
            if (lockScreen.busy || lockScreen.unlocking) return;
            if (shell.step === 0) {
                ShellState.lockShell();
                ShellState.action("unlocked");
                console.log("RESULT external-unlock " + ShellState.locked);
                lockScreen.pamConfig = "deny";
                lockScreen.password = "wrong";
                lockScreen.submit();
            } else if (shell.step === 1) {
                console.log("RESULT deny " + ShellState.locked + " " + lockScreen.failures + " [" + lockScreen.password + "] " + lockScreen.status);
                lockScreen.submit();
                console.log("RESULT empty " + lockScreen.busy);
                lockScreen.pamConfig = "permit";
                lockScreen.password = "right";
                lockScreen.submit();
            } else if (shell.step === 2) {
                console.log("RESULT permit " + ShellState.locked + " [" + ShellState.lockOwner + "]");
                ShellState.setSetting("lockScreen", "hyprlock");
                console.log("RESULT hyprlock-preferred " + ShellState.lockShell() + " " + ShellState.locked);
                Qt.quit();
            }
            shell.step++;
        }
    }
}
"""


@unittest.skipUnless(shutil.which("quickshell"), "quickshell is not installed")
class LockScreenTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            for name in ("core", "features", "services", "components", "assets", "helpers"):
                (base / name).symlink_to(ROOT / name)
            pam = base / "pam"
            pam.mkdir()
            (pam / "deny").write_text("auth required pam_deny.so\naccount required pam_permit.so\n")
            (pam / "permit").write_text("auth required pam_permit.so\naccount required pam_permit.so\n")
            (base / "shell.qml").write_text(HARNESS % pam)
            # Both buses point nowhere: the helper must not set the real session's logind LockedHint.
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", XDG_RUNTIME_DIR=directory, XDG_CONFIG_HOME=directory,
                       XDG_STATE_HOME=directory, XDG_CACHE_HOME=directory, DBUS_SESSION_BUS_ADDRESS="unix:path=" + directory + "/none",
                       DBUS_SYSTEM_BUS_ADDRESS="unix:path=" + directory + "/no-system-bus")
            env.pop("WAYLAND_DISPLAY", None)
            env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
            result = subprocess.run(["quickshell", "-p", str(base / "shell.qml"), "--no-color"], env=env, capture_output=True, text=True, timeout=20)
        cls.log = result.stdout + result.stderr
        cls.results = {line.split("RESULT ", 1)[1].split(" ", 1)[0]: line.split("RESULT ", 1)[1].split(" ", 1)[1]
                       for line in cls.log.splitlines() if "RESULT " in line}

    def test_ipc_cannot_unlock_the_shell_lock_screen(self):
        self.assertEqual(self.results.get("external-unlock"), "true", self.log)

    def test_wrong_password_keeps_the_session_locked(self):
        self.assertEqual(self.results.get("deny"), "true 1 [] Wrong password", self.log)
        self.assertEqual(self.results.get("empty"), "false", self.log)

    def test_accepted_password_unlocks(self):
        self.assertEqual(self.results.get("permit"), "false []", self.log)

    def test_hyprlock_preference_leaves_locking_to_hyprlock(self):
        self.assertEqual(self.results.get("hyprlock-preferred"), "false false", self.log)


if __name__ == "__main__":
    unittest.main()
