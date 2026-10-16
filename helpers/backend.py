#!/usr/bin/env python3
"""Shale JSON-lines backend. Credentials and clipboard data never enter logs."""
import ast
import asyncio
import datetime
import importlib.util
import json
import math
import operator
import os
from pathlib import Path
import re
import select
import shutil
import signal
import sqlite3
import subprocess
import sys
import tempfile
import time
import traceback
from urllib.parse import unquote, urlsplit
import wallpaper
import wallhaven
import wallpaperscom
import activity
import art
import sysmon
from runtime import runtime_base
import clipboard_watch
import equalizer
import weather
import units
import shortcuts

def user_dir(name, fallback, home=None):
    """An XDG user directory such as PICTURES from user-dirs.dirs (localized, e.g. ~/Bilder), as ~/path."""
    home = home or Path.home()
    config = Path(os.environ.get("XDG_CONFIG_HOME") or home / ".config") / "user-dirs.dirs"
    try:
        lines = config.read_text().splitlines()
    except OSError:
        return fallback
    for line in lines:
        match = re.fullmatch(rf'XDG_{name}_DIR="(.*)"', line.strip())
        if not match:
            continue
        path = Path(match[1].replace("$HOME", str(home)))
        if not path.is_absolute() or path == home:
            return fallback  # xdg-user-dirs points a disabled directory at $HOME itself
        return "~/" + str(path.relative_to(home)) if path.is_relative_to(home) else str(path)
    return fallback

DEFAULTS = {"version": 1, "reducedMotion": False, "clock24h": True,
            "dnd": False, "amplification": False, "persistNotifications": False,
            "fontSize": 14, "batterySaving": False, "saverRefresh": True, "windowPreviews": True,
            "hideFullscreen": True, "hiddenOutputs": [], "pinnedApps": [], "appUsage": {}, "captureDelay": 0,
            "accentColor": "#9ad6c6", "surfaceTone": "charcoal", "accentFromWallpaper": False, "accentManual": "#9ad6c6",
            "eqEnabled": False, "eqPreset": "flat", "eqBands": [0] * len(equalizer.BANDS), "visualizer": True, "barMedia": True, "trackChangeCard": True, "mediaRemaining": False,
            "weatherLocation": {}, "weatherUnits": "metric", "emojiUsage": {}, "searchEngine": "duckduckgo", "lockScreen": "builtin", "lockStyle": "particles",
            "recordAudio": "none", "activityTracking": "ask", "systemWindow": 60,
            "focusMinutes": 25, "focusSession": {}, "timers": [], "runHistory": [],
            "barLayout": {}, "controlLayout": {}, "clockFormat": "day-time", "clockSeconds": False, "workspaceStyle": "numbers",
            "workspaceSlots": 0, "trayIcons": -1, "batteryPercent": "auto", "barStyle": "floating", "weekStart": "locale", "terminal": "auto", "shortcuts": {},
            "screenshotDirectory": user_dir("PICTURES", "~/Pictures") + "/Screenshots",
            "recordingDirectory": user_dir("VIDEOS", "~/Videos") + "/Recordings",
            "wallpaperDirectory": user_dir("PICTURES", "~/Pictures") + "/Wallpapers"}
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "shale/config.json"
RUNTIME = runtime_base() / "shale"
STATE = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "shale"
CACHE = Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "shale"
# Where the installer puts shale.lua, and the command its shortcuts run.
HYPR = Path.home() / ".config/hypr"
SHALE_COMMAND = str(Path.home() / ".local/bin/shale")

BUILTIN_PANEL = re.compile(r"(eDP|LVDS|DSI)-[A-Za-z0-9-]+")
SEARCH_ENGINES = ("duckduckgo", "google", "brave")
# wf-recorder records one PulseAudio source. Given none it takes the default source, the microphone,
# so system audio names the default output's monitor.
RECORD_AUDIO = {"none": None, "system": "@DEFAULT_MONITOR@", "microphone": "@DEFAULT_SOURCE@"}
# "ask" until the user chooses in the Activity panel; nothing is recorded until "on".
# Bar items and control center parts, as core/barItems.js and core/controlItems.js name them. A layout lists
# only what the user arranged; the shell puts anything it doesn't mention in its default place.
BAR_ITEMS = ("launcher", "workspaces", "windowTitle", "clock", "media", "tray", "recording", "privacy", "focus", "timer",
             "stayAwake", "keyboard", "vpn", "wifi", "audio", "battery", "notifications", "control")
# Never hidden: what is recording or listening stays visible, and the control center leads back to Settings.
BAR_REQUIRED = ("recording", "privacy", "control")
CONTROL_TILES = ("wifi", "bluetooth", "dnd", "awake", "grayscale", "lid")
CONTROL_SECTIONS = ("focus", "levels", "media")
CONTROL_FOOTER = ("capture", "settings", "lock", "session")
# Personal history and state, and this computer's folders; a settings export leaves them out and an import
# ignores them, so a file from elsewhere can't redirect where screenshots, recordings or downloads are saved.
PRIVATE_KEYS = ("appUsage", "emojiUsage", "runHistory", "pinnedApps", "focusSession", "timers", "weatherLocation",
                "screenshotDirectory", "recordingDirectory", "wallpaperDirectory")
ACTIVITY_TRACKING = ("ask", "on", "off")

def keyboard_state(devices):
    """The layouts of the main keyboard from `hyprctl devices -j`: {layouts: [{code, variant}], index, name}."""
    keyboards = [k for k in devices.get("keyboards", []) if isinstance(k, dict)] if isinstance(devices, dict) else []
    keyboard = next((k for k in keyboards if k.get("main")), keyboards[0] if keyboards else None)
    if keyboard is None:
        return {"layouts": [], "index": 0, "name": ""}
    codes = [code.strip() for code in str(keyboard.get("layout", "")).split(",")]
    variants = str(keyboard.get("variant", "")).split(",")
    layouts = [{"code": code, "variant": variants[i].strip() if i < len(variants) else ""} for i, code in enumerate(codes) if code]
    index = keyboard.get("active_layout_index", 0)
    return {"layouts": layouts, "index": index if type(index) is int and 0 <= index < len(layouts) else 0,
            "name": str(keyboard.get("active_keymap", ""))}

def file_search_args(query, home):
    """fd arguments for a launcher file search: every word must appear in the name, in order, ignoring case."""
    words = query.split() if isinstance(query, str) else []
    if not words or len(query) > 200:
        raise BackendError("invalid", "Type part of a file name.")
    pattern = ".*".join(re.escape(word) for word in words)
    # A typed path ("Documents/notes") matches against the whole path; fd rejects "/" in name patterns.
    scope = ["--full-path"] if "/" in query else []
    # Plenty of candidates: fd returns them in arbitrary order and file_results ranks before trimming.
    return ["fd", "--ignore-case", "--absolute-path", *scope, "--max-results", "2000", "--exclude", ".git", "--", pattern, str(home)]

def file_results(output, query, home, limit=40):
    """Rank fd output: exact and prefix name matches first, then shallower paths."""
    term = " ".join(query.split()).lower().rstrip("/").rsplit("/", 1)[-1]
    results = []
    for line in output.decode(errors="replace").splitlines():
        path = line.rstrip("/")
        if not path:
            continue
        name = os.path.basename(path)
        folder = os.path.dirname(path)
        shown = "~" + folder[len(str(home)):] if folder == str(home) or folder.startswith(str(home) + "/") else folder
        results.append({"path": path, "name": name, "folder": shown, "directory": line.endswith("/") or os.path.isdir(path),
                        "rank": (name.lower() != term, not name.lower().startswith(term), path.count("/"), len(path))})
    results.sort(key=lambda item: item["rank"])
    return [{key: value for key, value in item.items() if key != "rank"} for item in results[:limit]]

def accent_luminance(value):
    if type(value) is not str or not re.fullmatch(r"#[0-9a-fA-F]{6}", value):
        return None
    channels = [int(value[index:index + 2], 16) / 255 for index in (1, 3, 5)]
    linear = [channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4 for channel in channels]
    return sum(weight * channel for weight, channel in zip((0.2126, 0.7152, 0.0722), linear))

# Room for album art sent inline as a data: URL (media.art caps the decoded image at 5 MB).
REQUEST_LIMIT = 8 * 1024 * 1024

async def read_request(reader, limit=REQUEST_LIMIT):
    """The next request line, b"" at the end of input, or (None, id) for a line over the limit.

    The oversized line is read to its end and dropped, so the next request starts cleanly; its id
    (the shell writes it first) lets the caller answer that request instead of leaving it waiting."""
    size, parts = 0, []
    while True:
        try:
            chunk, end = await reader.readuntil(b"\n"), True
        except asyncio.IncompleteReadError as error:
            chunk, end = error.partial, True
            if not chunk and not size:
                return b""
        except asyncio.LimitOverrunError as error:
            chunk, end = await reader.read(max(1, error.consumed)), False
        if size <= limit:
            parts.append(chunk)
        size += len(chunk)
        if end:
            if size <= limit + 1:
                return b"".join(parts)
            match = re.match(rb'\s*\{\s*"id"\s*:\s*(\d+)', parts[0][:100])
            return None, int(match[1]) if match else None

def emit(event, data):
    print(json.dumps({"event": event, "data": data}, ensure_ascii=False), flush=True)

def log_unexpected(error, context):
    """A traceback on stderr, which the shell logs. D-Bus error text is left out: it can carry credentials."""
    if getattr(error, "type", None):
        detail = "".join(traceback.format_tb(error.__traceback__)) + f"{type(error).__name__}: {error.type}\n"
    else:
        detail = "".join(traceback.format_exception(error))
    print(f"{context} failed:\n{detail}", end="", file=sys.stderr, flush=True)

class BackendError(Exception):
    def __init__(self, code, message):
        self.code, self.message = code, message
        super().__init__(message)

