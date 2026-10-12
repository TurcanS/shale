#!/usr/bin/env python3
"""Exercise launcher reuse and calculator state without changing the real clipboard."""
import os
import subprocess
import tempfile
from harness import harness

with tempfile.TemporaryDirectory(prefix="shale-interactions-") as directory:
    # As `shale run` sets it on a hybrid laptop; launched apps must not inherit the shell's driver choice.
    env = dict(os.environ, SHALE_CHILD_UNSET="__EGL_VENDOR_LIBRARY_FILENAMES __GLX_VENDOR_LIBRARY_NAME", XDG_RUNTIME_DIR=directory, XDG_CONFIG_HOME=directory, XDG_STATE_HOME=directory, XDG_CACHE_HOME=directory,
               QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", DBUS_SESSION_BUS_ADDRESS="unix:path=" + directory + "/no-bus")
    env.pop("WAYLAND_DISPLAY", None)
    env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
    result = subprocess.run(["quickshell", "-p", str(harness("interaction-check.qml", directory)), "--no-color"], env=env, capture_output=True, text=True, timeout=12)
    log = result.stdout + result.stderr
    for line in log.splitlines():
        if "CHECK" in line or "scene:" in line or "caused by" in line:
            print(line)
    passed = result.returncode == 0 and "INTERACTION CHECK COMPLETE 0" in log and "CHECK FAIL" not in log and "scene:" not in log
    if not passed:
        print(log)
    raise SystemExit(0 if passed else 1)
