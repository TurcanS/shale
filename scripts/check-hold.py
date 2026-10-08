#!/usr/bin/env python3
"""Exercise hold controls with real Qt pointer/key events; never run session actions."""
import os
import subprocess
import tempfile
from harness import harness

with tempfile.TemporaryDirectory(prefix="shale-hold-") as directory:
    env = dict(os.environ, XDG_RUNTIME_DIR=directory, XDG_CONFIG_HOME=directory,
               XDG_STATE_HOME=directory, XDG_CACHE_HOME=directory,
               QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
               DBUS_SESSION_BUS_ADDRESS="unix:path=" + directory + "/no-bus")
    env.pop("WAYLAND_DISPLAY", None)
    env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
    result = subprocess.run(["quickshell", "-p", str(harness("hold-check.qml", directory)), "--no-color"],
                            env=env, capture_output=True, text=True, timeout=30)
    log = result.stdout + result.stderr
    passed = result.returncode == 0 and "HOLD CHECK COMPLETE 0" in log and "scene:" not in log
    print("\n".join(line for line in log.splitlines() if "HOLD" in line) if passed else log)
    raise SystemExit(0 if passed else 1)