def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, name = tempfile.mkstemp(prefix=".shale-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream, ensure_ascii=False)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)

def is_time(value):
    """A positive epoch time in milliseconds, as JavaScript's Date.now() gives it."""
    return type(value) in (int, float) and math.isfinite(value) and 0 < value < 1e14

def check_ids(lists, known, what):
    """Lists of IDs from `known`, none repeated across them."""
    if not all(isinstance(ids, list) for ids in lists):
        raise BackendError("invalid", f"Incorrect {what}.")
    ids = [item for items in lists for item in items]
    if not all(isinstance(item, str) and item in known for item in ids) or len(ids) != len(set(ids)):
        raise BackendError("invalid", f"Incorrect {what}.")

def check_setting(key, value):
    """Raises an "invalid" error for a value of a known setting that the shell can't use."""
    if type(value) is not type(DEFAULTS[key]):
        raise BackendError("invalid", f"Incorrect type for {key}.")
    if key == "version" and value != 1:
        raise BackendError("invalid", "Unsupported settings version.")
    if key == "fontSize" and value not in (12, 14, 16, 18):
        raise BackendError("invalid", "Choose a supported text size.")
    if key == "captureDelay" and value not in (0, 3, 5, 10):
        raise BackendError("invalid", "Choose a supported capture delay.")
    if key == "surfaceTone" and value not in ("charcoal", "midnight", "warm"):
        raise BackendError("invalid", "Choose a supported surface tone.")
    if key in ("accentColor", "accentManual") and ((luminance := accent_luminance(value)) is None or luminance < 0.28):
        raise BackendError("invalid", "Choose a brighter six-digit hex color.")
    if key in ("screenshotDirectory", "recordingDirectory", "wallpaperDirectory") and not (value.startswith("~/") or Path(value).is_absolute()):
        raise BackendError("invalid", "Capture folders must be absolute paths or start with ~/.")
    if key == "eqPreset" and value not in (*equalizer.PRESETS, "custom"):
        raise BackendError("invalid", "Choose a supported equalizer preset.")
    if key == "lockScreen" and value not in ("builtin", "hyprlock"):
        raise BackendError("invalid", "Choose the built-in lock screen or hyprlock.")
    if key == "lockStyle" and value not in ("particles", "classic"):
        raise BackendError("invalid", "Choose the particle or classic lock screen.")
    if key == "searchEngine" and value not in SEARCH_ENGINES:
        raise BackendError("invalid", "Choose a supported search engine.")
    if key == "weatherUnits" and value not in weather.UNITS:
        raise BackendError("invalid", "Choose metric or imperial units.")
    if key == "recordAudio" and value not in RECORD_AUDIO:
        raise BackendError("invalid", "Choose system audio, the microphone or no audio.")
    if key == "activityTracking" and value not in ACTIVITY_TRACKING:
        raise BackendError("invalid", "Choose whether to record activity.")
    if key == "focusMinutes" and value not in (25, 50, 90):
        raise BackendError("invalid", "Choose a supported focus length.")
    # "recorded": where Activity's record already ends, for a session resumed with Undo.
    if key == "focusSession" and value and not (set(value) in ({"started", "ends"}, {"started", "ends", "recorded"})
                                                and all(is_time(value[k]) for k in value) and value["started"] < value["ends"]
                                                and value["started"] <= value.get("recorded", value["started"]) <= value["ends"]):
        raise BackendError("invalid", "Incorrect focus session.")
    if key == "timers" and (len(value) > 10 or not all(isinstance(t, dict) and set(t) == {"label", "ends", "seconds"}
                                                         and isinstance(t["label"], str) and len(t["label"]) <= 60
                                                         and is_time(t["ends"]) and type(t["seconds"]) is int and 0 < t["seconds"] <= 86400
                                                         for t in value)):
        raise BackendError("invalid", "Incorrect timers.")
    if key == "runHistory" and (len(value) > 20 or not all(isinstance(c, str) and 0 < len(c) <= 500 for c in value)):
        raise BackendError("invalid", "Incorrect command history.")
    if key == "barLayout":
        if not set(value) <= {"left", "center", "right", "hidden"}:
            raise BackendError("invalid", "Incorrect bar layout.")
        check_ids(list(value.values()), BAR_ITEMS, "bar layout")
        if set(value.get("hidden", [])) & set(BAR_REQUIRED):
            raise BackendError("invalid", "The recording, privacy and control center items can't be hidden.")
    if key == "controlLayout":
        if not set(value) <= {"tiles", "hiddenTiles", "sections", "footer", "hiddenFooter"}:
            raise BackendError("invalid", "Incorrect control center layout.")
        check_ids([value.get("tiles", []), value.get("hiddenTiles", [])], CONTROL_TILES, "control center tiles")
        check_ids([value.get("footer", []), value.get("hiddenFooter", [])], CONTROL_FOOTER, "control center buttons")
        sections = value.get("sections", {})
        if not isinstance(sections, dict) or not set(sections) <= set(CONTROL_SECTIONS) or not all(type(v) is bool for v in sections.values()):
            raise BackendError("invalid", "Incorrect control center sections.")
        if "settings" in value.get("hiddenFooter", []):
            raise BackendError("invalid", "The Settings button can't be hidden.")
    if key == "clockFormat" and value not in ("time", "day-time", "date-time"):
        raise BackendError("invalid", "Choose a supported clock format.")
    if key == "workspaceStyle" and value not in ("numbers", "dots"):
        raise BackendError("invalid", "Choose numbers or dots.")
    if key == "workspaceSlots" and value not in (0, 5, 10):
        raise BackendError("invalid", "Choose how many workspaces to show.")
    if key == "trayIcons" and not -1 <= value <= 5:
        raise BackendError("invalid", "Choose up to five tray icons.")
    if key == "batteryPercent" and value not in ("auto", "always", "never"):
        raise BackendError("invalid", "Choose when to show the battery percentage.")
    if key == "barStyle" and value not in ("floating", "edge"):
        raise BackendError("invalid", "Choose a floating or edge-to-edge bar.")
    if key == "weekStart" and value not in ("locale", "monday", "sunday", "saturday"):
        raise BackendError("invalid", "Choose the first day of the week.")
    if key == "terminal" and value != "auto" and value not in (prefix[0] for prefix in Backend.TERMINALS):
        raise BackendError("invalid", "Choose a supported terminal.")
    try:
        if key == "weatherLocation":
            weather.validate_location(value)
        if key == "eqBands":
            equalizer.validate(value)
        if key == "shortcuts":
            shortcuts.check(value)
    except ValueError as error:
        raise BackendError("invalid", str(error)) from None

def settings():
    try:
        value = json.loads(CONFIG.read_text())
        if not isinstance(value, dict) or value.get("version", 1) != 1:
            raise ValueError("Unsupported settings schema")
    except FileNotFoundError:
        return dict(DEFAULTS)
    except (ValueError, OSError):
        return {**DEFAULTS, "diagnostic": "Settings could not be loaded; defaults are active."}
    # A hand-edited value, or one a newer version wrote, costs only that setting.
    rejected = []
    for key in [key for key in value if key in DEFAULTS]:
        try:
            check_setting(key, value[key])
        except BackendError:
            rejected.append(key)
            del value[key]
    if rejected:
        return {**DEFAULTS, **value, "diagnostic": "Some settings could not be loaded and use their defaults: " + ", ".join(rejected) + "."}
    return {**DEFAULTS, **value}

def save_settings(changes):
    """Saves the known keys of `changes` after validating them; returns every setting."""
    current = settings()
    unreadable = current.pop("diagnostic", None) is not None
    # Only known keys are saved; this also keeps the load diagnostic out of the file.
    changes = {key: value for key, value in changes.items() if key in DEFAULTS}
    for key, value in changes.items():
        check_setting(key, value)
    if CONFIG.exists():
        if unreadable:
            # Keep the file with its rejected values instead of replacing the last good backup.
            shutil.copy2(CONFIG, CONFIG.with_suffix(".invalid.json"))
        else:
            atomic_json(CONFIG.with_suffix(".previous.json"), changed_only(current))
    current.update(changes)
    atomic_json(CONFIG, changed_only(current))
    return current

def reset_settings(keys):
    """Puts `keys` back to their defaults; returns every setting."""
    if not isinstance(keys, list) or not all(isinstance(key, str) and key in DEFAULTS and key not in ("version", "shortcuts") for key in keys):
        raise BackendError("invalid", "Choose settings to reset.")
    return save_settings({key: DEFAULTS[key] for key in keys})

def export_path(value):
    """An absolute or ~/ path to a .json file whose folder exists."""
    if not isinstance(value, str) or not (value.startswith("~/") or value.startswith("/")) or "\n" in value or not value.endswith(".json"):
        raise BackendError("invalid", "Enter a .json file path beginning with / or ~/.")
    path = Path(value).expanduser()
    if not path.parent.is_dir():
        raise BackendError("invalid", f"The folder {path.parent} doesn't exist.")
    return path

def export_settings(value):
    """Writes what the user changed, without history or location, to a file another computer can import."""
    path = export_path(value)
    current = settings()
    current.pop("diagnostic", None)
    data = {key: value for key, value in changed_only(current).items() if key not in PRIVATE_KEYS}
    data["exported"] = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    try:
        atomic_json(path, data)
    except OSError as error:
        raise BackendError("failed", f"Could not write {path}: {error.strerror or error}.") from None
    return {"path": str(path), "count": len(data) - 2}

def import_settings(value):
    """Applies every usable setting in an exported file except shortcuts, which need the compositor; returns
    {settings, applied, skipped, shortcuts (the file's, unchecked)}."""
    path = export_path(value)
    try:
        data = json.loads(path.read_text())
    except FileNotFoundError:
        raise BackendError("invalid", f"{path} doesn't exist.") from None
    except (OSError, ValueError):
        raise BackendError("invalid", "That file isn't a Shale settings export.") from None
    if not isinstance(data, dict) or data.get("version") != 1:
        raise BackendError("invalid", "That file isn't a Shale settings export.")
    usable, skipped = {}, []
    for key, item in data.items():
        if key in ("version", "exported", "shortcuts"):
            continue
        try:
            if key not in DEFAULTS or key in PRIVATE_KEYS:
                raise BackendError("invalid", key)
            check_setting(key, item)
            usable[key] = item
        except BackendError:
            skipped.append(key)
    return {"settings": save_settings(usable), "applied": sorted(usable), "skipped": sorted(skipped), "shortcuts": data.get("shortcuts")}

def migrated_settings():
    """settings(), after upgrades that depend on more than the file. History recorded before
    activityTracking existed means tracking was on: it stays on instead of asking. Only a file that
    loaded cleanly is upgraded; an unreadable one, or a rejected activityTracking, may hold another choice."""
    current = settings()
    if current["activityTracking"] == "ask" and "diagnostic" not in current and activity.has_history(STATE / "activity.sqlite3"):
        current = save_settings({"activityTracking": "on"})
    return current

def record_audio(value):
    """The audio choice of a recording request; shells before recordAudio sent a system-audio flag."""
    if type(value) is bool:
        value = "system" if value else "none"
    if not isinstance(value, str) or value not in RECORD_AUDIO:
        raise BackendError("invalid", "Choose system audio, the microphone or no audio.")
    return value

def number(params, key, default):
    """A finite number from request params, or an "invalid" error naming the field."""
    try:
        value = float(params.get(key, default))
    except (TypeError, ValueError):
        value = math.nan
    if not math.isfinite(value):
        raise BackendError("invalid", f"{key} must be a number.")
    return value

def modified(path):
    try:
        return path.stat().st_mtime
    except OSError:  # removed by another request meanwhile
        return 0

def changed_only(values):
    """What the user changed; defaults stay out of the file so improved defaults reach everyone."""
    return {"version": 1, **{key: value for key, value in values.items() if key != "version" and value != DEFAULTS.get(key)}}

def display_number(value):
    """How a result is shown and copied: exact integers, floats to 12 significant digits (0.1 + 0.2 is 0.3)."""
    if isinstance(value, int):
        return str(value)
    if value == int(value) and abs(value) < 1e15:
        return str(int(value))
    text = f"{value:.12g}"
    return text.replace("e+", "e")

def calculate(expression):
    if not isinstance(expression, str) or len(expression) > 256:
        raise BackendError("invalid", "Enter an expression of at most 256 characters.")
    ops = {ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul,
           ast.Div: operator.truediv, ast.FloorDiv: operator.floordiv, ast.Mod: operator.mod,
           ast.Pow: operator.pow}
    def visit(node, depth=0):
        if depth > 24:
            raise ValueError()
        if isinstance(node, ast.Constant) and type(node.value) in (int, float):
            value = node.value
        elif isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.UAdd, ast.USub)):
            value = visit(node.operand, depth + 1) * (-1 if isinstance(node.op, ast.USub) else 1)
        elif isinstance(node, ast.BinOp) and type(node.op) in ops:
            left, right = visit(node.left, depth + 1), visit(node.right, depth + 1)
            if isinstance(node.op, ast.Pow) and (abs(right) > 100 or abs(left) > 1e12):
                raise ValueError()
            value = ops[type(node.op)](left, right)
        else:
            raise ValueError()
        if type(value) not in (int, float) or not math.isfinite(value) or abs(value) > 1e100:
            raise ValueError()
        return value
    try:
        value = visit(ast.parse(expression, mode="eval").body)
        return {"value": value, "text": display_number(value)}
    except (ValueError, SyntaxError, ZeroDivisionError, OverflowError, TypeError):
        raise BackendError("invalid", "Use finite arithmetic with +, -, *, /, //, %, ** and parentheses.") from None

async def run(*args, data=None, timeout=15, cancel_ok=False):
    if not shutil.which(args[0]):
        raise BackendError("unavailable", f"Install {args[0]} to use this feature.")
    # wl-copy forks a child that serves the clipboard; if it inherits our pipes, communicate() never sees EOF.
    detached = args[0] == "wl-copy"
    process = await asyncio.create_subprocess_exec(*args, stdin=asyncio.subprocess.PIPE if data is not None else asyncio.subprocess.DEVNULL,
                                                   stdout=asyncio.subprocess.DEVNULL if detached else asyncio.subprocess.PIPE,
                                                   stderr=asyncio.subprocess.DEVNULL)
    try:
        out, _ = await asyncio.wait_for(process.communicate(data), timeout)
    except (asyncio.TimeoutError, asyncio.CancelledError) as error:
        try:
            process.kill()
        except ProcessLookupError:
            pass
        # Bounded: a leftover grandchild holding a pipe must not keep the caller (and its locks) stuck.
        try:
            await asyncio.wait_for(process.wait(), 2)
        except asyncio.TimeoutError:
            pass
        if isinstance(error, asyncio.CancelledError):
            raise
        raise BackendError("timeout", f"{args[0]} did not finish in time.") from None
    if process.returncode:
        raise BackendError("cancelled" if cancel_ok else "failed", "Action cancelled." if cancel_ok else f"{args[0]} failed (exit {process.returncode}).")
    return out


