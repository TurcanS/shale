#!/usr/bin/env python3
"""Verify actual rendered panels, or check the already installed shell with --installed."""
import argparse
import datetime
import json
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--installed", action="store_true")
args = parser.parse_args()
config = Path.home() / ".config/quickshell/shale" if args.installed else ROOT / "shell.qml"
started = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
failures = []

def call(target, method, *arguments):
    result = subprocess.run(["quickshell", "ipc", "-p", str(config), "call", target, method, *arguments], capture_output=True, text=True, timeout=5)
    if result.returncode:
        failures.append(method + ": " + result.stderr.strip())
    return result.stdout.strip()

with tempfile.TemporaryFile(mode="w+") as log:
    process = None if args.installed else subprocess.Popen(["quickshell", "-p", str(config), "--no-color"], stdout=log, stderr=log)
    original = ""
    try:
        if process:
            time.sleep(2)
        else:
            original = json.loads(call("shell", "status")).get("panel", "")
        if process and process.poll() is not None:
            failures.append("Shell exited during startup")
        else:
            monitors = json.loads(subprocess.check_output(["hyprctl", "monitors", "-j"], text=True))
            output = next((m["name"] for m in monitors if m.get("focused")), monitors[0]["name"])
            call("shell", "close")
            for panel in ["launcher", "control", "notifications", "calendar", "clipboard", "overview", "capture", "settings", "power", "wallpaper", "activity"]:
                call("shell", "toggle", panel)
                time.sleep(.4)
                actual = json.loads(call("surface-" + output, "status"))
                if not actual["visible"] or actual["panel"] != panel or actual["content"] != "panel-" + panel:
                    failures.append("Wrong rendered panel: " + panel + " / " + repr(actual))
            for page in ["wifi", "bluetooth", "audio", "power", "media", "tray"]:
                call("shell", "page", page)
                time.sleep(.6)
                bar_state = json.loads(call("bar-" + output, "status"))
                selected = [key for key, value in bar_state.items() if value]
                expected = [] if page == "bluetooth" else [page]
                if selected != expected:
                    failures.append("Wrong bar highlight for " + page + ": " + repr(selected))
            call("shell", "close")
            time.sleep(.3)
    except (ValueError, KeyError, subprocess.SubprocessError) as error:
        failures.append(str(error))
    finally:
        if process:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        elif original:
            call("shell", "toggle", original)
    if args.installed:
        output = subprocess.check_output(["journalctl", "--user", "-u", "shale.service", "--since", started, "--no-pager"], text=True)
    else:
        log.seek(0)
        output = log.read()
    for line in output.splitlines():
        if "scene:" in line or "caused by" in line or "Failed to load configuration" in line:
            failures.append(line)
    print(output)
    print("PASS rendered panel routing and control pages" if not failures else "FAIL\n" + "\n".join(failures))
    raise SystemExit(bool(failures))
