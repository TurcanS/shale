#!/usr/bin/env python3
"""Shale JSON-lines backend. Credentials and clipboard data never enter logs."""
import ast
import asyncio
from concurrent.futures import ThreadPoolExecutor
import datetime
import hashlib
import importlib.util
import ipaddress
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
import struct
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
import bluetooth_keep
import clipboard_watch
import equalizer
import displays
import weather
import units
import shortcuts
import update

def airdrop_command():
    """The `airdrop` CLI (AirDrop for Linux) as an absolute path, or "" when it isn't installed. ~/.local/bin is often
    missing from a compositor's PATH, so it is looked in as well."""
    found = shutil.which("airdrop")
    if found:
        return found
    local = Path.home() / ".local/bin/airdrop"
    return str(local) if os.access(local, os.X_OK) else ""


# What a file is, for an icon: by its extension, as AirDrop's own sheet does.
FILE_KINDS = {"image": ("jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "avif", "bmp", "tif", "tiff", "svg", "raw", "dng"),
              "video": ("mp4", "mov", "m4v", "mkv", "webm", "avi", "hevc"),
              "audio": ("mp3", "m4a", "aac", "flac", "wav", "ogg", "opus"),
              "pdf": ("pdf",),
              "archive": ("zip", "tar", "gz", "xz", "zst", "7z", "rar", "bz2"),
              "text": ("txt", "md", "rtf", "doc", "docx", "odt", "pages", "csv", "json", "log")}


def file_kind(path):
    if path.is_dir():
        return "folder"
    ext = path.suffix.lower().lstrip(".")
    return next((kind for kind, exts in FILE_KINDS.items() if ext in exts), "file")


def staged_item(text):
    """One file or folder picked for AirDrop: its name, size (a folder's files, counted up to 20000 of them) and kind.
    None when it is not an existing absolute path."""
    if not isinstance(text, str) or not text.startswith("/") or "\0" in text or len(text) > 4096:
        return None
    path = Path(text)
    try:
        if not path.exists():
            return None
        size = 0
        if path.is_dir():
            for count, child in enumerate(path.rglob("*")):
                if count >= 20000:
                    break
                if child.is_file() and not child.is_symlink():
                    size += child.stat().st_size
        else:
            size = path.stat().st_size
    except OSError:
        return None
    return {"path": str(path), "name": path.name or str(path), "size": size, "dir": path.is_dir(), "kind": file_kind(path)}


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

DEFAULTS = {"version": 1, "reducedMotion": False, "motion": "lively", "clock24h": True,
            "dnd": False, "amplification": False, "persistNotifications": False,
            "fontSize": 14, "panelSize": 85, "batterySaving": False, "saverRefresh": True, "windowPreviews": True,
            "hideFullscreen": True, "hiddenOutputs": [], "pinnedApps": [], "appUsage": {}, "captureDelay": 0,
            "accentColor": "#9ad6c6", "surfaceTone": "charcoal", "accentFromWallpaper": False, "accentManual": "#9ad6c6",
            "eqEnabled": False, "eqPreset": "flat", "eqBands": [0] * len(equalizer.BANDS), "visualizer": True, "barMedia": True, "trackChangeCard": True, "mediaRemaining": False,
            "weatherLocation": {}, "weatherUnits": "metric", "updateCheck": True, "emojiUsage": {}, "searchEngine": "duckduckgo", "lockScreen": "builtin", "lockStyle": "particles", "bluetoothAutoConnect": [],
            "recordAudio": "none", "activityTracking": "ask", "systemWindow": 60,
            "focusMinutes": 25, "focusSession": {}, "timers": [], "runHistory": [],
            "widgets": False, "widgetCards": ["clock", "sky", "note", "system"], "widgetSaved": [], "widgetCorner": "bottom-left",
            "barLayout": {}, "controlLayout": {}, "clockFormat": "date-time", "clockSeconds": False, "workspaceStyle": "dots",
            "workspaceSlots": 0, "trayIcons": -1, "batteryPercent": "auto", "barStyle": "floating", "weekStart": "locale", "terminal": "auto", "shortcuts": {},
            "screenshotDirectory": user_dir("PICTURES", "~/Pictures") + "/Screenshots",
            "recordingDirectory": user_dir("VIDEOS", "~/Videos") + "/Recordings",
            "wallpaperDirectory": user_dir("PICTURES", "~/Pictures") + "/Wallpapers", "wallpaperFit": "cover", "activityKeep": 0, "quietHours": [],
            "airdropMode": "off", "airdropAsk": "ask", "airdropTimeout": 60,
            "airdropFolder": user_dir("DOWNLOAD", "~/Downloads") + "/AirDrop"}
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "shale/config.json"
RUNTIME = runtime_base() / "shale"
STATE = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "shale"
CACHE = Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "shale"
# The installed shell folder: the installer records the commit it installed (and its checkout) there.
SHELL_FOLDER = Path(__file__).resolve().parents[1]
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
BAR_ITEMS = ("workspaces", "windowTitle", "clock", "media", "tray", "recording", "privacy", "focus", "timer",
             "stayAwake", "airdrop", "keyboard", "vpn", "wifi", "audio", "battery", "notifications", "control",
             # No longer on the bar, but layouts saved before may still list them; the shell skips them.
             "launcher", "wallpapers", "lock")
# Never hidden: what is recording or listening stays visible, and the control center leads back to Settings.
BAR_REQUIRED = ("recording", "privacy", "control")
CONTROL_TILES = ("wifi", "bluetooth", "airdrop", "dnd", "awake", "grayscale", "lid")
CONTROL_SECTIONS = ("focus", "levels", "media")
CONTROL_FOOTER = ("capture", "settings", "lock", "session")
# Desktop widget cards, as core/parts.js names them, and the corners they can sit in.
WIDGET_CARDS = ("clock", "sky", "note", "system", "player", "timers")
WIDGET_CORNERS = ("top-left", "top-right", "bottom-left", "bottom-right")
MAX_WIDGET_CARDS = 6
# Personal history and state, and this computer's folders and screens; a settings export leaves them out and an
# import ignores them, so a file from elsewhere can't redirect where screenshots, recordings or downloads are saved,
# hide a bar here, or turn activity recording on without the question the Activity panel asks.
PRIVATE_KEYS = ("appUsage", "emojiUsage", "runHistory", "pinnedApps", "focusSession", "timers", "weatherLocation",
                "screenshotDirectory", "recordingDirectory", "wallpaperDirectory", "airdropFolder", "bluetoothAutoConnect",
                "activityTracking", "hiddenOutputs")
# What a restore of the settings from before leaves as it is now: shortcuts are bound in the compositor, and a
# session or timer from then would be stale.
RESTORE_KEEPS = ("shortcuts", "focusSession", "timers")
# How each terminal takes a command to run; $TERMINAL is assumed to follow the common -e convention.
TERMINALS = (("xdg-terminal-exec",), ("foot",), ("kitty",), ("alacritty", "-e"), ("wezterm", "start", "--"),
             ("ghostty", "-e"), ("konsole", "-e"), ("gnome-terminal", "--"))
ACTIVITY_TRACKING = ("ask", "on", "off")
# Days of activity kept; 0 keeps everything until it is cleared.
ACTIVITY_KEEP = (0, 30, 90, 365)
# AirDrop (the optional `airdrop` command): what runs when the shell starts (Visible is never restored, it is for ten
# minutes at a time), whether to ask before saving, and how long a question waits before it declines.
AIRDROP_MODES = ("off", "background")
AIRDROP_ASK = ("ask", "all")
AIRDROP_TIMEOUTS = (30, 60, 120, 300)

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
    if path.parent == STATE and path.parent.stat().st_mode & 0o077:
        path.parent.chmod(0o700)  # made by an earlier installer with the usual permissions
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

def check_names(value, count, length):
    """A list of up to `count` different, non-empty strings of up to `length` characters."""
    return (len(value) <= count and all(isinstance(item, str) and 0 < len(item) <= length for item in value)
            and len(set(value)) == len(value))

def check_counts(value, count, length):
    """How often something was used: up to `count` names, each with a whole number up to 1000 (the shell's cap)."""
    return len(value) <= count and all(isinstance(name, str) and 0 < len(name) <= length and type(uses) is int
                                       and 0 <= uses <= 1000 for name, uses in value.items())

def check_setting(key, value):
    """Raises an "invalid" error for a value of a known setting that the shell can't use."""
    if type(value) is not type(DEFAULTS[key]):
        raise BackendError("invalid", f"Incorrect type for {key}.")
    if key == "version" and value != 1:
        raise BackendError("invalid", "Unsupported settings version.")
    if key == "fontSize" and value not in (12, 14, 16, 18):
        raise BackendError("invalid", "Choose a supported text size.")
    if key == "panelSize" and value not in (80, 85, 90, 100):
        raise BackendError("invalid", "Choose a supported panel size.")
    if key == "captureDelay" and value not in (0, 3, 5, 10):
        raise BackendError("invalid", "Choose a supported capture delay.")
    if key == "surfaceTone" and value not in ("charcoal", "midnight", "warm"):
        raise BackendError("invalid", "Choose a supported surface tone.")
    if key == "motion" and value not in ("calm", "lively", "playful"):
        raise BackendError("invalid", "Choose Calm, Lively or Playful motion.")
    if key in ("accentColor", "accentManual") and ((luminance := accent_luminance(value)) is None or luminance < 0.28):
        raise BackendError("invalid", "Choose a brighter six-digit hex colour.")
    if key == "airdropMode" and value not in AIRDROP_MODES:
        raise BackendError("invalid", "Choose Off or Background for AirDrop.")
    if key == "airdropAsk" and value not in AIRDROP_ASK:
        raise BackendError("invalid", "Choose whether AirDrop asks first.")
    if key == "airdropTimeout" and value not in AIRDROP_TIMEOUTS:
        raise BackendError("invalid", "Choose how long AirDrop waits for an answer.")
    if key in ("screenshotDirectory", "recordingDirectory", "wallpaperDirectory", "airdropFolder") and (
            not (value.startswith("~/") or value.startswith("/")) or re.search(r"[\0\r\n]", value) or len(value) > 4096):
        raise BackendError("invalid", "Folders must be absolute paths or start with ~/.")
    if key == "wallpaperFit" and value not in wallpaper.FITS:
        raise BackendError("invalid", "Choose how the wallpaper fits the screen.")
    # [from, to] in whole hours; [] when off. 22 to 7 runs over midnight.
    if key == "quietHours" and value and not (len(value) == 2 and all(type(hour) is int and 0 <= hour <= 23 for hour in value)
                                               and value[0] != value[1]):
        raise BackendError("invalid", "Choose when quiet hours start and end.")
    if key == "activityKeep" and value not in ACTIVITY_KEEP:
        raise BackendError("invalid", "Choose how long to keep activity.")
    if key == "systemWindow" and value not in (60, 300):
        raise BackendError("invalid", "Choose one minute or five for the system monitor.")
    if key == "hiddenOutputs" and not check_names(value, 16, 64):
        raise BackendError("invalid", "Incorrect list of screens without a bar.")
    if key == "pinnedApps" and not check_names(value, 200, 300):
        raise BackendError("invalid", "Incorrect pinned apps.")
    # The shell keeps the 200 most used apps and the 60 most used emoji.
    if key == "appUsage" and not check_counts(value, 250, 300):
        raise BackendError("invalid", "Incorrect app history.")
    if key == "emojiUsage" and not check_counts(value, 100, 64):
        raise BackendError("invalid", "Incorrect emoji history.")
    if key == "eqPreset" and value not in (*equalizer.PRESETS, "custom"):
        raise BackendError("invalid", "Choose a supported equalizer preset.")
    if key == "lockScreen" and value not in ("builtin", "hyprlock"):
        raise BackendError("invalid", "Choose the built-in lock screen or hyprlock.")
    if key == "lockStyle" and value not in ("particles", "classic"):
        raise BackendError("invalid", "Choose the particle or classic lock screen.")
    if key == "bluetoothAutoConnect" and (len(value) > 32 or not all(isinstance(a, str) and bluetooth_keep.ADDRESS.match(a) for a in value)
                                          or len(set(value)) != len(value)):
        raise BackendError("invalid", "Choose Bluetooth devices by their address.")
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
    # "recorded": where Activity's record already ends, for a session resumed with Undo. "paused": when a paused
    # session stopped counting down; "pausedFor": how long it was paused before, which its ring leaves out.
    if key == "focusSession" and value and not ({"started", "ends"} <= set(value) <= {"started", "ends", "recorded", "paused", "pausedFor"}
                                                and all(is_time(value[k]) for k in value) and value["started"] < value["ends"]
                                                and value["started"] <= value.get("recorded", value["started"]) <= value["ends"]
                                                and value["started"] <= value.get("paused", value["started"]) <= value["ends"]
                                                and value.get("pausedFor", 0) < value["ends"] - value["started"]):
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
            raise BackendError("invalid", "The recording, privacy and Control items can't be hidden.")
    if key == "controlLayout":
        if not set(value) <= {"tiles", "hiddenTiles", "sections", "footer", "hiddenFooter"}:
            raise BackendError("invalid", "Incorrect Control layout.")
        check_ids([value.get("tiles", []), value.get("hiddenTiles", [])], CONTROL_TILES, "Control tiles")
        check_ids([value.get("footer", []), value.get("hiddenFooter", [])], CONTROL_FOOTER, "Control buttons")
        sections = value.get("sections", {})
        if not isinstance(sections, dict) or not set(sections) <= set(CONTROL_SECTIONS) or not all(type(v) is bool for v in sections.values()):
            raise BackendError("invalid", "Incorrect Control sections.")
        if "settings" in value.get("hiddenFooter", []):
            raise BackendError("invalid", "The Settings button can't be hidden.")
    if key in ("widgetCards", "widgetSaved") and (len(value) > MAX_WIDGET_CARDS or not all(isinstance(card, str) and card in WIDGET_CARDS for card in value)
                                 or len(set(value)) != len(value)):
        raise BackendError("invalid", f"Choose up to {MAX_WIDGET_CARDS} widget cards, each once.")
    if key == "widgetCorner" and value not in WIDGET_CORNERS:
        raise BackendError("invalid", "Choose a corner for the widgets.")
    if key == "clockFormat" and value not in ("time", "day-time", "date-time"):
        raise BackendError("invalid", "Choose a supported clock format.")
    if key == "workspaceStyle" and value not in ("numbers", "dots"):
        raise BackendError("invalid", "Choose numbers or dots.")
    if key == "workspaceSlots" and value not in (0, 5, 10):
        raise BackendError("invalid", "Choose how many pages to show.")
    if key == "trayIcons" and not -1 <= value <= 5:
        raise BackendError("invalid", "Choose up to five tray icons.")
    if key == "batteryPercent" and value not in ("auto", "always", "never"):
        raise BackendError("invalid", "Choose when to show the battery percentage.")
    if key == "barStyle" and value not in ("floating", "edge"):
        raise BackendError("invalid", "Choose a floating or edge-to-edge bar.")
    if key == "weekStart" and value not in ("locale", "monday", "sunday", "saturday"):
        raise BackendError("invalid", "Choose the first day of the week.")
    if key == "terminal" and value != "auto" and value not in (prefix[0] for prefix in TERMINALS):
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

# The file as last read and checked, with what identified it then; settings() is asked for many times a minute.
SETTINGS_READ = {"mark": None, "value": None}

def settings():
    """Every setting. The file is read and checked again only when it has changed."""
    try:
        status = CONFIG.stat()
        mark = (status.st_mtime_ns, status.st_size, status.st_ino)
    except OSError:
        mark = None
    if mark is None or SETTINGS_READ["mark"] != mark:
        SETTINGS_READ.update(mark=mark, value=read_settings())
    return dict(SETTINGS_READ["value"])

def read_settings():
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

PREVIOUS = CONFIG.with_suffix(".previous.json")
# Named copies of the settings (Settings → Backup → Profiles): exports kept next to the settings, under a name.
PROFILES = CONFIG.parent / "profiles"
PROFILE_NAME = re.compile(r"[\w][\w .'-]{0,39}")

def profile_path(name):
    """The file of a profile, or an "invalid" error for a name that can't be one."""
    if not isinstance(name, str) or not PROFILE_NAME.fullmatch(name.strip()) or name.strip() in (".", ".."):
        raise BackendError("invalid", "Name the profile with up to 40 letters, digits, spaces, dots or dashes.")
    return PROFILES / (name.strip() + ".json")

def profiles():
    """The saved profiles, newest first: [{name, saved}]."""
    found = []
    for path in PROFILES.glob("*.json"):
        if PROFILE_NAME.fullmatch(path.stem):
            found.append({"name": path.stem, "saved": stamp(path)})
    return {"profiles": sorted(found, key=lambda item: item["saved"], reverse=True)}

def save_settings(changes, rejected=None, keep_previous=False):
    """Saves the known keys of `changes` after validating them; returns every setting.

    A value that can't be used raises, or with a `rejected` list is left as it was and added to the list as
    {key, message}, so one bad value doesn't hold back the rest. `keep_previous` first copies the settings as
    they are to config.previous.json: a reset or an import can be taken back with restore_settings()."""
    current = settings()
    unreadable = current.pop("diagnostic", None) is not None
    # Only known keys are saved; this also keeps the load diagnostic out of the file.
    changes = {key: value for key, value in changes.items() if key in DEFAULTS}
    for key, value in list(changes.items()):
        try:
            check_setting(key, value)
        except BackendError as error:
            if rejected is None:
                raise
            rejected.append({"key": key, "message": error.message})
            del changes[key]
    if CONFIG.exists():
        if unreadable:
            # Keep the file with its rejected values instead of replacing the last good backup.
            shutil.copy2(CONFIG, CONFIG.with_suffix(".invalid.json"))
        elif keep_previous:
            atomic_json(PREVIOUS, changed_only(current))
    elif keep_previous:
        atomic_json(PREVIOUS, {"version": 1})
    current.update(changes)
    atomic_json(CONFIG, changed_only(current))
    return current

def reset_settings(keys):
    """Puts `keys` back to their defaults; returns every setting."""
    if not isinstance(keys, list) or not all(isinstance(key, str) and key in DEFAULTS and key not in ("version", "shortcuts") for key in keys):
        raise BackendError("invalid", "Choose settings to reset.")
    return save_settings({key: DEFAULTS[key] for key in keys}, keep_previous=True)

def restore_settings():
    """Puts back the settings from before the last reset or import, and keeps today's in their place, so a
    second restore undoes the first; returns every setting."""
    try:
        previous = json.loads(PREVIOUS.read_text())
        if not isinstance(previous, dict) or previous.get("version") != 1:
            raise ValueError("not settings")
    except FileNotFoundError:
        raise BackendError("unavailable", "There are no earlier settings to put back.") from None
    except (OSError, ValueError):
        raise BackendError("failed", "The earlier settings can't be read.") from None
    current = settings()
    current.pop("diagnostic", None)
    restored = dict(DEFAULTS)
    for key, value in previous.items():
        if key not in DEFAULTS or key in RESTORE_KEEPS:
            continue
        try:
            check_setting(key, value)
            restored[key] = value
        except BackendError:
            pass  # written by another version; that setting takes its default
    for key in RESTORE_KEEPS:
        restored[key] = current[key]
    atomic_json(PREVIOUS, changed_only(current))
    atomic_json(CONFIG, changed_only(restored))
    return restored

def stamp(path):
    """When a file was last written, as local ISO time, or "" without one."""
    try:
        return datetime.datetime.fromtimestamp(path.stat().st_mtime).astimezone().isoformat(timespec="seconds")
    except OSError:
        return ""

def backup_state(value):
    """What the Backup page shows: when the settings from before were kept, and when the file was exported."""
    exported = ""
    try:
        data = json.loads(export_path(value).read_text())
        if isinstance(data, dict) and data.get("version") == 1 and isinstance(data.get("exported"), str):
            exported = data["exported"][:40]
    except (BackendError, OSError, ValueError):
        pass
    return {"previous": stamp(PREVIOUS), "exported": exported}

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
    # An export replaces an earlier export, never the settings in use or a file of something else.
    if path.resolve().parent == CONFIG.resolve().parent:
        raise BackendError("invalid", "Choose a file outside Shale's own settings folder.")
    if path.exists():
        try:
            old = json.loads(path.read_text())
        except (OSError, ValueError):
            old = None
        if not (isinstance(old, dict) and old.get("version") == 1 and "exported" in old):
            raise BackendError("invalid", f"{path} already exists and isn't a Shale settings export. Choose another name.")
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
    return {"settings": save_settings(usable, keep_previous=True), "applied": sorted(usable), "skipped": sorted(skipped), "shortcuts": data.get("shortcuts")}

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
            # The left side of a chain ("1+1+1…") stays at this depth: the chain is long, not nested.
            left, right = visit(node.left, depth), visit(node.right, depth + 1)
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

async def hypr_json(*args):
    """Hyprland's answer to `hyprctl <args>` as JSON, or a "failed" error when it can't be read."""
    try:
        return json.loads(await run("hyprctl", *args))
    except ValueError:
        raise BackendError("failed", "Hyprland gave an answer Shale can't read.") from None

# Looks at the disk for the clipboard (is this text a file?). A hung network mount can hold these threads for
# good, so they are kept apart from the ones weather, wallpapers and the system monitor share.
PROBES = ThreadPoolExecutor(max_workers=2, thread_name_prefix="probe")

async def probe(function, *args, timeout):
    return await asyncio.wait_for(asyncio.get_running_loop().run_in_executor(PROBES, function, *args), timeout)

ENTRY_ID = re.compile(r"[0-9]+")

def clipboard_entry(value):
    """A cliphist list line ("id<TAB>preview") from a request, or an "invalid" error."""
    entry = str(value or "")
    if not ENTRY_ID.fullmatch(entry.partition("\t")[0]) or "\n" in entry:
        raise BackendError("invalid", "Select a clipboard entry.")
    return entry


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


# Pinned clipboard entries live outside cliphist, so a wipe or cliphist's own trimming never takes them: an index of
# {"pin", "text" (cliphist's preview line), "file"} and each entry's full contents beside it, readable by you only.
CLIPBOARD_PINS = STATE / "clipboard-pins"
PIN_ID = re.compile(r"[0-9a-f]{16}")
PIN_FILE = re.compile(r"[0-9a-f]{16}\.(png|jpg|data)")
MAX_PINS = 50


def clipboard_pins():
    try:
        pins = json.loads((CLIPBOARD_PINS / "pins.json").read_text())
    except (OSError, ValueError):
        return []
    if not isinstance(pins, list):
        return []
    pins = [pin for pin in pins if isinstance(pin, dict) and isinstance(pin.get("text"), str)
            and PIN_ID.fullmatch(str(pin.get("pin", ""))) and PIN_FILE.fullmatch(str(pin.get("file", "")))]
    for pin in pins:
        # Pins saved before they carried their contents' hash get it from their file.
        if not re.fullmatch(r"[0-9a-f]{40}", str(pin.get("sha", ""))):
            if pin["pin"] not in PIN_HASHES:
                try:
                    PIN_HASHES[pin["pin"]] = hashlib.sha1((CLIPBOARD_PINS / pin["file"]).read_bytes()).hexdigest()
                except OSError:
                    PIN_HASHES[pin["pin"]] = ""
            pin["sha"] = PIN_HASHES[pin["pin"]]
    return pins


PIN_HASHES = {}


def ambiguous_preview(text):
    """cliphist's preview line doesn't settle what an entry holds: images of one size share a line, and long
    text is cut."""
    return text.endswith("…") or bool(clipboard_label(text))


def clipboard_pin(pins, identity):
    """The pin with this id, else an error; the file name was checked when the index was read."""
    pin = next((pin for pin in pins if pin["pin"] == identity), None) if PIN_ID.fullmatch(str(identity)) else None
    if pin is None:
        raise BackendError("invalid", "That pin is gone.")
    return pin


def pin_data(pin):
    try:
        return (CLIPBOARD_PINS / pin["file"]).read_bytes()
    except OSError:
        raise BackendError("failed", "This pin's contents are missing. Unpin it.") from None


# Installed by scripts/install-power-max.py; Control → Power offers Max performance when it is there.
POWER_MAX_UNIT = Path("/etc/systemd/system/shale-power-max.service")
# The desktop Note card's one running note: lines with a done mark, readable by you only.
NOTE = STATE / "note.json"
MAX_NOTE_LINES = 50
MAX_NOTE_TEXT = 200


def note_line(line):
    """A note line as stored, or None: one line of text and whether it is done."""
    if not (isinstance(line, dict) and set(line) == {"text", "done"} and isinstance(line["text"], str) and type(line["done"]) is bool):
        return None
    text = " ".join(line["text"].split())
    return {"text": text, "done": line["done"]} if 0 < len(text) <= MAX_NOTE_TEXT else None


def note_lines():
    try:
        lines = json.loads(NOTE.read_text())
    except (OSError, ValueError):
        return []
    return [line for line in map(note_line, lines) if line][-MAX_NOTE_LINES:] if isinstance(lines, list) else []


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

# The DNS a Wi-Fi network can use besides its own, as in Omarchy's DNS setup: IPv4 servers first.
DNS_PRESETS = {"cloudflare": ("1.1.1.1", "1.0.0.1", "2606:4700:4700::1111", "2606:4700:4700::1001"),
               "google": ("8.8.8.8", "8.8.4.4", "2001:4860:4860::8888", "2001:4860:4860::8844")}

def dns_choice(mode, servers):
    """The DNS servers a choice stands for: none for the network's own ("auto"), a preset's, or the addresses typed
    in ("custom"), separated by spaces or commas."""
    if not isinstance(mode, str):
        raise BackendError("invalid", "Choose where this network gets its DNS from.")
    if mode == "auto":
        return []
    if mode in DNS_PRESETS:
        return [ipaddress.ip_address(server) for server in DNS_PRESETS[mode]]
    if mode != "custom" or not isinstance(servers, str):
        raise BackendError("invalid", "Choose where this network gets its DNS from.")
    words = [word for word in re.split(r"[\s,]+", servers[:500]) if word]
    if not words:
        raise BackendError("invalid", "Enter at least one DNS server, like 9.9.9.9.")
    found = []
    for word in words:
        try:
            # A zone ("%wlan0") can't be saved in the profile's DNS list.
            address = ipaddress.ip_address(word) if "%" not in word else None
        except ValueError:
            address = None
        if address is None or address.is_unspecified or address.is_multicast:
            raise BackendError("invalid", f"{word[:60]} isn't a DNS server address.")
        if address not in found:
            found.append(address)
    if len(found) > 8:
        raise BackendError("invalid", "Enter up to 8 DNS servers.")
    return found

def dns_state(config):
    """Where a saved connection (as GetSettings returns it) gets its DNS: {"mode", "servers"}, the mode being "auto",
    a preset's name or "custom"."""
    servers = []
    for family in ("ipv4", "ipv6"):
        section = config.get(family, {})
        if "dns-data" in section:
            # Newer NetworkManagers may add a DoT server name: "1.1.1.1#cloudflare-dns.com".
            servers += [entry.partition("#")[0] for entry in section["dns-data"].value]
        elif "dns" in section:
            servers += [str(ipaddress.IPv4Address(struct.pack("=I", value))) if family == "ipv4" else str(ipaddress.IPv6Address(bytes(value)))
                        for value in section["dns"].value]
    if not servers:
        return {"mode": "auto", "servers": []}
    for preset, addresses in DNS_PRESETS.items():
        if set(servers) in (set(addresses), set(addresses[:2])):
            return {"mode": preset, "servers": servers}
    return {"mode": "custom", "servers": servers}

def dns_settings(config, servers, encrypted):
    """A saved connection's settings (as GetSettings returns them) with these DNS servers in place of the network's
    own, or with the network's own again when there are none. `encrypted` asks for DNS over TLS where the servers
    offer it, falling back to plain DNS where they don't."""
    from dbus_next import Variant  # importable once interface() has found dbus-next
    used, off = 0, []
    for family, kind in (("ipv4", ipaddress.IPv4Address), ("ipv6", ipaddress.IPv6Address)):
        section = config.setdefault(family, {})
        # NetworkManager reads a legacy key over its replacement when both come back, so only the replacements go,
        # and the servers go in the legacy `dns` alone, which every version reads.
        for legacy, current in (("addresses", "address-data"), ("routes", "route-data")):
            if current in section:
                section.pop(legacy, None)
        section.pop("dns", None)
        section.pop("dns-data", None)
        if section.get("method", Variant("s", "auto")).value in ("disabled", "ignore"):
            off.append(family)
            continue  # this family is off for the network: it takes no servers
        mine = [address for address in servers if isinstance(address, kind)]
        if mine:
            section["dns"] = (Variant("au", [struct.unpack("=I", address.packed)[0] for address in mine]) if family == "ipv4"
                              else Variant("aay", [address.packed for address in mine]))
            used += len(mine)
        # With servers of its own the network's DNS is left out, for both families, as Omarchy does.
        section["ignore-auto-dns"] = Variant("b", bool(servers))
    if servers and not used:
        if len(off) == 2:
            raise BackendError("invalid", "This network has IPv4 and IPv6 turned off.")
        family, other = ("IPv6", "IPv4") if off == ["ipv6"] else ("IPv4", "IPv6")
        raise BackendError("invalid", f"This network has {family} turned off. Add an {other} server.")
    if encrypted:
        config.setdefault("connection", {})["dns-over-tls"] = Variant("i", 1)  # opportunistic
    else:
        config.get("connection", {}).pop("dns-over-tls", None)
    return config

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
        self.activity_trimmed = ""
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
        self.update_lock = asyncio.Lock()
        self.lock_hint_lock = asyncio.Lock()
        self.shortcut_lock = asyncio.Lock()
        self.display_lock = asyncio.Lock()
        # Outputs changed in Settings → Displays and not yet kept: {name: {"previous": rule, "task": revert task}}.
        self.display_pending = {}
        # Clipboard entries deleted, and wipes so far: a preview still being decoded for one must not be saved after.
        self.clipboard_deleted = set()
        self.clipboard_wipes = 0
        self.clipboard_pin_lock = asyncio.Lock()
        # sha1 of history entries' contents by cliphist id, worked out only for entries that look like a pin.
        self.clipboard_hashes = {}
        # Counts the system buses connected so far: watches set up on an earlier one are set up again.
        self.bus_generation = 0
        # Introspection of objects that all look alike (access points, saved connections), by a caller's key.
        self.introspection = {}
        # Leaves the key-recording submap if Settings never says it's done.
        self.record_timeout = None
        # Closes links left open after a device switched off and runs auto-connect; set up by watch_bluetooth.
        self.bluetooth = None

    async def interface(self, name, path, interface, timeout=25, alike=None):
        """A system bus interface whose method calls time out after `timeout` seconds (None: never).

        `alike` names a kind of object whose instances all have the same interfaces (an access point, a saved
        connection): the first one is introspected and the rest reuse its description, which halves the calls
        of a list."""
        try:
            from dbus_next.aio import MessageBus
            from dbus_next import BusType
        except ImportError:
            raise BackendError("unavailable", "Install python-dbus-next to enable system controls.") from None
        try:
            async with self.bus_lock:
                if self.bus is None or not self.bus.connected:
                    self.bus = await asyncio.wait_for(MessageBus(bus_type=BusType.SYSTEM, negotiate_unix_fd=True).connect(), 10)
                    self.bus_generation += 1
                    self.introspection = {}
            intro = self.introspection.get(alike) if alike else None
            if intro is None:
                # A service that hangs must not hold the request for its whole allowance.
                intro = await asyncio.wait_for(self.bus.introspect(name, path), 10 if timeout is None else min(10, timeout))
                if alike:
                    self.introspection[alike] = intro
        except asyncio.TimeoutError:
            raise BackendError("timeout", "A system service did not answer in time.") from None
        proxy = self.bus.get_proxy_object(name, path, intro).get_interface(interface)
        return proxy if timeout is None else TimedInterface(proxy, timeout)

    async def entry_hash(self, line):
        """sha1 of a history entry's contents ("" if it can't be read), remembered by its cliphist id."""
        identity = line.partition("\t")[0]
        if identity not in self.clipboard_hashes:
            if len(self.clipboard_hashes) > 2000:
                self.clipboard_hashes.clear()
            try:
                self.clipboard_hashes[identity] = hashlib.sha1(await run("cliphist", "decode", data=line.encode())).hexdigest()
            except BackendError:
                return ""
        return self.clipboard_hashes[identity]

    async def same_as_pin(self, line, pins):
        """Whether a history line holds what one of `pins` holds. The preview line settles it for short text;
        images and cut text are compared by their contents."""
        text = line.partition("\t")[2]
        matches = [pin for pin in pins if pin["text"] == text]
        if not matches:
            return False
        if not ambiguous_preview(text) or not all(pin["sha"] for pin in matches):
            return True
        return await self.entry_hash(line) in {pin["sha"] for pin in matches}

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

    async def refit_wallpapers(self, fit):
        """Shows each screen's wallpaper again in a new fit; a screen that fails keeps the old one."""
        try:
            daemon = await self.wallpaper_daemon()
            async with self.wallpaper_lock:
                for monitor, path in (await wallpaper.active(run, daemon)).items():
                    if path and Path(path).is_file():
                        await wallpaper.apply(run, path, monitor, BackendError, daemon, fit)
        except BackendError as error:
            print(f"Wallpaper fit: {error.message}", file=sys.stderr, flush=True)

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

    TERMINALS = TERMINALS

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
            monitors = await hypr_json("monitors", "-j")
            builtin_panel = any(BUILTIN_PANEL.fullmatch(str(m.get("name", ""))) for m in monitors)
        except (BackendError, ValueError, TypeError):
            builtin_panel = None
        return {"commands": {x: bool(shutil.which(x)) for x in self.COMMANDS},
                "dbus": importlib.util.find_spec("dbus_next") is not None,
                "lid": any(Path("/proc/acpi/button/lid").glob("*")),
                "terminal": self.terminal(),
                "terminals": [prefix[0] for prefix in self.TERMINALS if shutil.which(prefix[0])],
                "builtinPanel": builtin_panel, "airdrop": airdrop_command(), "version": 1}

    async def hypr_eval(self, code):
        """Runs Lua in Hyprland; False when it reports an error."""
        try:
            return (await run("hyprctl", "eval", code)).decode().strip() == "ok"
        except BackendError:
            return False

    async def live_binds(self):
        try:
            return await hypr_json("binds", "-j")
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
        """Applies imported shortcuts when all of them fit this computer; "" if they did, or why not."""
        bound, ready = shortcuts.installed(HYPR)
        try:
            shortcuts.check(wanted)
        except ValueError:
            return "the file's shortcuts can't be read"
        if not ready:
            return "shortcuts aren't set up on this computer; run the installer"
        current = shortcuts.effective(bound, settings()["shortcuts"])
        after = shortcuts.effective(bound, wanted)
        binds = await self.live_binds()
        if any(keys and shortcuts.clash(keys, n, current, binds, after) for n, keys in after.items() if keys != current[n]):
            return "their keys are taken here"
        await self.save_shortcuts({n: keys for n, keys in wanted.items() if keys != bound.get(n, "")},
                                  {n: (current[n], after[n]) for n in after})
        return ""

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
            current = await hypr_json("-j", "submap")
        except (BackendError, ValueError):
            return
        if current == shortcuts.RECORD_SUBMAP:
            await self.hypr_eval('hl.dispatch(hl.dsp.submap("reset"))')

    DISPLAY_REVERT = 15
    DISPLAYS_SAVED = CONFIG.parent / "displays.json"

    def saved_displays(self):
        try:
            value = json.loads(self.DISPLAYS_SAVED.read_text())
            return {name: entry for name, entry in value.items() if isinstance(entry, dict)} if isinstance(value, dict) else {}
        except (FileNotFoundError, ValueError):
            return {}

    def write_displays(self, entries):
        """Keeps the confirmed rules as JSON (to merge later) and as the Lua file shale.lua applies at start."""
        CONFIG.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        atomic_json(self.DISPLAYS_SAVED, entries)
        target = CONFIG.parent / "displays.lua"
        fd, name = tempfile.mkstemp(prefix=".shale-", dir=target.parent)
        try:
            with os.fdopen(fd, "w") as stream:
                stream.write(displays.saved_lua(entries))
            os.replace(name, target)
        finally:
            if os.path.exists(name):
                os.unlink(name)

    async def apply_display(self, entry):
        if not await self.hypr_eval(displays.rule_lua(entry)):
            raise BackendError("failed", "Hyprland didn't accept that display setting.")

    async def revert_display_later(self, name):
        try:
            await asyncio.sleep(self.DISPLAY_REVERT)
        except asyncio.CancelledError:
            return
        async with self.display_lock:
            pending = self.display_pending.pop(name, None)
            if pending:
                try:
                    await self.apply_display(pending["previous"])
                except BackendError:
                    pass
                emit("display.reverted", {"output": name})

    async def displays(self, action, p):
        """Settings → Displays. `set` applies a resolution, refresh rate and scale at once and puts the old ones back
        after DISPLAY_REVERT seconds unless `keep` confirms them; `reset` forgets a kept choice."""
        monitors = [m for m in await hypr_json("monitors", "-j") if not m.get("disabled")]
        if action == "list":
            saved = self.saved_displays()
            now = time.monotonic()
            return {"displays": [{**displays.describe(m), "saved": m["name"] in saved,
                                  "pending": max(1, math.ceil(self.display_pending[m["name"]]["until"] - now)) if m["name"] in self.display_pending else 0}
                                 for m in monitors],
                    "revertSeconds": self.DISPLAY_REVERT,
                    # False until an install or update brings the shale.lua that applies kept displays at start.
                    "startup": "displays.lua" in await asyncio.to_thread(lambda: (HYPR / "shale.lua").read_text() if (HYPR / "shale.lua").exists() else "")}
        name = p.get("output")
        monitor = next((m for m in monitors if m["name"] == name), None)
        if monitor is None:
            raise BackendError("invalid", "That display is no longer connected.")
        if action == "set":
            width, height, rate, scale = p.get("width"), p.get("height"), p.get("rate"), p.get("scale")
            try:
                displays.check(monitor, width, height, rate, scale)
            except ValueError as error:
                raise BackendError("invalid", str(error)) from None
            current = displays.describe(monitor)
            # A second change before keeping still reverts to what was there before the first.
            pending = self.display_pending.pop(name, None)
            previous = pending["previous"] if pending else displays.rule(monitor, current["width"], current["height"], current["rate"], current["scale"])
            if pending:
                pending["task"].cancel()
            await self.apply_display(displays.rule(monitor, width, height, float(rate), float(scale)))
            self.display_pending[name] = {"previous": previous, "until": time.monotonic() + self.DISPLAY_REVERT,
                                          "task": asyncio.create_task(self.revert_display_later(name))}
            return {"pending": True, "seconds": self.DISPLAY_REVERT}
        pending = self.display_pending.pop(name, None)
        if pending:
            pending["task"].cancel()
        if action == "revert":
            if pending:
                await self.apply_display(pending["previous"])
            return {"done": True}
        saved = self.saved_displays()
        if action == "keep":
            current = displays.describe(monitor)
            saved[name] = displays.rule(monitor, current["width"], current["height"], current["rate"], current["scale"])
            await asyncio.to_thread(self.write_displays, saved)
            return {"done": True}
        # reset: Hyprland goes back to its own config for this output.
        saved.pop(name, None)
        await asyncio.to_thread(self.write_displays, saved)
        if pending:
            await self.apply_display(pending["previous"])
        await run("hyprctl", "reload")
        return {"done": True}

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
            current = (await hypr_json("getoption", f"decoration:{option}:enabled", "-j")).get("bool", False)
            if saver:
                # After a config reload the compositor is back at the user's value; record it again.
                keep[option] = current or options.get(option, False)
                if current:
                    changes.append(f"hl.config({{decoration = {{{option} = {{enabled = false}}}}}})")
            elif options.get(option) and not current:
                changes.append(f"hl.config({{decoration = {{{option} = {{enabled = true}}}}}})")
        monitors_kept = {}
        for monitor in await hypr_json("monitors", "-j"):
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

    async def bluetooth_call(self, path, member, timeout=25):
        """Device1.Connect or Disconnect on one device, without introspecting it."""
        await self.interface("org.bluez", "/", "org.freedesktop.DBus.ObjectManager")  # connects the bus, checks BlueZ is there
        from dbus_next import Message, MessageType  # importable once interface() has found dbus-next
        reply = await asyncio.wait_for(self.bus.call(Message(destination="org.bluez", path=path, interface="org.bluez.Device1", member=member)), timeout)
        if reply.message_type == MessageType.ERROR:
            if reply.error_name in ("org.bluez.Error.AlreadyConnected", "org.bluez.Error.NotConnected"):
                return  # it got there by itself
            if reply.error_name in SERVICE_MISSING or reply.error_name == "org.freedesktop.DBus.Error.UnknownObject":
                raise BackendError("unavailable", "That device is no longer available.")
            raise BackendError("failed", reply.error_name)

    async def watch_bluetooth(self):
        """Follows BlueZ's objects and properties for bluetooth_keep, from login until the helper stops."""
        manager = await self.interface("org.bluez", "/", "org.freedesktop.DBus.ObjectManager")
        from dbus_next import Message, MessageType  # importable once interface() has found dbus-next
        if self.bluetooth is None:
            self.bluetooth = bluetooth_keep.Keeper(lambda path: self.bluetooth_call(path, "Connect"),
                                                   lambda path: self.bluetooth_call(path, "Disconnect"),
                                                   lambda: settings()["bluetoothAutoConnect"])
        keeper = self.bluetooth
        keeper.load(await manager.call_get_managed_objects())
        for rule in ("type='signal',sender='org.bluez',interface='org.freedesktop.DBus.ObjectManager'",
                     "type='signal',sender='org.bluez',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged'",
                     "type='signal',sender='org.freedesktop.DBus',member='NameOwnerChanged',arg0='org.bluez'"):
            await self.bus.call(Message(destination="org.freedesktop.DBus", path="/org/freedesktop/DBus", interface="org.freedesktop.DBus",
                                        member="AddMatch", signature="s", body=[rule]))

        async def reload():
            # bluetoothd restarted: its objects are new.
            try:
                keeper.load(await (await self.interface("org.bluez", "/", "org.freedesktop.DBus.ObjectManager")).call_get_managed_objects())
                keeper.trigger("Bluetooth service started", fresh=True)
            except Exception as error:
                log_unexpected(error, "Bluetooth watch")

        def on_message(message):
            if message.message_type != MessageType.SIGNAL:
                return
            try:
                if message.member == "NameOwnerChanged" and message.body[0] == "org.bluez" and message.body[2]:
                    asyncio.ensure_future(reload())
                elif not (message.path or "").startswith("/org/bluez") and message.path != "/":
                    return
                elif message.member == "InterfacesAdded":
                    keeper.added(message.body[0], message.body[1])
                elif message.member == "InterfacesRemoved":
                    keeper.removed(message.body[0], message.body[1])
                elif message.member == "PropertiesChanged" and message.interface == "org.freedesktop.DBus.Properties":
                    keeper.changed(message.path, message.body[0], message.body[1])
            except Exception as error:
                log_unexpected(error, "Bluetooth watch")
        self.bus.add_message_handler(on_message)
        keeper.trigger("login", fresh=True)

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
            connection = await self.interface(name, path, name + ".Settings.Connection", alike="nm-connection")
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
            props = await self.interface(name, active, "org.freedesktop.DBus.Properties", alike="nm-active")
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
        if action == "hidden":
            # A network that doesn't announce its name: NetworkManager looks for it by name ("hidden"), with a
            # password for WPA2/WPA3 Personal or none for an open one. A profile that never connects is removed again.
            ssid = p.get("ssid")
            password = p.get("password") or ""
            if not isinstance(ssid, str) or not 0 < len(ssid.encode()) <= 32 or "\n" in ssid:
                raise BackendError("invalid", "Enter the network's name, up to 32 characters.")
            if not isinstance(password, str) or (password and not 8 <= len(password) <= 63):
                raise BackendError("invalid", "Wi-Fi passwords are 8 to 63 characters; leave it empty for an open network.")
            config = {"connection": {"id": Variant("s", ssid), "type": Variant("s", "802-11-wireless")},
                      "802-11-wireless": {"ssid": Variant("ay", ssid.encode()), "hidden": Variant("b", True)}}
            if password:
                config["802-11-wireless-security"] = {"key-mgmt": Variant("s", "wpa-psk"), "psk": Variant("s", password)}
            profile, active_path = await manager.call_add_and_activate_connection(config, device_path, "/")
            active_props = await self.interface(name, active_path, "org.freedesktop.DBus.Properties")
            for _ in range(60):
                try:
                    state = (await active_props.call_get(name + ".Connection.Active", "State")).value
                except Exception:
                    state = 4  # the attempt is gone: it failed
                if state == 2:
                    return {"done": True}
                if state == 4:
                    break
                await asyncio.sleep(0.5)
            try:
                await (await self.interface(name, profile, name + ".Settings.Connection")).call_delete()
            except Exception:
                pass
            raise BackendError("failed", f"Couldn't join {ssid}. Check its name and password.")
        if action == "dns":
            # The DNS of the network in use, kept in its own profile: every other network, and the sign-in page of
            # a café or campus network, keeps the DNS it gives out.
            mode = p.get("mode")
            servers = dns_choice(mode, p.get("servers"))
            active = (await device_props.call_get(name + ".Device", "ActiveConnection")).value
            if (await device_props.call_get(name + ".Device", "State")).value != 100 or active == "/":
                raise BackendError("unavailable", "Connect to the network first.")
            if p.get("path") != (await device_props.call_get(name + ".Device.Wireless", "ActiveAccessPoint")).value:
                raise BackendError("unavailable", "The network changed while you were choosing. Try again.")
            active_props = await self.interface(name, active, "org.freedesktop.DBus.Properties", alike="nm-active")
            profile = (await active_props.call_get(name + ".Connection.Active", "Connection")).value
            connection = await self.interface(name, profile, name + ".Settings.Connection", alike="nm-connection")
            try:
                # Settings sent without secrets keep the saved password.
                await connection.call_update(dns_settings(await connection.call_get_settings(), servers, mode in DNS_PRESETS))
            except Exception as error:
                if "PermissionDenied" not in str(getattr(error, "type", "")):
                    raise
                raise BackendError("permission", "NetworkManager didn't let you change this network's settings.") from None
            try:
                await device.call_reapply({}, 0, 0)
            except Exception:
                # A change NetworkManager can't apply to a live link: join the network again to use it.
                await manager.call_activate_connection(profile, device_path, "/")
            return {"done": True}

        settings = await self.interface(name, "/org/freedesktop/NetworkManager/Settings", name + ".Settings")
        profiles, configs = {}, {}
        for path in await settings.call_list_connections():
            connection = await self.interface(name, path, name + ".Settings.Connection", alike="nm-connection")
            try:
                config = await connection.call_get_settings()
            except Exception:
                continue  # A system profile may be private to another user.
            if config.get("connection", {}).get("type", Variant("s", "")).value != "802-11-wireless":
                continue
            ssid = bytes(config.get("802-11-wireless", {}).get("ssid", Variant("ay", b"")).value)
            security = config.get("802-11-wireless-security", {}).get("key-mgmt")
            profiles[(ssid, "open" if security is None or security.value == "owe" else "8021x" if security.value == "wpa-eap" else "secured")] = path
            configs[path] = config

        active_ap = (await device_props.call_get(name + ".Device.Wireless", "ActiveAccessPoint")).value
        state = (await device_props.call_get(name + ".Device", "State")).value
        powered = (await manager_props.call_get(name, "WirelessEnabled")).value
        # The profile in use, whose DNS the network in use shows.
        in_use = None
        if state == 100:
            try:
                active = (await device_props.call_get(name + ".Device", "ActiveConnection")).value
                active_props = await self.interface(name, active, "org.freedesktop.DBus.Properties", alike="nm-active")
                in_use = (await active_props.call_get(name + ".Connection.Active", "Connection")).value
            except Exception:
                pass  # the link dropped while being read
        networks, rsn = {}, {}
        for path in await wireless.call_get_all_access_points():
            props = await self.interface(name, path, "org.freedesktop.DBus.Properties", alike="nm-access-point")
            try:
                ap = await props.call_get_all(name + ".AccessPoint")
            except Exception:
                continue  # out of range since the list was read
            ssid = bytes(ap["Ssid"].value)
            if not ssid:
                continue
            rsn[path] = ap["RsnFlags"].value
            flags = ap["WpaFlags"].value | ap["RsnFlags"].value
            # Enhanced Open (OWE, 0x800 and its transition mode 0x1000) encrypts without a password.
            owe = bool(flags & 0x1800) and not flags & 0x700
            kind = "8021x" if flags & 0x200 else "open" if owe or not (ap["Flags"].value & 1 or flags) else "secured"
            connected = path == active_ap and state == 100
            frequency = ap["Frequency"].value if "Frequency" in ap else 0
            network = {"path": path, "name": ssid.decode("utf-8", "replace"), "type": kind, "owe": owe,
                       "connected": connected, "saved": (ssid, kind) in profiles,
                       "signal": ap["Strength"].value,
                       # MHz to the band people know it by; "" when the access point doesn't say.
                       "band": "" if not frequency else "2.4 GHz" if frequency < 3000 else "5 GHz" if frequency < 5925 else "6 GHz"}
            if connected:
                try:
                    # The speed of the link as it is now, in Mbit/s (NetworkManager counts in kbit/s).
                    network["speed"] = round((await device_props.call_get(name + ".Device.Wireless", "Bitrate")).value / 1000)
                except Exception:
                    pass  # an older NetworkManager, or the link just dropped
                if in_use in configs:
                    network["dns"] = dns_state(configs[in_use])
            key = (ssid, kind)
            if key not in networks or connected or (not networks[key]["connected"] and network["signal"] > networks[key]["signal"]):
                networks[key] = network
        if action == "list":
            return {"networks": sorted(({key: value for key, value in n.items() if key != "owe"} for n in networks.values()),
                                       key=lambda n: (-n["connected"], -n["signal"], n["name"])),
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
            try:
                active_path = await manager.call_activate_connection(profile, device_path, path)
            except Exception as error:
                if "UnknownConnection" not in str(getattr(error, "type", "")):
                    raise
                # NetworkManager says a saved network isn't available when this access point has gone since the
                # list was read: let it pick one of the network's access points itself.
                try:
                    active_path = await manager.call_activate_connection(profile, device_path, "/")
                except Exception as again:
                    if "UnknownConnection" not in str(getattr(again, "type", "")):
                        raise
                    raise BackendError("unavailable", f"{network['name']} isn't in range right now. Scan and try again.") from None
        else:
            if network["type"] == "8021x":
                raise BackendError("invalid", "Configure enterprise credentials in NetworkManager first.")
            config = {"connection": {"id": Variant("s", network["name"]), "type": Variant("s", "802-11-wireless")},
                      "802-11-wireless": {"ssid": Variant("ay", ssid)}}
            if network["owe"]:
                config["802-11-wireless-security"] = {"key-mgmt": Variant("s", "owe")}
            elif network["type"] != "open":
                password = p.get("password")
                if not isinstance(password, str) or not password:
                    raise BackendError("invalid", "Enter the Wi-Fi password.")
                config["802-11-wireless-security"] = {"key-mgmt": Variant("s", key_management(rsn[path])), "psk": Variant("s", password)}
            profile, active_path = await manager.call_add_and_activate_connection(config, device_path, path)
        active_props = await self.interface(name, active_path, "org.freedesktop.DBus.Properties")
        for _ in range(60):
            try:
                state = (await active_props.call_get(name + ".Connection.Active", "State")).value
            except Exception:
                state = 4  # the attempt is gone: it failed
            if state == 2:
                return {"done": True}
            if state == 4:
                raise BackendError("failed", "Wi-Fi connection failed. Check the password and try again.")
            await asyncio.sleep(0.5)
        raise BackendError("timeout", "Wi-Fi connection timed out.")

    async def bluetooth_pair(self, p):
        objects = await self.objects("org.bluez")
        from dbus_next.service import ServiceInterface, method  # importable once interface() has found dbus-next
        from dbus_next import DBusError
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
                    self.activity_trimmed = ""
                # Old days go once a day, while recording or when the panel opens.
                if self.activity_trimmed != datetime.date.today().isoformat():
                    self.activity.trim(settings()["activityKeep"])
                    self.activity_trimmed = datetime.date.today().isoformat()
                if method == "activity.update":
                    self.activity_snapshot = dict(p)
                    return self.activity.ingest({**p, "unlocked": bool(p.get("unlocked")) and not self.activity_locked and not self.activity_sleeping})
                # Weeks start on the shell's locale's first day (0 is Sunday).
                first = p.get("weekStart", 1)
                if method == "activity.overview":
                    return self.activity.overview(first)
                if method == "activity.day":
                    return self.activity.day(str(p.get("date", "")))
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
            before_settings = settings()
            before = before_settings["bluetoothAutoConnect"]
            # A value the shell can't use is reported and left as it was; the others are saved.
            rejected = []
            current = save_settings({key: value for key, value in changes.items() if key != "shortcuts"}, rejected)
            added = [address for address in current["bluetoothAutoConnect"] if address not in before]
            if added and self.bluetooth:
                # A device just marked for auto-connect is tried straight away, even one disconnected by hand.
                self.bluetooth.release(added)
                self.bluetooth.trigger("auto-connect turned on")
            if current["activityTracking"] != "on":
                self.close_activity()
            if current["activityKeep"] != before_settings["activityKeep"]:
                self.activity_trimmed = ""  # the next activity request trims to the new length
            if current["wallpaperFit"] != before_settings["wallpaperFit"]:
                await self.refit_wallpapers(current["wallpaperFit"])
            return {**current, "rejected": rejected} if rejected else current
        if method == "settings.restore":
            before = settings()
            current = restore_settings()
            problem = await self.settings_replaced(before, current)
            return {"settings": current, "problem": problem}
        if method == "settings.defaults":
            # How Shale comes, for the reset key beside each changed setting.
            return {key: value for key, value in DEFAULTS.items() if key not in ("version", "shortcuts")}
        if method == "settings.backup":
            return backup_state(p.get("path"))
        if method == "settings.reset":
            before = settings()
            current = reset_settings(p.get("keys"))
            await self.settings_replaced(before, current)
            return current
        if method == "settings.export":
            return export_settings(p.get("path"))
        if method == "settings.profiles":
            return profiles()
        if method == "settings.profile.save":
            path = profile_path(p.get("name"))
            PROFILES.mkdir(parents=True, exist_ok=True, mode=0o700)
            return {**export_settings(str(path)), **profiles()}
        if method == "settings.profile.delete":
            profile_path(p.get("name")).unlink(missing_ok=True)
            return profiles()
        if method == "settings.profile.load":
            # A profile is an export; loading it is an import, shortcuts included, with Undo through restore.
            path = profile_path(p.get("name"))
            if not path.exists():
                raise BackendError("invalid", "That profile is gone.")
            return await self.dispatch("settings.import", {"path": str(path)})
        if method == "settings.import":
            before = settings()
            result = import_settings(p.get("path"))
            wanted = result.pop("shortcuts")
            if wanted is not None:
                async with self.shortcut_lock:
                    reason = await self.import_shortcuts(wanted)
                (result["skipped"] if reason else result["applied"]).append("shortcuts")
                result["shortcutsReason"] = reason
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
        if method == "update.status":
            async with self.update_lock:
                return await asyncio.to_thread(update.status, SHELL_FOLDER, CACHE / "update.json", STATE / "update.json",
                                               settings()["updateCheck"], p.get("refresh") is True)
        if method == "update.skip":
            async with self.update_lock:
                try:
                    await asyncio.to_thread(update.skip, CACHE / "update.json", STATE / "update.json")
                except ValueError as exc:
                    raise BackendError("invalid", str(exc)) from None
                return await asyncio.to_thread(update.status, SHELL_FOLDER, CACHE / "update.json", STATE / "update.json",
                                               settings()["updateCheck"])
        if method == "update.seen":
            async with self.update_lock:
                await asyncio.to_thread(update.seen, SHELL_FOLDER, STATE / "update.json")
                return await asyncio.to_thread(update.status, SHELL_FOLDER, CACHE / "update.json", STATE / "update.json",
                                               settings()["updateCheck"])
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
            result = await asyncio.to_thread(wallpaper.catalog, settings()["wallpaperDirectory"], CACHE / "thumbs")
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
                result = await wallpaper.apply(run, p.get("path", ""), p.get("monitor", ""), BackendError, await self.wallpaper_daemon(),
                                               settings()["wallpaperFit"])
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
            names = [monitor["name"] for monitor in await hypr_json("monitors", "-j")]
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
                        await wallpaper.apply(run, path, name, BackendError, daemon, settings()["wallpaperFit"])
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
            if action in ("connect", "hidden", "dns"):
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
        if method in ("bluetooth.connect", "bluetooth.disconnect"):
            path = p.get("path")
            if not isinstance(path, str) or not re.fullmatch(r"/org/bluez/hci\d+/dev(_[0-9A-F]{2}){6}", path):
                raise BackendError("invalid", "Select a Bluetooth device.")
            address = path.rsplit("/dev_", 1)[1].replace("_", ":")
            if self.bluetooth:
                # A device disconnected by hand stays off until the next wake, login or Bluetooth start.
                self.bluetooth.hold(address) if method == "bluetooth.disconnect" else self.bluetooth.release([address])
            try:
                await self.bluetooth_call(path, "Connect" if method == "bluetooth.connect" else "Disconnect")
            except BackendError as error:
                if method == "bluetooth.connect" and error.code != "unavailable":
                    raise BackendError("failed", "Couldn't connect. Make sure the device is on and nearby.") from None
                raise
            return {"done": True}
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
            current = (await hypr_json("getoption", "decoration:screen_shader", "-j"))["str"]
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
                actual = (await hypr_json("getoption", "decoration:screen_shader", "-j"))["str"]
                enabled = actual == shader
            return {"enabled": enabled}
        if method.startswith("display.") and method[8:] in ("list", "set", "keep", "revert", "reset"):
            async with self.display_lock:
                return await self.displays(method[8:], p)
        if method in ("keyboard.get", "keyboard.next"):
            if method == "keyboard.next":
                # Every keyboard, so an external one and the laptop's never disagree.
                await run("hyprctl", "switchxkblayout", "all", "next")
            return keyboard_state(await hypr_json("devices", "-j"))
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
            entry = clipboard_entry(p.get("entry"))
            identity = entry.partition("\t")[0]
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
            # Written whole and private before it takes its name: the shell may be loading the old one.
            fd, name = tempfile.mkstemp(prefix=".shale-", dir=folder)
            try:
                with os.fdopen(fd, "wb") as stream:
                    stream.write(data)
                os.replace(name, path)
            finally:
                if os.path.exists(name):
                    os.unlink(name)
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
        # Files dropped or picked for AirDrop: which exist, and their sizes for the share card.
        if method == "airdrop.stat":
            paths = p.get("paths")
            if not isinstance(paths, list) or len(paths) > 200:
                raise BackendError("invalid", "Expected up to 200 paths.")
            items = await asyncio.to_thread(lambda: [staged_item(path) for path in paths])
            return {"items": [item for item in items if item]}
        if method == "note.get":
            return {"lines": note_lines()}
        if method == "note.set":
            lines = p.get("lines")
            checked = [note_line(line) for line in lines] if isinstance(lines, list) and len(lines) <= MAX_NOTE_LINES else [None]
            if None in checked:
                raise BackendError("invalid", f"A note holds up to {MAX_NOTE_LINES} lines of up to {MAX_NOTE_TEXT} characters.")
            atomic_json(NOTE, checked)
            return {"lines": checked}
        # A line from Find ("note …") or the card; the oldest lines make room once the note is full.
        if method == "note.add":
            line = note_line({"text": p.get("text"), "done": False})
            if line is None:
                raise BackendError("invalid", f"Write a line of up to {MAX_NOTE_TEXT} characters.")
            lines = (note_lines() + [line])[-MAX_NOTE_LINES:]
            atomic_json(NOTE, lines)
            return {"lines": lines}
        if method == "power.compositor":
            return await self.compositor_saver(bool(p.get("saver")), bool(p.get("refresh", True)))
        if method.startswith("power."):
            # tuned-ppd serves these properties but omits them from introspection.
            # Read the standard Properties interface instead of generated accessors.
            name = "net.hadess.PowerProfiles"
            interface = await self.interface(name, "/net/hadess/PowerProfiles", "org.freedesktop.DBus.Properties")
            properties = await interface.call_get_all(name)
            available = [x["Profile"].value for x in properties["Profiles"].value]
            platform = Path("/sys/firmware/acpi/platform_profile")
            def firmware_custom():
                try:
                    return platform.read_text().strip() == "custom"
                except OSError:
                    return False
            def charger_in():
                # As integration/power-max/shale-power-max checks it: a mains adapter (AC*, ADP*) online.
                for online in Path("/sys/class/power_supply").glob("A*/online"):
                    try:
                        if online.read_text().strip() == "1":
                            return True
                    except OSError:
                        pass
                return False
            from dbus_next import Variant
            if method == "power.set":
                profile = p.get("profile")
                if profile not in available:
                    raise BackendError("invalid", "Select an available power profile.")
                # Leaving Max performance for Performance: the daemon skips an unchanged profile, so step through Balanced
                # to make it write the firmware's own limits back.
                if firmware_custom() and properties["ActiveProfile"].value == profile and "balanced" in available:
                    await interface.call_set(name, "ActiveProfile", Variant("s", "balanced"))
                await interface.call_set(name, "ActiveProfile", Variant("s", profile))
                properties = await interface.call_get_all(name)
            # Max performance: Performance, then shale-power-max.service (scripts/install-power-max.py) raises the
            # Lenovo firmware limits to the highest values the firmware allows.
            if method == "power.max":
                if not POWER_MAX_UNIT.exists():
                    raise BackendError("unavailable", "Install Max performance first: sudo python3 scripts/install-power-max.py --apply")
                if "performance" in available:
                    await interface.call_set(name, "ActiveProfile", Variant("s", "performance"))
                try:
                    # Without the polkit rule, the polkit agent asks for a password: give it time.
                    await run("systemctl", "start", "shale-power-max.service", timeout=120)
                except BackendError as error:
                    if error.code != "failed":
                        raise
                    # The helper refuses on battery; any other refusal or write error is in its journal.
                    raise BackendError("failed", "Max performance needs the charger plugged in." if not charger_in()
                                       else "Could not raise the firmware power limits. See why: journalctl -u shale-power-max") from None
                properties = await interface.call_get_all(name)
            try:
                tuned = "=shale-" in Path("/etc/tuned/ppd.conf").read_text()
            except OSError:
                tuned = None  # not tuned-ppd (e.g. power-profiles-daemon): Shale's profiles don't apply
            return {"active": properties["ActiveProfile"].value, "profiles": available, "tuned": tuned,
                    "max": firmware_custom(), "maxAvailable": POWER_MAX_UNIT.exists()}
        if method == "clipboard.list":
            data = (await run("cliphist", "list")).decode(errors="replace")
            query = str(p.get("query", "")).casefold()
            limit = min(1000, max(1, int(number(p, "limit", 100))))
            saved, pins = clipboard_pins(), []
            for pin in saved:
                if query in pin["text"].casefold():
                    entry = {"pin": pin["pin"], "text": pin["text"]}
                    if label := clipboard_label(pin["text"]):
                        entry["label"] = label
                        if not pin["file"].endswith(".data"):
                            entry["image"] = str(CLIPBOARD_PINS / pin["file"])
                    pins.append(entry)
            # Copying a pin puts it back in cliphist; it shows once, as the pin.
            pinned = {pin["text"] for pin in saved}
            entries = []
            for line in data.splitlines():
                identity, _, text = line.partition("\t")
                if query in text.casefold() and not (text in pinned and await self.same_as_pin(line, saved)):
                    entry = {"id": identity, "text": text, "raw": line}
                    label = clipboard_label(text)
                    if label:
                        entry["label"] = label
                    entries.append(entry)
                if len(entries) >= limit:
                    break
            paths = []
            for entry in pins + entries:
                text = entry["text"].strip()
                if "label" in entry:
                    continue
                if kind := clipboard_kind(text):
                    entry.update(kind)
                elif text.startswith(("/", "~/", "file://")) and not text.endswith("…"):
                    paths.append((entry, text))
            if paths:
                try:
                    kinds = await probe(path_kinds, [text for _, text in paths], timeout=1)
                except asyncio.TimeoutError:
                    # A hung network mount must not hold up the list; paths just go unmarked.
                    kinds = []
                for (entry, _), kind in zip(paths, kinds):
                    if kind:
                        entry.update(kind)
            return {"entries": entries, "pins": pins}
        if method == "clipboard.pin":
            entry = clipboard_entry(p.get("entry"))
            text = entry.partition("\t")[2]
            async with self.clipboard_pin_lock:
                pins = clipboard_pins()
                if any(pin["text"] == text for pin in pins) and not ambiguous_preview(text):
                    return {"done": True}
                if len(pins) >= MAX_PINS:
                    raise BackendError("invalid", f"Up to {MAX_PINS} pins. Unpin one first.")
                data = await run("cliphist", "decode", data=entry.encode())
                if len(data) > 20 * 1024 * 1024:
                    raise BackendError("invalid", "This entry is too large to pin.")
                # Two images of one size share a preview line; what they hold tells them apart.
                sha = hashlib.sha1(data).hexdigest()
                if any(pin["sha"] == sha for pin in pins):
                    return {"done": True}
                extension = ".png" if data.startswith(b"\x89PNG\r\n\x1a\n") else ".jpg" if data.startswith(b"\xff\xd8\xff") else ".data"
                identity = os.urandom(8).hex()
                CLIPBOARD_PINS.mkdir(parents=True, exist_ok=True, mode=0o700)
                path = CLIPBOARD_PINS / (identity + extension)
                with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "wb") as stream:
                    stream.write(data)
                atomic_json(CLIPBOARD_PINS / "pins.json", [{"pin": identity, "text": text, "file": path.name, "sha": sha}] + pins)
            return {"done": True}
        if method == "clipboard.unpin":
            async with self.clipboard_pin_lock:
                pins = clipboard_pins()
                pin = clipboard_pin(pins, p.get("pin"))
                atomic_json(CLIPBOARD_PINS / "pins.json", [x for x in pins if x is not pin])
                (CLIPBOARD_PINS / pin["file"]).unlink(missing_ok=True)
            # Removing (not just unpinning) also takes the copies the pin hid from history.
            if p.get("forget") is True:
                for line in (await run("cliphist", "list")).decode(errors="replace").splitlines():
                    if ENTRY_ID.fullmatch(line.partition("\t")[0]) and await self.same_as_pin(line, [pin]):
                        await run("cliphist", "delete", data=line.encode())
            return {"done": True}
        if method == "clipboard.text":
            # The full text for the preview (cliphist's list line is cut and flattened); "" for images and other data.
            if "pin" in p:
                data = pin_data(clipboard_pin(clipboard_pins(), p.get("pin")))
            else:
                entry = clipboard_entry(p.get("entry"))
                data = await run("cliphist", "decode", data=entry.encode())
            try:
                text = data[:65536].decode()
            except UnicodeDecodeError as error:
                # Cut inside a character: keep what came before it; anything else isn't text.
                text = data[:error.start].decode() if len(data) > 65536 and error.start > 65532 else ""
            return {"text": text, "cut": len(data) > 65536 and text != ""}
        if method in ("clipboard.copy", "clipboard.open") and "pin" in p:
            data = pin_data(clipboard_pin(clipboard_pins(), p.get("pin")))
            if method.endswith("copy"):
                await run("wl-copy", data=data)
                return {"done": True}
            try:
                text = data.decode().strip() if len(data) <= 65536 else ""
            except UnicodeDecodeError:
                text = ""
            try:
                target = await probe(clipboard_target, text, timeout=3)
            except asyncio.TimeoutError:
                raise BackendError("failed", "That location isn't responding.")
            if not target:
                raise BackendError("invalid", "This entry can't be opened.")
            return target
        if method in ("clipboard.copy", "clipboard.delete", "clipboard.open"):
            entry = clipboard_entry(p.get("entry"))
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
                    target = await probe(clipboard_target, text, timeout=3)
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
            return await self.sysmon.sample(nvidia=p.get("nvidia") is True, history=p.get("history") is True,
                                            processes=p.get("processes") if p.get("processes") in ("cpu", "memory") else None)
        if method == "system.end":
            pid, start = p.get("pid"), p.get("start")
            if type(pid) is not int or type(start) is not int:
                raise BackendError("invalid", "Choose a process.")
            # The start time must still match: the pid may have been reused since the list was read.
            found = self.sysmon.process(pid)
            if not found or found["start"] != start:
                raise BackendError("unavailable", "The process has already exited.")
            if pid in self.sysmon.lineage(os.getpid()) or found["name"] in sysmon.PROTECTED_PROCESSES:
                raise BackendError("unavailable", "Ending this would end your session.")
            return await quit_process(pid)
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
            window = await hypr_json("-j", "activewindow")
            if not window.get("at") or not window.get("size"):
                raise BackendError("unavailable", "No active window.")
            x, y = window["at"]
            w, h = window["size"]
            return ["-g", f"{x},{y} {w}x{h}"]
        if mode == "output":
            outputs = await hypr_json("-j", "monitors")
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


# The shell writes a request's id, then its method.
QUICK_REQUEST = re.compile(rb'"method"\s*:\s*"(settings\.|note\.|notifications\.|activity\.(update|focus)")')

async def watch_capslock(leds=Path("/sys/class/leds"), every=0.4, rescan=30):
    """Reports Caps Lock as it changes, from the keyboards' Caps Lock lights: the shell sees no keys outside its own
    windows. The kernel gives no notice when a light changes, so the few small files are read a few times a second;
    without any light (some laptops) it only looks again now and then for a keyboard plugged in later."""
    previous, files, scanned = None, [], -rescan
    while True:
        now = time.monotonic()
        if now - scanned >= rescan:
            files, scanned = sorted(leds.glob("*::capslock/brightness")), now
        if not files:
            await asyncio.sleep(rescan)
            continue
        on = False
        for path in files:
            try:
                on = on or int(path.read_text().strip() or 0) > 0
            except (OSError, ValueError):
                scanned = -rescan  # a keyboard went away
        if previous is not None and on != previous:
            emit("capslock", {"on": on})
        previous = on
        await asyncio.sleep(every)

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
    tasks, quick = set(), set()
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
                was_locked = backend.activity_locked
                backend.activity_locked = bool(changed["LockedHint"].value)
                resample()
                if was_locked and not backend.activity_locked and backend.bluetooth:
                    backend.bluetooth.trigger("unlocked")
        def on_sleep(sleeping):
            backend.activity_sleeping = bool(sleeping)
            resample()
            if not sleeping and backend.bluetooth:
                backend.bluetooth.trigger("woke from sleep", fresh=True)
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
        try:
            print(json.dumps(response, ensure_ascii=False), flush=True)
        except (UnicodeError, ValueError, TypeError) as error:
            # A file name that isn't valid text, or a value JSON can't carry: the request still gets its answer.
            log_unexpected(error, method if isinstance(method, str) else "Request")
            print(json.dumps({"id": identity, "ok": False, "error": {"code": "failed", "message": "The answer couldn't be sent."}}), flush=True)

    async def keep_watches():
        """Sets the D-Bus watches up again on a system bus that had to be reconnected: they died with the old one."""
        seen = backend.bus_generation
        while True:
            await asyncio.sleep(30)
            if backend.bus_generation != seen and backend.bus and backend.bus.connected:
                seen = backend.bus_generation
                for name, setup in (("Session watch", watch_session), ("Power profile watch", watch_power), ("Bluetooth watch", backend.watch_bluetooth)):
                    await watch_with_retries(name, setup, delays=())

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
    caps_watcher = asyncio.create_task(watch_capslock())
    equalizer_keeper = asyncio.create_task(keep_equalizer())
    session_watcher = asyncio.create_task(watch_with_retries("Session watch", watch_session))
    power_watcher = asyncio.create_task(watch_with_retries("Power profile watch", watch_power))
    bluetooth_watcher = asyncio.create_task(watch_with_retries("Bluetooth watch", backend.watch_bluetooth))
    clipboard_keeper = asyncio.create_task(keep_clipboard_history(clipboard))
    system_keeper = asyncio.create_task(keep_system_history(backend))
    watch_keeper = asyncio.create_task(keep_watches())
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
            # Up to 32 requests run at once; some wait a long time on purpose (a colour pick, a pairing, a VPN
            # password). Saving settings and notes is quick and never waits behind them.
            if len(tasks) >= 32 and not QUICK_REQUEST.search(line[:160]):
                await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
            task = asyncio.create_task(handle(line))
            if QUICK_REQUEST.search(line[:160]):
                quick.add(task)
                task.add_done_callback(quick.discard)
            else:
                tasks.add(task)
                task.add_done_callback(tasks.discard)
        if tasks or quick:
            await asyncio.gather(*tasks, *quick)
    finally:
        watcher.cancel()
        caps_watcher.cancel()
        session_watcher.cancel()
        power_watcher.cancel()
        bluetooth_watcher.cancel()
        if backend.bluetooth:
            backend.bluetooth.stop()
        clipboard_keeper.cancel()
        system_keeper.cancel()
        watch_keeper.cancel()
        equalizer_keeper.cancel()
        backend.equalizer.stop()
        clipboard.stop()
        leave_recording()
        transport.close()
    for bus in (backend.bus, backend.session_bus):
        if bus:
            bus.disconnect()

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "record-worker":
        sys.exit(record_worker(json.loads(sys.argv[2]), sys.argv[3]))
    asyncio.run(main())