BINARY_ENTRY = re.compile(r"^\[\[ binary data (?P<size>[\d.]+ \w+) (?P<kind>\w+)(?: (?P<width>\d+)x(?P<height>\d+))? \]\]$")


def clipboard_label(text):
    """Readable label for cliphist's binary summaries, e.g. "Image · PNG · 1920×1080 · 1.2 MiB"."""
    match = BINARY_ENTRY.match(text.strip()) if "[[" in text[:4] else None
    if not match:
        return ""
    kind = match["kind"].lower()
    image = kind in ("png", "jpeg", "jpg", "gif", "webp", "bmp", "svg", "tiff", "avif")
    parts = ["Image" if image else "Data", match["kind"].upper()]
    if match["width"]:
        parts.append(match["width"] + "×" + match["height"])
    parts.append(match["size"])
    return " · ".join(parts)


# Six or eight digits only: "#123" and "#bad" are far more often issue numbers and hashtags.
HEX_COLOR = re.compile(r"#([0-9a-f]{6}|[0-9a-f]{8})", re.IGNORECASE)
RGB_COLOR = re.compile(r"rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*(?:,\s*\d*\.?\d+%?\s*)?\)", re.IGNORECASE)


def clipboard_color(text):
    """"#rrggbb" for a copied hex or rgb() color, else "". Alpha is dropped: QML reads #aarrggbb."""
    if match := HEX_COLOR.fullmatch(text):
        return "#" + match[1][:6].lower()
    if (match := RGB_COLOR.fullmatch(text)) and all(int(channel) <= 255 for channel in match.groups()):
        return "#" + ''.join(f"{int(channel):02x}" for channel in match.groups())
    return ""


LINK = re.compile(r"https?://\S+", re.IGNORECASE)


def clipboard_link(text):
    if not LINK.fullmatch(text):
        return False
    try:
        return bool(urlsplit(text).hostname)
    except ValueError:
        return False


def clipboard_path(text):
    """The existing local file or folder a copied path or file:// URL names, else None."""
    if "\n" in text:
        return None
    if text.startswith("file://"):
        try:
            parts = urlsplit(text)
        except ValueError:
            return None
        if parts.netloc not in ("", "localhost"):
            return None
        text = unquote(parts.path)
    elif not text.startswith(("/", "~/")):
        return None
    try:
        path = Path(text).expanduser()
        return path if path.is_absolute() and path.exists() else None
    except (OSError, ValueError, RuntimeError):
        return None


def clipboard_kind(text):
    """A color or link in a cliphist preview line, which ends in "…" when cut. Most lines are neither,
    so the first character settles them before any pattern runs. Paths need the disk: see path_kinds."""
    first = text[:1]
    if first in ("#", "r", "R") and (color := clipboard_color(text)):
        return {"kind": "color", "color": color}
    if first in ("h", "H") and clipboard_link(text.removesuffix("…")):
        return {"kind": "link"}
    return {}


def path_kinds(texts):
    """{"kind": "path", "folder": bool} for each text naming an existing file or folder, else None."""
    paths = [clipboard_path(text) for text in texts]
    return [{"kind": "path", "folder": path.is_dir()} if path else None for path in paths]


def clipboard_target(text):
    """What Open does with a full clipboard entry: a link opens; a file is only shown in its folder,
    since anything can put a path on the clipboard and opening it could run it."""
    if clipboard_link(text):
        return {"url": text}
    if path := clipboard_path(text):
        return {"path": str(path if path.is_dir() else path.parent)}
    return None


PROPERTIES = "org.freedesktop.DBus.Properties"
SERVICE_MISSING = ("org.freedesktop.DBus.Error.ServiceUnknown", "org.freedesktop.DBus.Error.NameHasNoOwner")
FLATPAK_SCOPE = re.compile(r"app-flatpak-([A-Za-z0-9_.-]+?)-\d+\.scope")

class TimedInterface:
    """A dbus-next proxy interface whose method calls give up after `timeout` seconds."""
    def __init__(self, proxy, timeout):
        self._proxy, self._timeout = proxy, timeout

    def __getattr__(self, attribute):
        value = getattr(self._proxy, attribute)
        if not attribute.startswith("call_"):
            return value
        async def call(*args, **options):
            try:
                return await asyncio.wait_for(value(*args, **options), self._timeout)
            except asyncio.TimeoutError:
                raise BackendError("timeout", "A system service did not answer in time.") from None
        return call

def key_management(rsn_flags):
    """NetworkManager key-mgmt for a new password network: sae when the access point offers only WPA3
    (SAE without PSK); WPA2/WPA3 transition networks keep wpa-psk."""
    return "sae" if rsn_flags & 0x400 and not rsn_flags & 0x100 else "wpa-psk"

async def tray_owner(call, item_id, title=""):
    """The pid of the process that owns a tray item, found through the StatusNotifierWatcher.

    `call(destination, path, interface, member, signature, body)` returns the reply body."""
    (registered,) = await call("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher", PROPERTIES, "Get", "ss",
                               ["org.kde.StatusNotifierWatcher", "RegisteredStatusNotifierItems"])
    matches = []
    for entry in registered.value:
        # "service/object/path", or just the service with the default path.
        service, _, path = entry.partition("/")
        path = "/" + path if path else "/StatusNotifierItem"
        try:
            (value,) = await call(service, path, PROPERTIES, "Get", "ss", ["org.kde.StatusNotifierItem", "Id"])
            if value.value != item_id:
                continue
            if title:
                (value,) = await call(service, path, PROPERTIES, "Get", "ss", ["org.kde.StatusNotifierItem", "Title"])
            matches.append((service, value.value == title))
        except BackendError:
            continue  # an item that went away or doesn't answer
    if not matches:
        raise BackendError("unavailable", "This app can't be closed from here.")
    # Two items can share an id (two windows of one app); the title tells them apart.
    service = next((service for service, same in matches if same), matches[0][0])
    (pid,) = await call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                        "GetConnectionUnixProcessID", "s", [service])
    return pid

async def quit_process(pid, proc=Path("/proc"), kill=os.kill, command=None, protected=()):
    """Ask a tray app to exit: SIGTERM, or `flatpak kill` for a Flatpak (its D-Bus peer is a proxy)."""
    if not isinstance(pid, int) or pid <= 1 or pid in (os.getpid(), os.getppid(), *protected):
        raise BackendError("unavailable", "This app can't be closed from here.")
    try:
        if (proc / str(pid)).stat().st_uid != os.getuid():
            raise BackendError("unavailable", "This app belongs to another user.")
        cgroup = (proc / str(pid) / "cgroup").read_text()
    except OSError:
        raise BackendError("unavailable", "The app has already exited.") from None
    flatpak = FLATPAK_SCOPE.search(cgroup)
    if flatpak:
        await (command or run)("flatpak", "kill", flatpak[1], timeout=5)
        return {"quit": flatpak[1]}
    try:
        kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        raise BackendError("unavailable", "The app has already exited.") from None
    return {"quit": pid}

