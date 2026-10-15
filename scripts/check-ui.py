#!/usr/bin/env python3
"""Render every panel using Qt's software backend and reject QML runtime errors, or open one panel by hand."""
import os
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
from harness import harness
from install import SHORTCUTS, shale_lua

PANELS = ["launcher", "clipboard", "control", "notifications", "calendar", "overview", "capture", "settings", "power", "wallpaper", "activity", "system"]
SCENARIOS = [(panel, "") for panel in PANELS] + [("control", detail) for detail in ["wifi", "bluetooth", "audio", "power", "media", "tray", "custom"]]
# Machines without a backlight, Wi-Fi, lid or capture tools.
SCENARIOS += [("control", "wifi-vpn"), ("control", "bare"), ("control", "wifi-bare"), ("control", "power-bare"), ("capture", "bare")]
SCENARIOS += [("settings", category) for category in ["Motion", "Bar", "Notifications", "Audio", "Capture", "Activity", "Shortcuts", "Shortcuts-old", "Bar-custom", "Control center", "Control center-custom", "Diagnostics"]]
SCENARIOS += [("launcher", detail) for detail in ["emoji", "files", "web", "units", "run", "timer", "focus", "actions"]]
SCENARIOS += [("launcher", "calculator"), ("notifications", "populated"), ("capture", "recording")]
SCENARIOS += [("activity", detail) for detail in ["overview", "day", "week", "apps", "app", "optin", "off"]]
SCENARIOS += [("settings", detail) for detail in ["color-frost", "color-warm"]]
SCENARIOS += [("system", detail) for detail in ["memory", "disk", "network", "gpu", "gpu-asleep", "bare"]]
SCENARIOS += [("calendar", detail) for detail in ["weather-forecast", "weather-search"]]
SCENARIOS += [("lock", detail) for detail in ["", "error", "caps"]]
SCENARIOS += [("bar", detail) for detail in ["default", "custom", "narrow"]]
# Settings each preview keeps over the helper's.
PREVIEW_SETTINGS = {
    ("bar", "custom"): {"barLayout": {"left": ["clock", "workspaces"], "center": ["media", "launcher"], "hidden": ["windowTitle", "notifications"]},
                        "clockFormat": "date-time", "clockSeconds": True, "workspaceStyle": "dots", "workspaceSlots": 5, "barStyle": "edge",
                        "batteryPercent": "always"},
    ("settings", "Bar-custom"): {"barLayout": {"left": ["clock", "workspaces"], "center": ["media", "launcher"], "hidden": ["windowTitle", "notifications"]},
                                 "barStyle": "edge"},
    ("settings", "Control center-custom"): {"controlLayout": {"tiles": ["dnd", "wifi"], "hiddenTiles": ["grayscale"], "sections": {"media": False},
                                                              "hiddenFooter": ["lock"]}},
    ("control", "custom"): {"controlLayout": {"tiles": ["dnd", "awake", "wifi"], "hiddenTiles": ["grayscale", "lid"], "sections": {"media": False, "focus": False},
                                              "footer": ["settings", "capture"], "hiddenFooter": ["lock"]}},
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output-dir", type=Path, help="Keep screenshots for visual inspection")
parser.add_argument("--panels", nargs="+", help="Render only these panel names")
parser.add_argument("--open", nargs="?", const="launcher", metavar="PANEL", help="Open one panel in a window instead (SHALE_DETAIL and the other SHALE_* variables apply)")
parser.add_argument("--accent", default="", help="Preview a six-digit accent color")
parser.add_argument("--tone", default="", choices=("", "charcoal", "midnight", "warm"), help="Preview a surface tone")
parser.add_argument("--width", type=int, default=1280, help="Preview viewport width")
parser.add_argument("--height", type=int, default=850, help="Preview viewport height")
args = parser.parse_args()
if args.width < 360 or args.height < 480:
    parser.error("viewport must be at least 360x480")
if args.open:
    with tempfile.TemporaryDirectory(prefix="shale-preview-") as directory:
        env = dict(os.environ, SHALE_PREVIEW=args.open, SHALE_VIEWPORT_WIDTH=str(args.width), SHALE_VIEWPORT_HEIGHT=str(args.height))
        env.update({key: value for key, value in (("SHALE_ACCENT", args.accent), ("SHALE_TONE", args.tone)) if value})
        try:
            raise SystemExit(subprocess.run(["quickshell", "-p", str(harness("preview.qml", directory))], env=env).returncode)
        except KeyboardInterrupt:
            raise SystemExit(130)
if args.panels:
    SCENARIOS = [scenario for scenario in SCENARIOS if scenario[0] in args.panels]
if args.output_dir:
    args.output_dir.mkdir(parents=True, exist_ok=True)
failed = False
with tempfile.TemporaryDirectory(prefix="shale-ui-") as directory:
    preview = str(harness("preview.qml", directory))
    # A home with Shale's Hyprland fragment as this checkout installs it, and one with a fragment from before
    # shortcuts could change in Settings.
    for name, fragment in (("home", shale_lua(SHORTCUTS)), ("home-old", 'local shortcuts = {\n    ["SUPER + V"] = "clipboard",\n}\n')):
        (Path(directory) / name / ".config/hypr").mkdir(parents=True)
        (Path(directory) / name / ".config/hypr/shale.lua").write_text(fragment)
    for panel, detail in SCENARIOS:
        label = panel + ("-" + detail if detail else "")
        screenshot = (args.output_dir or Path(directory)) / (label + ".png")
        env = dict(os.environ, XDG_RUNTIME_DIR=directory, XDG_CONFIG_HOME=directory, XDG_STATE_HOME=directory, XDG_CACHE_HOME=directory,
                   QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", SHALE_PREVIEW=panel, SHALE_DETAIL=detail,
                   SHALE_SCREENSHOT=str(screenshot), SHALE_CATEGORY=("Appearance" if detail.startswith("color-") else detail.split("-")[0]) if panel == "settings" else "",
                   HOME=str(Path(directory) / ("home-old" if detail.endswith("-old") else "home")),
                   SHALE_ACCENT="#a5c8ef" if detail == "color-frost" else "#e0c283" if detail == "color-warm" else args.accent,
                   SHALE_TONE="midnight" if detail == "color-frost" else "warm" if detail == "color-warm" else args.tone,
                   SHALE_QUERY={"calculator": "12345 * 6789", "emoji": ":heart", "files": "/quickshell", "web": "?quickshell.org", "units": "10 km to mi",
                                "run": ">notify-send hi", "timer": "timer 10m tea", "focus": "focus 40", "actions": "restart"}.get(detail, "") if panel == "launcher" else "",
                   SHALE_POPULATED="1" if detail == "populated" else "",
                   SHALE_WEATHER=detail.removeprefix("weather-") if detail.startswith("weather-") else "",
                   SHALE_CAPTURE_KIND="recording" if detail == "recording" else "",
                   # The first-run question, tracking turned off, or (every other scenario) tracking on.
                   SHALE_ACTIVITY={"optin": "ask", "off": "off"}.get(detail, "on") if panel == "activity" else "")
        env["SHALE_SETTINGS"] = json.dumps(PREVIEW_SETTINGS.get((panel, detail), {}))
        env["SHALE_VIEWPORT_WIDTH"] = str(700 if (panel, detail) == ("bar", "narrow") else args.width)
        env["SHALE_VIEWPORT_HEIGHT"] = str(args.height)
        env.pop("WAYLAND_DISPLAY", None)
        env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
        env["DBUS_SESSION_BUS_ADDRESS"] = "unix:path=" + directory + "/no-session-bus"
        result = subprocess.run(["quickshell", "-p", preview, "--no-color"], env=env, capture_output=True, text=True, timeout=12)
        log = result.stdout + result.stderr
        errors = [line for line in log.splitlines() if "scene:" in line or "caused by" in line or "Failed to load configuration" in line]
        okay = result.returncode == 0 and not errors and Path(env["SHALE_SCREENSHOT"]).is_file()
        print(("PASS " if okay else "FAIL ") + label)
        if not okay:
            failed = True
            print("\n".join(errors) or log)
raise SystemExit(1 if failed else 0)
