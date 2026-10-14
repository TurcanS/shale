"""Quickshell loads modules only from its config folder, so the QML harnesses in tests/qml run from a folder that
links back to the repository."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LINKED = ("assets", "components", "core", "features", "helpers", "scripts", "services")


def harness(name, directory):
    """Link tests/qml/`name` and the shell's directories into `directory`/shell; return the harness path."""
    base = Path(directory) / "shell"
    base.mkdir()
    for item in LINKED + ("tests/qml/" + name,):
        (base / Path(item).name).symlink_to(ROOT / item)
    return base / name