class Backend:
    def __init__(self):
        self.activity = None
        self.activity_snapshot = None
        # Keeps the previous counters for the system monitor's rates.
        self.sysmon = sysmon.Sampler(run=run)
        # Followed by watch_power; slows the system monitor's background sampling.
        self.power_saver = False
        self.activity_locked = False
        self.activity_sleeping = False
        self.lid_fd = None
        self.lid_lock = asyncio.Lock()
        self.bus = None
        self.session_bus = None
        self.bus_lock = asyncio.Lock()
        self.wifi_lock = asyncio.Lock()
        self.vpn_lock = asyncio.Lock()
        self.wallpaper_lock = asyncio.Lock()
        self.daemon_lock = asyncio.Lock()
        self.wallhaven_lock = asyncio.Lock()
        self.capture_lock = asyncio.Lock()
        self.pairing_reply = None
        self.pairing_lock = asyncio.Lock()
        self.equalizer = equalizer.Equalizer(RUNTIME)
        self.eq_lock = asyncio.Lock()
        self.eq_requests = 0
        self.weather_lock = asyncio.Lock()
        self.lock_hint_lock = asyncio.Lock()
        self.shortcut_lock = asyncio.Lock()
        # Clipboard entries deleted, and wipes so far: a preview still being decoded for one must not be saved after.
        self.clipboard_deleted = set()
        self.clipboard_wipes = 0
        # Leaves the key-recording submap if Settings never says it's done.
        self.record_timeout = None

    async def interface(self, name, path, interface, timeout=25):
        """A system bus interface whose method calls time out after `timeout` seconds (None: never)."""
        try:
            from dbus_next.aio import MessageBus
            from dbus_next import BusType
        except ImportError:
            raise BackendError("unavailable", "Install python-dbus-next to enable system controls.") from None
        async with self.bus_lock:
            if self.bus is None or not self.bus.connected:
                self.bus = await MessageBus(bus_type=BusType.SYSTEM, negotiate_unix_fd=True).connect()
        intro = await self.bus.introspect(name, path)
        proxy = self.bus.get_proxy_object(name, path, intro).get_interface(interface)
        return proxy if timeout is None else TimedInterface(proxy, timeout)

    async def session_call(self, destination, path, interface, member, signature="", body=()):
        """One call on the session bus, without introspection; returns the reply body."""
        try:
            from dbus_next.aio import MessageBus
            from dbus_next import BusType, Message, MessageType
        except ImportError:
            raise BackendError("unavailable", "Install python-dbus-next to enable system controls.") from None
        async with self.bus_lock:
            if self.session_bus is None or not self.session_bus.connected:
                self.session_bus = await MessageBus(bus_type=BusType.SESSION).connect()
        message = Message(destination=destination, path=path, interface=interface, member=member,
                          signature=signature, body=list(body))
        try:
            reply = await asyncio.wait_for(self.session_bus.call(message), 3)
        except asyncio.TimeoutError:
            raise BackendError("unavailable", "The app did not answer.") from None
        if reply.message_type == MessageType.ERROR:
            raise BackendError("unavailable", (reply.body or [reply.error_name])[0])
        return reply.body

    async def wallpaper_daemon(self):
        """hyprpaper, awww or swww, started if none runs yet; an "unavailable" error otherwise."""
        async with self.daemon_lock:
            daemon = await wallpaper.ensure()
        if daemon in (None, "foreign"):
            raise wallpaper.unavailable(daemon, BackendError)
        return daemon

    async def active_wallpapers(self):
        """Monitor name -> image the running daemon shows. Never starts a daemon; only apply and restore do."""
        daemon = wallpaper.current()
        if daemon == "foreign" or (daemon is None and not wallpaper.installed()):
            raise wallpaper.unavailable(daemon, BackendError)
        return await wallpaper.active(run, daemon) if daemon else {}

    async def apply_equalizer(self, enabled, bands):
        """Makes the filter match: off, or running with `bands` (validated). Call with eq_lock held."""
        # Past validation, any ValueError is PipeWire's (unreadable pw-dump output), not the bands.
        try:
            if not enabled:
                await asyncio.to_thread(self.equalizer.stop)
            elif not self.equalizer.running:
                await self.equalizer.start(run, bands)
            elif bands != self.equalizer.bands:
                await self.equalizer.update(run, bands)
        except RuntimeError as error:
            raise BackendError("failed", str(error)) from None
        except ValueError:
            raise BackendError("failed", "PipeWire gave an unreadable answer; try again.") from None

    async def settings_replaced(self, before, after):
        """What settings changed in bulk (import, reset) mean beyond the file. Activity recording stops once it is
        off, and the running equalizer follows. Returns a problem to report, or None."""
        if after["activityTracking"] != "on":
            self.close_activity()
        if (before["eqEnabled"], before["eqBands"]) == (after["eqEnabled"], after["eqBands"]):
            return None
        self.eq_requests += 1  # settled here; resume_equalizer must not act on the old settings
        try:
            async with self.eq_lock:
                await self.apply_equalizer(after["eqEnabled"], equalizer.validate(after["eqBands"]))
        except (BackendError, ValueError) as error:
            return "The equalizer couldn't follow: " + getattr(error, "message", str(error))
        finally:
            emit("eq", self.equalizer.status())
        return None

    async def resume_equalizer(self, delays):
        """Starts the filter the settings ask for, trying again after each delay (PipeWire may still be
        starting). Leaves it to the shell once it sends eq.apply; False if every attempt failed."""
        requests = self.eq_requests
        for delay in delays:
            await asyncio.sleep(delay)
            saved = settings()
            async with self.eq_lock:
                if self.eq_requests != requests or not saved["eqEnabled"] or self.equalizer.running:
                    return True
                try:
                    await self.equalizer.start(run, equalizer.validate(saved["eqBands"]))
                    return True
                except (RuntimeError, ValueError, BackendError) as error:
                    print("Equalizer:", getattr(error, "message", error), file=sys.stderr, flush=True)
        return False

    async def check_equalizer(self, delays=(1, 2, 4, 8, 16)):
        """Brings back a filter that exited on its own (PipeWire restarted, the filter crashed); reports
        an "eq" event with the equalizer status when it can't."""
        async with self.eq_lock:
            if self.equalizer.process is None or self.equalizer.running:
                return
            await asyncio.to_thread(self.equalizer.stop)
        print("Equalizer: the filter exited; restarting it.", file=sys.stderr, flush=True)
        if not await self.resume_equalizer(delays):
            emit("eq", self.equalizer.status())

    COMMANDS = ["hyprctl", "cliphist", "wl-copy", "wl-paste", "grim", "slurp", "hyprpicker", "wf-recorder", "brightnessctl",
                "hyprlock", "hypridle", "fd", "cava", "hyprpaper", "awww", "swww", "xdg-terminal-exec"]

    # How each terminal takes a command to run; $TERMINAL is assumed to follow the common -e convention.
    TERMINALS = (("xdg-terminal-exec",), ("foot",), ("kitty",), ("alacritty", "-e"), ("wezterm", "start", "--"),
                 ("ghostty", "-e"), ("konsole", "-e"), ("gnome-terminal", "--"))

    def terminal(self):
        """The command prefix that runs a program in a terminal, or [] when none is installed."""
        picked = settings()["terminal"]
        prefix = next((list(prefix) for prefix in self.TERMINALS if prefix[0] == picked), None)
        if prefix and shutil.which(picked):
            return prefix
        chosen = os.environ.get("TERMINAL", "").strip()
        if chosen and shutil.which(chosen):
            return [chosen, "-e"]
        return next((list(prefix) for prefix in self.TERMINALS if shutil.which(prefix[0])), [])

    async def capabilities(self):
        """What this machine offers, so the shell can hide controls instead of failing on click."""
        try:
            monitors = json.loads(await run("hyprctl", "monitors", "-j"))
            builtin_panel = any(BUILTIN_PANEL.fullmatch(str(m.get("name", ""))) for m in monitors)
        except (BackendError, ValueError, TypeError):
            builtin_panel = None
        return {"commands": {x: bool(shutil.which(x)) for x in self.COMMANDS},
                "dbus": importlib.util.find_spec("dbus_next") is not None,
                "lid": any(Path("/proc/acpi/button/lid").glob("*")),
                "terminal": self.terminal(),
                "terminals": [prefix[0] for prefix in self.TERMINALS if shutil.which(prefix[0])],
                "builtinPanel": builtin_panel, "version": 1}

    async def hypr_eval(self, code):
        """Runs Lua in Hyprland; False when it reports an error."""
        try:
            return (await run("hyprctl", "eval", code)).decode().strip() == "ok"
        except BackendError:
            return False

    async def live_binds(self):
        try:
            return json.loads(await run("hyprctl", "binds", "-j"))
        except (BackendError, ValueError):
            return []

    async def save_shortcuts(self, changed, moves):
        """Saves the `shortcuts` setting, writes shortcuts.lua for later config loads and moves the binds now.
        `moves` is {action: (old keys, new keys)}; a reload applies them if moving one fails."""
        save_settings({"shortcuts": changed})
        target = CONFIG.parent / "shortcuts.lua"
        target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        fd, name = tempfile.mkstemp(prefix=".shale-", dir=target.parent)
        try:
            with os.fdopen(fd, "w") as stream:
                stream.write(shortcuts.overrides_lua(changed))
            os.replace(name, target)
        finally:
            if os.path.exists(name):
                os.unlink(name)
        changes = {action: keys for action, keys in moves.items() if keys[0] != keys[1]}
        if changes and not await self.hypr_eval(shortcuts.rebind_lua(changes, SHALE_COMMAND)):
            try:
                await run("hyprctl", "reload")
            except BackendError:
                raise BackendError("failed", "Saved. Hyprland couldn't take the change now; it applies when Hyprland reloads its config.") from None

    async def shortcuts(self, action, p):
        bound, ready = shortcuts.installed(HYPR)
        changed = dict(settings()["shortcuts"])
        if action == "list":
            return shortcuts.listing(bound, changed, ready)
        if action == "record":
            return await self.record_keys(p.get("active") is True and ready)
        if not ready:
            raise BackendError("unavailable", "Update Shale with ./install.sh --update to change shortcuts here.")
        name = p.get("action")
        if action not in ("set", "reset") or (name is not None and name not in shortcuts.ACTIONS) or (action == "set" and name is None):
            raise BackendError("invalid", "Unknown shortcut.")
        current = shortcuts.effective(bound, changed)
        names = [name] if name else list(changed)
        if action == "set":
            try:
                keys = shortcuts.canonical(p.get("keys")) if p.get("keys") else ""
            except ValueError as error:
                raise BackendError("invalid", str(error)) from None
            wanted = {name: keys}
        else:
            # Back to what the installer bound; an action it left alone gets its usual keys.
            wanted = {n: bound.get(n) or shortcuts.ACTIONS[n]["keys"] for n in names}
        binds = await self.live_binds()
        for n, keys in wanted.items():
            if keys and (reason := shortcuts.clash(keys, n, current, binds, {**current, **wanted})):
                raise BackendError("clash", reason)
        for n, keys in wanted.items():
            if keys == bound.get(n, ""):
                changed.pop(n, None)
            else:
                changed[n] = keys
        await self.save_shortcuts(changed, {n: (current[n], keys) for n, keys in wanted.items()})
        return shortcuts.listing(bound, changed, ready)

    async def import_shortcuts(self, wanted):
        """Applies imported shortcuts when all of them fit this computer; True if they did."""
        bound, ready = shortcuts.installed(HYPR)
        try:
            shortcuts.check(wanted)
        except ValueError:
            return False
        current = shortcuts.effective(bound, settings()["shortcuts"])
        after = shortcuts.effective(bound, wanted)
        binds = await self.live_binds()
        if not ready or any(keys and shortcuts.clash(keys, n, current, binds, after) for n, keys in after.items() if keys != current[n]):
            return False
        await self.save_shortcuts({n: keys for n, keys in wanted.items() if keys != bound.get(n, "")},
                                  {n: (current[n], after[n]) for n in after})
        return True

    async def record_keys(self, active):
        """Enters or leaves the empty submap shale.lua defines, so pressing keys that are already bound reaches the
        recorder in Settings instead of acting. It is left after 15 seconds whatever happens."""
        if self.record_timeout:
            self.record_timeout.cancel()
            self.record_timeout = None
        if active:
            if not await self.hypr_eval(f'hl.dispatch(hl.dsp.submap("{shortcuts.RECORD_SUBMAP}"))'):
                return {"active": False}
            async def later():
                await asyncio.sleep(15)
                self.record_timeout = None
                await self.leave_recording()
            self.record_timeout = asyncio.create_task(later())
            return {"active": True}
        await self.leave_recording()
        return {"active": False}

    async def leave_recording(self):
        try:
            current = json.loads(await run("hyprctl", "-j", "submap"))
        except (BackendError, ValueError):
            return
        if current == shortcuts.RECORD_SUBMAP:
            await self.hypr_eval('hl.dispatch(hl.dsp.submap("reset"))')

    async def compositor_saver(self, saver, refresh):
        """Turn off blur and shadows and drop built-in panels to their lowest refresh rate in power
        saver, then put back exactly what was there. The saved originals live in the runtime directory,
        so they survive shell restarts but not a reboot, which starts from the Hyprland config."""
        path = RUNTIME / "power-saver.json"
        try:
            saved = json.loads(path.read_text())
        except (FileNotFoundError, ValueError):
            saved = {}
        options = saved.get("options", {}) if isinstance(saved.get("options"), dict) else {}
        outputs = {name: mode for name, mode in (saved.get("monitors") or {}).items()
                   if isinstance(mode, str) and re.fullmatch(r"\d+x\d+@[\d.]+", mode)}
        async def configure(code):
            if (await run("hyprctl", "eval", code)).decode().strip() != "ok":
                raise BackendError("failed", "Could not change compositor settings.")
        def monitor_code(monitor, mode):
            # hl.monitor replaces the output's whole rule: carry over its rotation and 10-bit colour.
            fields = [f'output = "{monitor["name"]}"', f'mode = "{mode}"', f'position = "{int(monitor["x"])}x{int(monitor["y"])}"',
                      f'scale = "{float(monitor["scale"]):g}"', f'transform = {int(monitor.get("transform", 0))}']
            if "2101010" in str(monitor.get("currentFormat", "")):
                fields.append("bitdepth = 10")
            return "hl.monitor({" + ", ".join(fields) + "})"
        changes, keep = [], {}
        for option in ("blur", "shadow"):
            current = json.loads(await run("hyprctl", "getoption", f"decoration:{option}:enabled", "-j")).get("bool", False)
            if saver:
                # After a config reload the compositor is back at the user's value; record it again.
                keep[option] = current or options.get(option, False)
                if current:
                    changes.append(f"hl.config({{decoration = {{{option} = {{enabled = false}}}}}})")
            elif options.get(option) and not current:
                changes.append(f"hl.config({{decoration = {{{option} = {{enabled = true}}}}}})")
        monitors_kept = {}
        for monitor in json.loads(await run("hyprctl", "monitors", "-j")):
            name = str(monitor.get("name", ""))
            if not BUILTIN_PANEL.fullmatch(name):
                continue
            width, height, rate = int(monitor["width"]), int(monitor["height"]), float(monitor["refreshRate"])
            rates = [float(match[1]) for mode in monitor.get("availableModes", [])
                     if (match := re.fullmatch(rf"{width}x{height}@([\d.]+)Hz", mode))]
            low = min((value for value in rates if value >= 59), default=rate)
            if saver and refresh and rate > low + 1:
                monitors_kept[name] = f"{width}x{height}@{rate:.2f}"
                changes.append(monitor_code(monitor, f"{width}x{height}@{low:.2f}"))
            elif saver and refresh and name in outputs:
                monitors_kept[name] = outputs[name]
            elif name in outputs and rate < float(outputs[name].rpartition("@")[2]) - 1:
                changes.append(monitor_code(monitor, outputs[name]))
        if saver:
            atomic_json(path, {"options": keep, "monitors": monitors_kept})
        for code in changes:
            await configure(code)
        if not saver:
            path.unlink(missing_ok=True)
        return {"saver": saver, "changed": len(changes)}

    async def session_path(self):
        """The logind object path of the shell's session: $XDG_SESSION_ID, else the session this process
        runs in, else (started from a systemd user unit, outside any session) this user's first seat session."""
        manager = await self.interface("org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager")
        for lookup, argument in ((manager.call_get_session, os.environ.get("XDG_SESSION_ID")),
                                 (manager.call_get_session_by_pid, os.getpid())):
            if argument:
                try:
                    return await lookup(argument)
                except Exception:
                    pass  # a stale session id, or a process outside any session
        sessions = await manager.call_list_sessions()
        path = next((s[4] for s in sessions if s[1] == os.getuid() and s[3]), None)
        if not path:
            raise BackendError("unavailable", "No logind session was found.")
        return path

    async def objects(self, name):
        manager = await self.interface(name, "/", "org.freedesktop.DBus.ObjectManager")
        return await manager.call_get_managed_objects()

    async def vpn(self, action, p):
        """NetworkManager's VPN and WireGuard profiles. Secrets (passwords, one-time codes) are asked for by
        NetworkManager's own secret agent, as they would be from any other client."""
        name = "org.freedesktop.NetworkManager"
        from dbus_next import Variant  # importable once interface() has found dbus-next
        manager = await self.interface(name, "/org/freedesktop/NetworkManager", name)
        manager_props = await self.interface(name, "/org/freedesktop/NetworkManager", "org.freedesktop.DBus.Properties")
        settings = await self.interface(name, "/org/freedesktop/NetworkManager/Settings", name + ".Settings")
        profiles = {}
        for path in await settings.call_list_connections():
            connection = await self.interface(name, path, name + ".Settings.Connection")
            try:
                config = await connection.call_get_settings()
            except Exception:
                continue  # A system profile may be private to another user.
            section = config.get("connection", {})
            kind = section.get("type", Variant("s", "")).value
            if kind not in ("vpn", "wireguard"):
                continue
            # "org.freedesktop.NetworkManager.openvpn" → "OpenVPN"-ish short names for the subtitle.
            service = config.get("vpn", {}).get("service-type", Variant("s", "")).value if kind == "vpn" else "wireguard"
            profiles[path] = {"path": path, "name": section.get("id", Variant("s", "VPN")).value,
                              "kind": service.rsplit(".", 1)[-1] or kind, "state": "off", "active": ""}
        for active in (await manager_props.call_get(name, "ActiveConnections")).value:
            props = await self.interface(name, active, "org.freedesktop.DBus.Properties")
            try:
                connection = (await props.call_get(name + ".Connection.Active", "Connection")).value
                state = (await props.call_get(name + ".Connection.Active", "State")).value
            except Exception:
                continue  # it went away while being read
            if connection in profiles:
                profiles[connection].update(active=active, state={1: "connecting", 2: "on", 3: "disconnecting"}.get(state, "off"))
        if action == "list":
            return {"connections": [{key: value for key, value in profile.items() if key != "active"}
                                    for profile in sorted(profiles.values(), key=lambda profile: profile["name"].lower())]}
        profile = profiles.get(p.get("path"))
        if profile is None:
            raise BackendError("invalid", "Choose a VPN connection.")
        if action == "disconnect":
            if profile["active"]:
                await manager.call_deactivate_connection(profile["active"])
            return {"done": True}
        if action != "connect":
            raise BackendError("invalid", "Unknown VPN operation.")
        if profile["state"] == "on":
            return {"done": True}
        active_path = profile["active"] or await manager.call_activate_connection(profile["path"], "/", "/")
        active_props = await self.interface(name, active_path, "org.freedesktop.DBus.Properties")
        # Long enough to type a password or a one-time code into NetworkManager's prompt.
        for _ in range(180):
            try:
                state = (await active_props.call_get(name + ".Connection.Active", "State")).value
            except Exception:
                state = 4  # the active connection object is gone: it failed
            if state == 2:
                return {"done": True}
            if state == 4:
                raise BackendError("failed", f"Could not connect to {profile['name']}. A VPN that needs a password also needs a "
                                             "NetworkManager secret agent, such as nm-applet.")
            await asyncio.sleep(0.5)
        raise BackendError("timeout", f"Connecting to {profile['name']} timed out.")

    async def wifi(self, action, p):
        name = "org.freedesktop.NetworkManager"
        manager = await self.interface(name, "/org/freedesktop/NetworkManager", name)
        from dbus_next import Variant  # importable once interface() has found dbus-next
        manager_props = await self.interface(name, "/org/freedesktop/NetworkManager", "org.freedesktop.DBus.Properties")
        if action == "power":
            await manager_props.call_set(name, "WirelessEnabled", Variant("b", bool(p.get("powered", True))))
            return {"done": True}

        device_path = None
        for path in await manager.call_get_devices():
            props = await self.interface(name, path, "org.freedesktop.DBus.Properties")
            if (await props.call_get(name + ".Device", "DeviceType")).value == 2:
                device_path = path
                break
        if device_path is None:
            raise BackendError("unavailable", "No NetworkManager Wi-Fi device is available.")
        device = await self.interface(name, device_path, name + ".Device")
        wireless = await self.interface(name, device_path, name + ".Device.Wireless")
        device_props = await self.interface(name, device_path, "org.freedesktop.DBus.Properties")
        if action == "scan":
            await wireless.call_request_scan({})
            return {"done": True}
        if action == "disconnect":
            if (await device_props.call_get(name + ".Device", "State")).value == 100:
                await device.call_disconnect()
            return {"done": True}

        settings = await self.interface(name, "/org/freedesktop/NetworkManager/Settings", name + ".Settings")
        profiles = {}
        for path in await settings.call_list_connections():
            connection = await self.interface(name, path, name + ".Settings.Connection")
            try:
                config = await connection.call_get_settings()
            except Exception:
                continue  # A system profile may be private to another user.
            if config.get("connection", {}).get("type", Variant("s", "")).value != "802-11-wireless":
                continue
            ssid = bytes(config.get("802-11-wireless", {}).get("ssid", Variant("ay", b"")).value)
            security = config.get("802-11-wireless-security", {}).get("key-mgmt")
            profiles[(ssid, "open" if security is None else "8021x" if security.value == "wpa-eap" else "secured")] = path

        active_ap = (await device_props.call_get(name + ".Device.Wireless", "ActiveAccessPoint")).value
        state = (await device_props.call_get(name + ".Device", "State")).value
        powered = (await manager_props.call_get(name, "WirelessEnabled")).value
        networks, rsn = {}, {}
        for path in await wireless.call_get_all_access_points():
            props = await self.interface(name, path, "org.freedesktop.DBus.Properties")
            ap = await props.call_get_all(name + ".AccessPoint")
            ssid = bytes(ap["Ssid"].value)
            if not ssid:
                continue
            rsn[path] = ap["RsnFlags"].value
            flags = ap["WpaFlags"].value | ap["RsnFlags"].value
            kind = "8021x" if flags & 0x200 else "open" if not (ap["Flags"].value & 1 or flags) else "secured"
            connected = path == active_ap and state == 100
            network = {"path": path, "name": ssid.decode("utf-8", "replace"), "type": kind,
                       "connected": connected, "saved": (ssid, kind) in profiles,
                       "signal": ap["Strength"].value}
            key = (ssid, kind)
            if key not in networks or connected or (not networks[key]["connected"] and network["signal"] > networks[key]["signal"]):
                networks[key] = network
        if action == "list":
            return {"networks": sorted(networks.values(), key=lambda n: (-n["connected"], -n["signal"], n["name"])),
                    "state": "connected" if state == 100 else "disconnected", "powered": powered}

        path = p.get("path", "")
        network = next((n for n in networks.values() if n["path"] == path), None)
        if network is None:
            raise BackendError("invalid", "Select an available network.")
        ssid = bytes((await (await self.interface(name, path, "org.freedesktop.DBus.Properties")).call_get(name + ".AccessPoint", "Ssid")).value)
        profile = profiles.get((ssid, network["type"]))
        if action == "forget":
            if profile is None:
                raise BackendError("invalid", "This network has no saved connection.")
            connection = await self.interface(name, profile, name + ".Settings.Connection")
            await connection.call_delete()
            return {"done": True}
        if action != "connect":
            raise BackendError("invalid", "Unknown wireless operation.")
        if profile:
            active_path = await manager.call_activate_connection(profile, device_path, path)
        else:
            if network["type"] == "8021x":
                raise BackendError("invalid", "Configure enterprise credentials in NetworkManager first.")
            config = {"connection": {"id": Variant("s", network["name"]), "type": Variant("s", "802-11-wireless")},
                      "802-11-wireless": {"ssid": Variant("ay", ssid)}}
            if network["type"] != "open":
                password = p.get("password")
                if not isinstance(password, str) or not password:
                    raise BackendError("invalid", "Enter the Wi-Fi password.")
                config["802-11-wireless-security"] = {"key-mgmt": Variant("s", key_management(rsn[path])), "psk": Variant("s", password)}
            profile, active_path = await manager.call_add_and_activate_connection(config, device_path, path)
        active_props = await self.interface(name, active_path, "org.freedesktop.DBus.Properties")
        for _ in range(60):
            state = (await active_props.call_get(name + ".Connection.Active", "State")).value
            if state == 2:
                return {"done": True}
            if state == 4:
                raise BackendError("failed", "Wi-Fi connection failed. Check the password and try again.")
            await asyncio.sleep(0.5)
        raise BackendError("timeout", "Wi-Fi connection timed out.")

    async def bluetooth_pair(self, p):
        from dbus_next.service import ServiceInterface, method
        from dbus_next import DBusError
        objects = await self.objects("org.bluez")
        path = p.get("path", "")
        if path not in objects or "org.bluez.Device1" not in objects[path]:
            raise BackendError("invalid", "Select an available Bluetooth device.")
        backend = self

        async def prompt(message, input_kind=""):
            backend.pairing_reply = asyncio.get_running_loop().create_future()
            emit("bluetooth.prompt", {"message": message, "input": input_kind})
            try:
                reply = await asyncio.wait_for(backend.pairing_reply, 90)
                if not reply.get("accept"):
                    raise DBusError("org.bluez.Error.Rejected", "Pairing rejected")
                return str(reply.get("value", ""))
            finally:
                backend.pairing_reply = None
                emit("bluetooth.prompt", None)

        class Agent(ServiceInterface):
            def __init__(self):
                super().__init__("org.bluez.Agent1")
            @method()
            async def RequestPinCode(self, device: 'o') -> 's':
                return await prompt("Enter the device PIN", "pin")
            @method()
            async def RequestPasskey(self, device: 'o') -> 'u':
                value = await prompt("Enter the six-digit passkey", "passkey")
                if not value.isdigit() or len(value) > 6:
                    raise DBusError("org.bluez.Error.Rejected", "Invalid passkey")
                return int(value)
            @method()
            async def RequestConfirmation(self, device: 'o', passkey: 'u'):
                await prompt(f"Does the device show {passkey:06d}?")
            @method()
            async def RequestAuthorization(self, device: 'o'):
                await prompt("Allow this device to pair?")
            @method()
            async def AuthorizeService(self, device: 'o', uuid: 's'):
                await prompt("Allow the device to connect this service?")
            @method()
            def DisplayPinCode(self, device: 'o', pincode: 's'):
                emit("bluetooth.prompt", {"message": "Enter PIN " + pincode + " on your device.", "input": ""})
            @method()
            def DisplayPasskey(self, device: 'o', passkey: 'u', entered: 'q'):
                emit("bluetooth.prompt", {"message": f"Enter {passkey:06d} on your device ({entered}/6).", "input": ""})
            @method()
            def Cancel(self):
                if backend.pairing_reply and not backend.pairing_reply.done():
                    backend.pairing_reply.set_result({"accept": False})
                emit("bluetooth.prompt", None)
            @method()
            def Release(self):
                self.Cancel()
        async with self.pairing_lock:
            manager = await self.interface("org.bluez", "/org/bluez", "org.bluez.AgentManager1")
            # Pairing waits for the user to confirm; only the request's own limit applies.
            device = await self.interface("org.bluez", path, "org.bluez.Device1", timeout=None)
            agent_path = "/org/shale/BluetoothAgent"
            self.bus.export(agent_path, Agent())
            registered = False
            try:
                await manager.call_register_agent(agent_path, "KeyboardDisplay")
                registered = True
                await device.call_pair()
                await device.call_connect()
            finally:
                try:
                    if registered:
                        await manager.call_unregister_agent(agent_path)
                finally:
                    self.bus.unexport(agent_path)
                    emit("bluetooth.prompt", None)
            return {"done": True}

    BACKLIGHT = Path("/sys/class/backlight")

    def brightness(self):
        """The built-in panel's backlight, or {"available": False} on machines without one."""
        def preference(device):
            # Firmware (ACPI) and platform interfaces drive the real panel; "raw" GPU devices and
            # acpi_video stand-ins are the fallback, as in the kernel's own backlight selection.
            try:
                kind = (device / "type").read_text().strip()
            except OSError:
                kind = ""
            return ({"firmware": 0, "platform": 1, "raw": 2}.get(kind, 3), device.name)
        for device in sorted(self.BACKLIGHT.glob("*"), key=preference):
            try:
                maximum = int((device / "max_brightness").read_text())
                value = int((device / "brightness").read_text())
                if maximum > 0:
                    return {"available": True, "value": value / maximum, "device": device.name}
            except (OSError, ValueError):
                continue
        return {"available": False}

    def close_activity(self):
        """Stops recording: the open segment ends at the last sample, open windows at reopening."""
        self.activity_snapshot = None
        if self.activity is not None:
            self.activity.db.close()
            self.activity = None

    async def dispatch(self, method, p):
        if method.startswith("activity."):
            if method in ("activity.update", "activity.focus") and migrated_settings()["activityTracking"] != "on":
                self.close_activity()
                return {"tracking": False}
            try:
                if self.activity is None:
                    self.activity = activity.ActivityStore(STATE / "activity.sqlite3")
                if method == "activity.update":
                    self.activity_snapshot = dict(p)
                    return self.activity.ingest({**p, "unlocked": bool(p.get("unlocked")) and not self.activity_locked and not self.activity_sleeping})
                # Weeks start on the shell's locale's first day (0 is Sunday).
                first = p.get("weekStart", 1)
                if method == "activity.overview":
                    return self.activity.overview(first)
                if method == "activity.day":
                    return self.activity.day(str(p.get("date", "")))
                if method == "activity.week":
                    return self.activity.week(str(p.get("date", "")), first)
                if method == "activity.apps":
                    return self.activity.apps(str(p.get("range", "")), str(p.get("date", "")), first)
                if method == "activity.app":
                    return self.activity.app(str(p.get("app", "")), str(p.get("date", "")))
                if method == "activity.pause":
                    if type(p.get("paused")) is not bool:
                        raise ValueError("Choose a tracking state.")
                    return self.activity.pause(p["paused"])
                if method == "activity.clear":
                    return self.activity.clear()
                if method == "activity.focus":
                    return self.activity.add_focus(p.get("start"), p.get("end"))
            except (ValueError, OverflowError, sqlite3.Error) as error:
                raise BackendError("invalid", str(error)) from None
            raise BackendError("invalid", "Unknown activity operation.")
        if method == "capabilities":
            return await self.capabilities()
        if method == "settings.get":
            return migrated_settings()
        if method == "settings.set":
            changes = p.get("settings", p)
            if not isinstance(changes, dict):
                raise BackendError("invalid", "Settings must be an object.")
            # The shell echoes every setting back; shortcuts change only through shortcuts.set, which binds them.
            current = save_settings({key: value for key, value in changes.items() if key != "shortcuts"})
            if current["activityTracking"] != "on":
                self.close_activity()
            return current
        if method == "settings.reset":
            before = settings()
            current = reset_settings(p.get("keys"))
            await self.settings_replaced(before, current)
            return current
        if method == "settings.export":
            return export_settings(p.get("path"))
        if method == "settings.import":
            before = settings()
            result = import_settings(p.get("path"))
            wanted = result.pop("shortcuts")
            if wanted is not None:
                async with self.shortcut_lock:
                    applied = await self.import_shortcuts(wanted)
                (result["applied"] if applied else result["skipped"]).append("shortcuts")
                result["settings"] = settings()
            result["problem"] = await self.settings_replaced(before, result["settings"])
            return result
        if method.startswith("shortcuts."):
            async with self.shortcut_lock:
                return await self.shortcuts(method.removeprefix("shortcuts."), p)
        if method == "wallpaperscom.search":
            try:
                return await asyncio.to_thread(wallpaperscom.search, p.get("query", ""), p.get("page", 1), settings()["wallpaperDirectory"])
            except Exception as exc:
                raise BackendError("wallpaperscom", wallpaperscom.message(exc)) from None
        if method == "wallpaperscom.download":
            async with self.wallhaven_lock:
                try:
                    return await asyncio.to_thread(wallpaperscom.download, p.get("id", ""), p.get("url", ""), p.get("name", ""), settings()["wallpaperDirectory"])
                except Exception as exc:
                    raise BackendError("wallpaperscom", wallpaperscom.message(exc)) from None
        if method == "weather.search":
            try:
                return {"results": await asyncio.to_thread(weather.search, p.get("query", ""))}
            except Exception as exc:
                raise BackendError("weather", weather.message(exc)) from None
        if method == "media.art":
            url = p.get("url")
            if type(url) is not str or not url:
                raise BackendError("invalid", "url must be a non-empty string.")
            try:
                return {"path": await asyncio.to_thread(art.local, url, CACHE / "art")}
            except ValueError as exc:
                raise BackendError("unavailable", str(exc)) from None
            except OSError:
                raise BackendError("failed", "The cover could not be downloaded.") from None
        if method == "weather.get":
            # The caller passes its location and units: settings are saved with a short delay.
            async with self.weather_lock:
                try:
                    return await asyncio.to_thread(weather.forecast, p.get("location", {}), p.get("units", "metric"),
                                                   CACHE / "weather.json", p.get("refresh") is True)
                except Exception as exc:
                    raise BackendError("weather", weather.message(exc)) from None
        if method == "wallhaven.search":
            try:
                return await asyncio.to_thread(wallhaven.search, p.get("query", ""), p.get("page", 1), settings()["wallpaperDirectory"])
            except Exception as exc:
                raise BackendError("wallhaven", wallhaven.message(exc)) from None
        if method == "wallhaven.download":
            async with self.wallhaven_lock:
                try:
                    return await asyncio.to_thread(wallhaven.download, p.get("id", ""), settings()["wallpaperDirectory"])
                except Exception as exc:
                    raise BackendError("wallhaven", wallhaven.message(exc)) from None
        if method == "wallpaper.list":
            result = await asyncio.to_thread(wallpaper.catalog, settings()["wallpaperDirectory"])
            try:
                result["active"] = await self.active_wallpapers()
            except BackendError as exc:
                result["active"] = {}
                result["warning"] = exc.message
            return result
        if method == "wallpaper.active":
            try:
                return {"active": await self.active_wallpapers()}
            except BackendError:
                return {"active": {}}
        if method == "wallpaper.apply":
            async with self.wallpaper_lock:
                result = await wallpaper.apply(run, p.get("path", ""), p.get("monitor", ""), BackendError, await self.wallpaper_daemon())
                state_file = STATE / "wallpapers.json"
                try:
                    saved = json.loads(state_file.read_text())
                    if not isinstance(saved, dict): saved = {}
                except (OSError, ValueError):
                    saved = {}
                saved[result["monitor"]] = result["path"]
                atomic_json(state_file, saved)
                return result
        if method == "wallpaper.restore":
            # Also runs when outputs change: one already showing its wallpaper is left alone, and one
            # that fails doesn't keep the others from being restored.
            restored, failed = [], {}
            try:
                saved = json.loads((STATE / "wallpapers.json").read_text())
            except (OSError, ValueError):
                saved = {}
            if not isinstance(saved, dict) or not saved:
                return {"restored": restored, "failed": failed}
            names = [monitor["name"] for monitor in json.loads((await run("hyprctl", "monitors", "-j")).decode())]
            if not any(name in saved for name in names):
                return {"restored": restored, "failed": failed}
            daemon = await self.wallpaper_daemon()
            async with self.wallpaper_lock:
                # Read again under the lock so a completed user selection wins.
                try:
                    saved = json.loads((STATE / "wallpapers.json").read_text())
                except (OSError, ValueError):
                    saved = {}
                if not isinstance(saved, dict): saved = {}
                try:
                    shown = await wallpaper.active(run, daemon)
                except BackendError:
                    shown = {}
                for name in names:
                    path = saved.get(name)
                    if not isinstance(path, str) or not Path(path).is_file() or shown.get(name) == path:
                        continue
                    try:
                        await wallpaper.apply(run, path, name, BackendError, daemon)
                        restored.append(name)
                    except BackendError as error:
                        failed[name] = error.message
            return {"restored": restored, "failed": failed}
        if method in ("eq.apply", "eq.status"):
            if method == "eq.apply":
                self.eq_requests += 1  # the shell is in charge now; see resume_equalizer
            async with self.eq_lock:
                if method == "eq.apply":
                    if type(p.get("enabled")) is not bool:
                        raise BackendError("invalid", "Choose an equalizer state.")
                    try:
                        bands = equalizer.validate(p.get("bands"))
                    except ValueError as error:
                        raise BackendError("invalid", str(error)) from None
                    await self.apply_equalizer(p["enabled"], bands)
                return self.equalizer.status()
        if method == "session.lockedHint":
            # Tells logind (and hypridle, activity tracking) that the shell's lock screen is up.
            if type(p.get("locked")) is not bool:
                raise BackendError("invalid", "Lock state must be true or false.")
            # One at a time, in the order sent: a slow lock must not land after the unlock that followed it.
            async with self.lock_hint_lock:
                session = await self.interface("org.freedesktop.login1", await self.session_path(), "org.freedesktop.login1.Session")
                await session.call_set_locked_hint(p["locked"])
            return {"locked": p["locked"]}
        if method == "units.convert":
            try:
                return units.convert(p.get("query"))
            except ValueError as error:
                raise BackendError("invalid", str(error)) from None
        if method == "files.search":
            home = Path.home()
            query = p.get("query")
            output = await run(*file_search_args(query, home), timeout=3)
            return {"results": file_results(output, query, home)}
        if method == "calculator":
            return calculate(p.get("expression", ""))
        if method.startswith("wifi."):
            action = method.split(".")[1]
            if action == "connect":
                if self.wifi_lock.locked():
                    raise BackendError("busy", "A Wi-Fi connection is already in progress.")
                async with self.wifi_lock:
                    return await self.wifi(action, p)
            if action == "list":
                # Wired desktops and iwd/networkd setups have no NetworkManager Wi-Fi: say so as a
                # state, not an error, so the shell hides Wi-Fi instead of reporting a failure.
                try:
                    return {"available": True, **await self.wifi(action, p)}
                except BackendError as error:
                    if error.code != "unavailable":
                        raise
                    reason = error.message
                except Exception as error:
                    # Only a NetworkManager that isn't on the bus means "no Wi-Fi here"; a timeout or other
                    # one-off failure stays an error, so the shell keeps the state it last knew.
                    if getattr(error, "type", "") not in ("org.freedesktop.DBus.Error.ServiceUnknown", "org.freedesktop.DBus.Error.NameHasNoOwner"):
                        raise
                    reason = "NetworkManager is not running."
                return {"available": False, "reason": reason, "networks": [], "state": "unavailable", "powered": False}
            return await self.wifi(action, p)
        if method.startswith("vpn."):
            action = method.split(".")[1]
            if action == "list":
                try:
                    return {"available": True, **await self.vpn(action, p)}
                except BackendError as error:
                    if error.code != "unavailable":
                        raise
                except Exception as error:
                    if getattr(error, "type", "") not in ("org.freedesktop.DBus.Error.ServiceUnknown", "org.freedesktop.DBus.Error.NameHasNoOwner"):
                        raise
                return {"available": False, "connections": []}
            if self.vpn_lock.locked():
                raise BackendError("busy", "A VPN change is already in progress.")
            async with self.vpn_lock:
                return await self.vpn(action, p)
        if method == "tray.quit":
            if not isinstance(p.get("id"), str) or not p["id"] or not isinstance(p.get("title", ""), str):
                raise BackendError("invalid", "Choose a tray app.")
            pid = await tray_owner(self.session_call, p["id"], p.get("title", ""))
            return await quit_process(pid)
        if method == "bluetooth.pair":
            return await self.bluetooth_pair(p)
        if method == "bluetooth.reply":
            if self.pairing_reply and not self.pairing_reply.done():
                self.pairing_reply.set_result(p)
            return {"done": True}
        if method == "display.lid.get":
            return {"enabled": self.lid_fd is not None}
        if method == "display.lid.toggle":
            async with self.lid_lock:
                if self.lid_fd is not None:
                    os.close(self.lid_fd)
                    self.lid_fd = None
                else:
                    manager = await self.interface("org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager")
                    fd = await manager.call_inhibit("handle-lid-switch", "Shale", "Keep laptop awake with lid closed", "block")
                    if not isinstance(fd, int) or fd < 0:
                        raise BackendError("failed", "Could not keep the laptop awake.")
                    os.set_inheritable(fd, False)
                    self.lid_fd = fd
                return {"enabled": self.lid_fd is not None}
        if method in ("display.grayscale.get", "display.grayscale.toggle"):
            shader = str(Path(__file__).resolve().parents[1] / "assets/grayscale.frag")
            current = json.loads(await run("hyprctl", "getoption", "decoration:screen_shader", "-j"))["str"]
            enabled = current == shader
            if method.endswith(".toggle"):
                saved = RUNTIME / "grayscale.json"
                if enabled:
                    try:
                        previous = json.loads(saved.read_text()).get("previous", "")
                    except (FileNotFoundError, ValueError):
                        previous = ""
                    target = previous
                else:
                    atomic_json(saved, {"previous": "" if current == "[[EMPTY]]" else current})
                    target = shader
                # Lua byte escapes preserve paths without allowing Lua code injection.
                literal = '"' + ''.join(f'\\{byte:03d}' for byte in target.encode()) + '"'
                result = (await run("hyprctl", "eval", 'hl.config({decoration = {screen_shader = ' + literal + '}})')).decode().strip()
                if result != "ok":
                    raise BackendError("failed", "Could not change the screen shader.")
                actual = json.loads(await run("hyprctl", "getoption", "decoration:screen_shader", "-j"))["str"]
                enabled = actual == shader
            return {"enabled": enabled}
        if method in ("keyboard.get", "keyboard.next"):
            if method == "keyboard.next":
                # Every keyboard, so an external one and the laptop's never disagree.
                await run("hyprctl", "switchxkblayout", "all", "next")
            return keyboard_state(json.loads(await run("hyprctl", "devices", "-j")))
        if method == "brightness.get":
            return self.brightness()
        if method == "brightness.set":
            value = number(p, "value", 0)
            current = self.brightness()
            if not current["available"]:
                raise BackendError("unavailable", "No laptop backlight is available.")
            device = current["device"]
            await run("brightnessctl", "-d", device, "set", str(max(1, min(100, round(value * 100)))) + "%")
            return self.brightness()
        if method == "clipboard.write":
            await run("wl-copy", data=str(p.get("text", "")).encode())
            return {"done": True}
        if method == "clipboard.thumbnail":
            entry = str(p.get("entry", ""))
            identity = entry.partition("\t")[0]
            if not identity.isdigit() or "\n" in entry:
                raise BackendError("invalid", "Select a clipboard entry.")
            wipes = self.clipboard_wipes
            data = await run("cliphist", "decode", data=entry.encode())
            if identity in self.clipboard_deleted or wipes != self.clipboard_wipes:
                return {"path": ""}
            extension = ".png" if data.startswith(b"\x89PNG\r\n\x1a\n") else ".jpg" if data.startswith(b"\xff\xd8\xff") else None
            if extension is None or len(data) > 20 * 1024 * 1024:
                return {"path": ""}
            folder = CACHE / "clipboard"
            folder.mkdir(parents=True, exist_ok=True, mode=0o700)
            for stale in sorted(folder.glob("*"), key=modified, reverse=True)[31:]:
                stale.unlink(missing_ok=True)
            path = folder / (identity + extension)
            path.write_bytes(data)
            path.chmod(0o600)
            return {"path": str(path)}
        if method == "notifications.get":
            if not settings()["persistNotifications"]:
                return {"entries": []}
            try:
                history = json.loads((STATE / "notifications.json").read_text())
            except (OSError, ValueError):
                history = []
            cutoff = (time.time() - 7 * 86400) * 1000
            return {"entries": [x for x in history if isinstance(x, dict) and x.get("timestamp", 0) > cutoff][:200]}
        if method == "notifications.set":
            path = STATE / "notifications.json"
            if not settings()["persistNotifications"]:
                path.unlink(missing_ok=True)
                return {"done": True}
            entries = p.get("entries", [])
            if not isinstance(entries, list):
                raise BackendError("invalid", "Expected notification entries.")
            cutoff = (time.time() - 7 * 86400) * 1000
            allowed = ("id", "summary", "body", "appName", "appIcon", "urgency", "timestamp")
            atomic_json(path, [{k: x[k] for k in allowed if k in x} for x in entries[:200] if isinstance(x, dict) and x.get("timestamp", 0) > cutoff])
            return {"done": True}
        if method == "power.compositor":
            return await self.compositor_saver(bool(p.get("saver")), bool(p.get("refresh", True)))
        if method.startswith("power."):
            # tuned-ppd serves these properties but omits them from introspection.
            # Read the standard Properties interface instead of generated accessors.
            name = "net.hadess.PowerProfiles"
            interface = await self.interface(name, "/net/hadess/PowerProfiles", "org.freedesktop.DBus.Properties")
            properties = await interface.call_get_all(name)
            available = [x["Profile"].value for x in properties["Profiles"].value]
            if method == "power.set":
                profile = p.get("profile")
                if profile not in available:
                    raise BackendError("invalid", "Select an available power profile.")
                from dbus_next import Variant
                await interface.call_set(name, "ActiveProfile", Variant("s", profile))
                properties = await interface.call_get_all(name)
            try:
                tuned = "=shale-" in Path("/etc/tuned/ppd.conf").read_text()
            except OSError:
                tuned = None  # not tuned-ppd (e.g. power-profiles-daemon): Shale's profiles don't apply
            return {"active": properties["ActiveProfile"].value, "profiles": available, "tuned": tuned}
        if method == "clipboard.list":
            data = (await run("cliphist", "list")).decode(errors="replace")
            query = str(p.get("query", "")).casefold()
            limit = min(1000, max(1, int(number(p, "limit", 100))))
            entries = []
            for line in data.splitlines():
                identity, _, text = line.partition("\t")
                if query in text.casefold():
                    entry = {"id": identity, "text": text, "raw": line}
                    label = clipboard_label(text)
                    if label:
                        entry["label"] = label
                    entries.append(entry)
                if len(entries) >= limit:
                    break
            paths = []
            for entry in entries:
                text = entry["text"].strip()
                if "label" in entry:
                    continue
                if kind := clipboard_kind(text):
                    entry.update(kind)
                elif text.startswith(("/", "~/", "file://")) and not text.endswith("…"):
                    paths.append((entry, text))
            if paths:
                try:
                    kinds = await asyncio.wait_for(asyncio.to_thread(path_kinds, [text for _, text in paths]), 1)
                except asyncio.TimeoutError:
                    # A hung network mount must not hold up the list; paths just go unmarked.
                    kinds = []
                for (entry, _), kind in zip(paths, kinds):
                    if kind:
                        entry.update(kind)
            return {"entries": entries}
        if method in ("clipboard.copy", "clipboard.delete", "clipboard.open"):
            entry = str(p.get("entry", ""))
            if not entry.partition("\t")[0].isdigit() or "\n" in entry:
                raise BackendError("invalid", "Select a clipboard entry.")
            data = await run("cliphist", "delete" if method.endswith("delete") else "decode", data=entry.encode())
            if method.endswith("delete"):
                # The preview is a full copy of the image; it goes with the entry.
                identity = entry.partition("\t")[0]
                self.clipboard_deleted.add(identity)
                for extension in (".png", ".jpg"):
                    (CACHE / "clipboard" / (identity + extension)).unlink(missing_ok=True)
            if method.endswith("open"):
                # Previews are cut and flattened, so the full entry decides what opens.
                try:
                    text = data.decode().strip() if len(data) <= 65536 else ""
                except UnicodeDecodeError:
                    text = ""
                try:
                    target = await asyncio.wait_for(asyncio.to_thread(clipboard_target, text), 3)
                except asyncio.TimeoutError:
                    raise BackendError("failed", "That location isn't responding.")
                if not target:
                    raise BackendError("invalid", "This entry can't be opened.")
                return target
            if method.endswith("copy"):
                await run("wl-copy", data=data)
            return {"done": True}
        if method == "clipboard.clear":
            await run("cliphist", "wipe")
            self.clipboard_wipes += 1
            shutil.rmtree(CACHE / "clipboard", ignore_errors=True)
            return {"done": True}
        if method == "color.pick":
            value = (await run("hyprpicker", "--format", "hex", timeout=120, cancel_ok=True)).decode().strip()
            await run("wl-copy", data=value.encode())
            return {"color": value}
        if method == "system.sample":
            return await self.sysmon.sample(nvidia=p.get("nvidia") is True, history=p.get("history") is True)
        if method == "capture.screenshot":
            async with self.capture_lock:
                return await self.screenshot(p)
        if method.startswith("capture.record."):
            action = method.rsplit(".", 1)[1]
            if action == "start":
                async with self.capture_lock:
                    return await self.record(action, p)
            return await self.record(action, p)
        raise BackendError("invalid", "Unknown backend method.")

    async def geometry(self, mode):
        if mode == "region":
            return ["-g", (await run("slurp", timeout=120, cancel_ok=True)).decode().strip()]
        if mode == "window":
            window = json.loads(await run("hyprctl", "-j", "activewindow"))
            if not window.get("at") or not window.get("size"):
                raise BackendError("unavailable", "No active window.")
            x, y = window["at"]
            w, h = window["size"]
            return ["-g", f"{x},{y} {w}x{h}"]
        if mode == "output":
            outputs = json.loads(await run("hyprctl", "-j", "monitors"))
            output = next((x for x in outputs if x.get("focused")), None)
            if not output:
                raise BackendError("unavailable", "No focused output.")
            return ["-o", output["name"]]
        raise BackendError("invalid", "Choose region, output, or window capture.")

    async def screenshot(self, p):
        await asyncio.sleep(min(10, max(0.2, number(p, "delay", 0.2))))
        args = await self.geometry(p.get("mode", "region"))
        folder = Path(settings()["screenshotDirectory"]).expanduser()
        folder.mkdir(parents=True, exist_ok=True)
        path = folder / (datetime.datetime.now().strftime("Screenshot-%Y%m%d-%H%M%S-%f") + ".png")
        await run("grim", *args, str(path))
        copied = False
        if p.get("copy", True):
            # The saved file is the result; the clipboard copy is a convenience that may be missing.
            try:
                await run("wl-copy", "--type", "image/png", data=path.read_bytes())
                copied = True
            except BackendError:
                pass
        return {"path": str(path), "copied": copied}

    async def record(self, action, p):
        RUNTIME.mkdir(parents=True, exist_ok=True, mode=0o700)
        state_path = RUNTIME / "recording.json"
        try:
            state = json.loads(state_path.read_text())
            alive = Path(f"/proc/{state['pid']}/cmdline").read_bytes()
            active = b"record-worker" in alive and b"backend.py" in alive
        except (OSError, ValueError, KeyError):
            state, active = {}, False
        if action == "status":
            return {**state, "active": active}
        if action == "stop":
            if active:
                os.kill(state["pid"], signal.SIGTERM)
                for _ in range(50):
                    await asyncio.sleep(0.1)
                    try:
                        latest = json.loads(state_path.read_text())
                        if not latest.get("active", False):
                            return latest
                    except (OSError, ValueError):
                        pass
                raise BackendError("timeout", "Recording is still finalizing. Check status before starting another recording.")
            return {**state, "active": False}
        if action != "start":
            raise BackendError("invalid", "Unknown recording operation.")
        if active:
            raise BackendError("busy", "A recording is already running.")
        if not shutil.which("wf-recorder"):
            raise BackendError("unavailable", "Install wf-recorder to record the screen.")
        audio = record_audio(p.get("audio", "none"))
        args = await self.geometry(p.get("mode", "output"))
        folder = Path(settings()["recordingDirectory"]).expanduser()
        folder.mkdir(parents=True, exist_ok=True)
        path = folder / (datetime.datetime.now().strftime("Recording-%Y%m%d-%H%M%S-%f") + ".mp4")
        command = ["wf-recorder", *args, "-f", str(path)]
        if RECORD_AUDIO[audio]:
            command.append("--audio=" + RECORD_AUDIO[audio])
        # A detached process would remain in the shell's systemd cgroup and die
        # on restart. Give recording its own transient user unit instead.
        unit = ["systemd-run", "--user", "--quiet", "--collect", "--unit=shale-recording",
                "--property=PartOf=graphical-session.target", "--property=KillMode=mixed", "--property=TimeoutStopSec=15"]
        for key in ("WAYLAND_DISPLAY", "XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS", "HYPRLAND_INSTANCE_SIGNATURE"):
            if os.environ.get(key):
                unit.append("--setenv=" + key + "=" + os.environ[key])
        await run(*unit, sys.executable, str(Path(__file__).resolve()), "record-worker", json.dumps(command), str(path))
        for _ in range(30):
            await asyncio.sleep(0.1)
            try:
                current = json.loads(state_path.read_text())
                if current.get("path") == str(path):
                    if current.get("active"):
                        return current
                    raise BackendError("failed", "Recorder failed to start. See journalctl --user -u shale-recording.")
            except (OSError, ValueError):
                pass
        raise BackendError("timeout", "Recorder startup is taking longer than expected. Check recording status.")

