"""Keeps cliphist fed with clipboard changes on setups that don't already run a watcher."""
import os
from pathlib import Path
import shutil
import subprocess
import sys

KINDS = ("text", "image")


def watched_kinds(cmdline):
    """Clipboard kinds a `wl-paste --watch cliphist store` command line covers (empty if it isn't one)."""
    args = [arg.decode(errors="replace") for arg in cmdline.split(b"\0") if arg]
    if not args or Path(args[0]).name != "wl-paste" or "--watch" not in args or not any("cliphist" in a for a in args):
        return set()
    for flag in ("--type", "-t"):
        if flag in args[:-1]:
            kind = args[args.index(flag) + 1]
            return {"image"} if kind.startswith("image") else {"text"}
    return set(KINDS)  # without --type, wl-paste stores every kind


class ClipboardWatcher:
    def __init__(self, proc=Path("/proc"), which=shutil.which, spawn=subprocess.Popen):
        self.proc, self.which, self.spawn = proc, which, spawn
        self.children = {}
        self.prefix = None  # looked up the first time a watcher is started

    def external(self):
        """Kinds already covered by watchers this helper didn't start (for example from hyprland.lua)."""
        own = {child.pid for child in self.children.values()}
        uid, covered = os.getuid(), set()
        for entry in self.proc.glob("[0-9]*"):
            try:
                if int(entry.name) in own or entry.stat().st_uid != uid:
                    continue
                covered |= watched_kinds((entry / "cmdline").read_bytes())
            except (OSError, ValueError):
                continue
        return covered

    def ensure(self):
        if not (self.which("cliphist") and self.which("wl-paste")):
            return
        for kind, child in list(self.children.items()):
            if child.poll() is not None:
                del self.children[kind]
        missing = set(KINDS) - set(self.children) - self.external()
        if missing and self.prefix is None:
            # setpriv (util-linux) makes a watcher die with the helper, without running Python in the
            # forked child, which isn't safe while the helper has worker threads.
            self.prefix = ["setpriv", "--pdeathsig", "TERM", "--"] if self.which("setpriv") else []
            if not self.prefix:
                print("setpriv (util-linux) not found: clipboard watchers stay running if the helper crashes.",
                      file=sys.stderr)
        for kind in sorted(missing):
            self.children[kind] = self.spawn(self.prefix + ["wl-paste", "--type", kind, "--watch", "cliphist", "store"],
                                             stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def stop(self):
        for child in self.children.values():
            if child.poll() is None:
                child.terminate()
        self.children.clear()
