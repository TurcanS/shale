"""Apps started from the shell must go through ShellState.launch, which gives each its own systemd scope.

A process spawned straight from quickshell stays in shale.service's cgroup, so restarting the shell would kill it."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPAWNS = re.compile(r"Qt\.openUrlExternally\(|\.execute\(\)|execDetached\(")


class LaunchTests(unittest.TestCase):
    def test_only_shell_state_spawns_processes(self):
        offenders = []
        for path in sorted(ROOT.glob("*/*.qml")) + [ROOT / "shell.qml"]:
            if path.parts[-2] == "qml":
                continue
            for number, line in enumerate(path.read_text().splitlines(), 1):
                if SPAWNS.search(line):
                    offenders.append(f"{path.relative_to(ROOT)}:{number}")
        # launch() itself, and the session action that already runs as its own unit.
        self.assertEqual([o for o in offenders if not o.startswith("core/ShellState.qml:")], [])
        self.assertEqual(len(offenders), 2)

    def test_launch_uses_an_app_scope(self):
        source = (ROOT / "core/ShellState.qml").read_text()
        launch = source[source.index("function launch("):source.index("function openUrl(")]
        # The scope inherits the shell's environment, so the GPU driver choice made for the shell is dropped.
        for part in ('"--scope"', '"--slice=app.slice"', '"--unit=" + unit', '"systemd-cat"', 'environment: childEnvironment'):
            self.assertIn(part, launch)


if __name__ == "__main__":
    unittest.main()