def record_worker(command, path):
    """Own the recorder independently of the QML/UI process, and finalize on stop."""
    import fcntl
    RUNTIME.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (RUNTIME / "recording.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 1
        child = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        state = {"pid": os.getpid(), "path": path, "started": time.time(), "active": True}
        def stop(*_):
            if child.poll() is None:
                child.send_signal(signal.SIGINT)
        signal.signal(signal.SIGTERM, stop)
        signal.signal(signal.SIGINT, stop)
        atomic_json(RUNTIME / "recording.json", state)
        code = child.wait()
        atomic_json(RUNTIME / "recording.json", {**state, "active": False, "saved": Path(path).is_file() and Path(path).stat().st_size > 0})
        return code

async def keep_clipboard_history(clipboard, interval=30):
    # Re-checks so a watcher the user starts later wins, and a crashed one of ours comes back.
    while True:
        try:
            clipboard.ensure()
        except OSError as error:
            print("Clipboard history: could not start a watcher:", error.strerror or error, file=sys.stderr, flush=True)
        await asyncio.sleep(interval)

async def keep_system_history(backend):
    """Keeps the system monitor's graphs going while its panel is closed, so it opens on the last few minutes.
    A few /proc reads every 2 s (4 s in power saver); nothing while the session is locked or suspending."""
    reported = False
    while True:
        interval = 4 if backend.power_saver else 2
        await asyncio.sleep(interval)
        if backend.activity_locked or backend.activity_sleeping:
            continue
        try:
            await backend.sysmon.tick()
        except Exception as error:
            if not reported:
                log_unexpected(error, "System history")
                reported = True

class BacklightWatch:
    """Calls `changed` when the kernel announces a new brightness for a backlight. Every change made through
    sysfs (brightnessctl, logind) or by brightness hotkeys is announced on actual_brightness."""
    def __init__(self, device, changed):
        self.device, self.changed, self.closed, self.poll = device, changed, False, None
        self.file = open(device / "actual_brightness", "rb", buffering=0)
        try:
            self.file.read()  # a sysfs file's notice is armed by reading it
            self.poll = select.epoll()
            self.poll.register(self.file.fileno(), select.EPOLLPRI | select.EPOLLERR)
            asyncio.get_running_loop().add_reader(self.poll.fileno(), self.ready)
        except BaseException:
            if self.poll:
                self.poll.close()
            self.file.close()
            raise

    def ready(self):
        try:
            self.poll.poll(0)
            # Reading again re-arms the notice; without it the file stays ready and this would spin.
            self.file.seek(0)
            self.file.read()
        except OSError:
            self.close()  # the device went away; the watcher looks for it again
        self.changed()

    def close(self):
        if self.closed:
            return
        self.closed = True
        asyncio.get_running_loop().remove_reader(self.poll.fileno())
        self.poll.close()
        self.file.close()


async def watch_brightness(backend, recheck=10, poll=1, unavailable=30):
    """Reports the backlight level as it changes: on the kernel's notice where it gives one, otherwise by
    polling every `poll` seconds. The slow `recheck` covers drivers that change it without a notice."""
    previous, watch, changed = None, None, asyncio.Event()
    try:
        while True:
            value = backend.brightness()
            if value != previous:
                emit("brightness", {**value, "initial": previous is None})
                previous = value
            device = backend.BACKLIGHT / value["device"] if value["available"] else None
            if watch and (watch.closed or watch.device != device):
                watch.close()
                watch = None
            if device and not watch:
                try:
                    watch = BacklightWatch(device, changed.set)
                except OSError:
                    pass
            changed.clear()
            # Machines without a backlight rarely gain one; check far less often.
            delay = recheck if watch else poll if device else unavailable
            try:
                await asyncio.wait_for(changed.wait(), delay)
            except asyncio.TimeoutError:
                pass
    finally:
        if watch:
            watch.close()


async def watch_with_retries(name, setup, delays=(5, 10, 30, 60, 120, 300)):
    """Sets up a D-Bus watch, again after each delay while it fails: the service may start after the shell."""
    for delay in (0, *delays):
        await asyncio.sleep(delay)
        try:
            return await setup()
        except BackendError as error:
            print(f"{name}: {error.message}", file=sys.stderr, flush=True)
            if error.code != "timeout":
                return  # no python-dbus-next or no logind session: trying again won't help
        except Exception as error:
            if getattr(error, "type", "") not in SERVICE_MISSING:
                log_unexpected(error, name)

async def main():
    backend = Backend()
    tasks = set()
    async def watch_session():
        """Gate activity at external locks and immediately before suspend. Until it works, the shell's
        own lock state and monotonic gap detection remain available."""
        manager = await backend.interface("org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager")
        path = await backend.session_path()
        props = await backend.interface("org.freedesktop.login1", path, "org.freedesktop.DBus.Properties")
        backend.activity_locked = bool((await props.call_get("org.freedesktop.login1.Session", "LockedHint")).value)
        def resample():
            # Only while recording is on: a change saved some other way (an import) may have turned it off.
            if backend.activity and settings()["activityTracking"] != "on":
                backend.close_activity()
            if backend.activity and backend.activity_snapshot:
                snap = backend.activity_snapshot
                backend.activity.ingest({**snap, "unlocked": bool(snap.get("unlocked")) and not backend.activity_locked and not backend.activity_sleeping})
        def on_properties(interface, changed, _invalidated):
            if interface == "org.freedesktop.login1.Session" and "LockedHint" in changed:
                backend.activity_locked = bool(changed["LockedHint"].value)
                resample()
        def on_sleep(sleeping):
            backend.activity_sleeping = bool(sleeping)
            resample()
        props.on_properties_changed(on_properties)
        manager.on_prepare_for_sleep(on_sleep)
    async def watch_power():
        """Report power-mode changes made anywhere (shell, powerprofilesctl, tuned-ppd battery rules).
        Until it works, the shell keeps polling on its power page."""
        props = await backend.interface("net.hadess.PowerProfiles", "/net/hadess/PowerProfiles", "org.freedesktop.DBus.Properties")
        def on_properties(interface, changed, _invalidated):
            if "ActiveProfile" in changed:
                backend.power_saver = changed["ActiveProfile"].value == "power-saver"
                emit("power.profile", {"active": changed["ActiveProfile"].value})
        props.on_properties_changed(on_properties)
        backend.power_saver = (await props.call_get("net.hadess.PowerProfiles", "ActiveProfile")).value == "power-saver"
    async def handle(line):
        identity = method = None
        try:
            request = json.loads(line)
            identity = request.get("id")
            method, params = request.get("method"), request.get("params", {})
            if not isinstance(method, str) or not isinstance(params, dict):
                raise BackendError("invalid", "Expected a method string and params object.")
            result = await asyncio.wait_for(backend.dispatch(method, params), timeout=150)
            response = {"id": identity, "ok": True, "result": result}
        except BackendError as error:
            response = {"id": identity, "ok": False, "error": {"code": error.code, "message": error.message}}
        except asyncio.TimeoutError:
            response = {"id": identity, "ok": False, "error": {"code": "timeout", "message": "The operation timed out."}}
        except Exception as error:
            # D-Bus exception text can contain credentials or device data: expose only its stable type.
            error_type = str(getattr(error, "type", ""))
            code = "permission" if "AccessDenied" in error_type else "failed"
            message = "The operation failed. Check service availability and permissions."
            if "ServiceUnknown" in error_type or "NameHasNoOwner" in error_type:
                code, message = "unavailable", "The required system service is not running."
            elif "InvalidKey" in error_type or "AuthenticationFailed" in error_type:
                code, message = "authentication", "Authentication failed. Check the password and try again."
            elif "Canceled" in error_type or "Cancelled" in error_type:
                code, message = "cancelled", "Action cancelled."
            if code == "failed":
                log_unexpected(error, method if isinstance(method, str) else "Request")
            response = {"id": identity, "ok": False, "error": {"code": code, "message": message}}
        print(json.dumps(response, ensure_ascii=False), flush=True)

    async def keep_equalizer():
        backend.equalizer.reap_stale()
        # PipeWire may still be starting with the session: a few attempts over about 30 seconds.
        if not await backend.resume_equalizer((0, 2, 4, 8, 16)):
            emit("eq", backend.equalizer.status())
        while True:
            await asyncio.sleep(5)
            await backend.check_equalizer()

    clipboard = clipboard_watch.ClipboardWatcher()

    def leave_recording():
        """A shell that stops while Settings records a shortcut must not leave every binding off."""
        if backend.record_timeout:
            backend.record_timeout.cancel()
            try:
                subprocess.run(["hyprctl", "eval", 'if hl.get_current_submap() == "' + shortcuts.RECORD_SUBMAP
                                + '" then hl.dispatch(hl.dsp.submap("reset")) end'], capture_output=True, timeout=2)
            except (OSError, subprocess.SubprocessError):
                pass

    def terminate():
        # The filter is a separate PipeWire client; do not leave it running without the shell.
        backend.equalizer.stop()
        leave_recording()
        clipboard.stop()
        signal.signal(signal.SIGTERM, signal.SIG_DFL)
        os.kill(os.getpid(), signal.SIGTERM)

    asyncio.get_running_loop().add_signal_handler(signal.SIGTERM, terminate)
    watcher = asyncio.create_task(watch_brightness(backend))
    equalizer_keeper = asyncio.create_task(keep_equalizer())
    session_watcher = asyncio.create_task(watch_with_retries("Session watch", watch_session))
    power_watcher = asyncio.create_task(watch_with_retries("Power profile watch", watch_power))
    clipboard_keeper = asyncio.create_task(keep_clipboard_history(clipboard))
    system_keeper = asyncio.create_task(keep_system_history(backend))
    reader = asyncio.StreamReader(limit=1024 * 1024 + 1)
    transport, _ = await asyncio.get_running_loop().connect_read_pipe(lambda: asyncio.StreamReaderProtocol(reader), sys.stdin)
    try:
        while True:
            line = await read_request(reader)
            if not line:
                break
            if isinstance(line, tuple):
                print(json.dumps({"id": line[1], "ok": False, "error": {"code": "invalid", "message": "Request is too large."}}), flush=True)
                continue
            if len(tasks) >= 32:
                await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
            task = asyncio.create_task(handle(line))
            tasks.add(task)
            task.add_done_callback(tasks.discard)
        if tasks:
            await asyncio.gather(*tasks)
    finally:
        watcher.cancel()
        session_watcher.cancel()
        power_watcher.cancel()
        clipboard_keeper.cancel()
        system_keeper.cancel()
        equalizer_keeper.cancel()
        backend.equalizer.stop()
        clipboard.stop()
        leave_recording()
        transport.close()
    if backend.bus:
        backend.bus.disconnect()

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "record-worker":
        sys.exit(record_worker(json.loads(sys.argv[2]), sys.argv[3]))
    asyncio.run(main())
