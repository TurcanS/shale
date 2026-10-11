import asyncio
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import AsyncMock, patch
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "helpers"))
spec = importlib.util.spec_from_file_location("backend", ROOT / "helpers/backend.py")
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)


class CalculatorTests(unittest.TestCase):
    def test_precedence_and_finite_math(self):
        self.assertEqual(b.calculate("(1920 / 1080) * 100")["value"], (1920 / 1080) * 100)
        self.assertEqual(b.calculate("-2 ** 2 + 11 // 3")["value"], -1)

    def test_results_are_displayed_without_float_noise(self):
        cases = {"0.1 + 0.2": "0.3", "10 / 3": "3.33333333333", "2 ** 60": "1152921504606846976", "6 * 7": "42",
                 "7 / 2": "3.5", "1 / 8": "0.125", "2 ** 0.5": "1.41421356237", "1e20 / 3": "3.33333333333e19", "4 / 2": "2"}
        for expression, expected in cases.items():
            with self.subTest(expression=expression):
                self.assertEqual(b.calculate(expression)["text"], expected)

    def test_rejects_execution_and_resource_exhaustion(self):
        for expression in ['__import__("os")', 'open("/etc/passwd")', "True + 1", "9 ** 99999", "1/0", "1e999", "[1] * 10000", "1 << 99999"]:
            with self.subTest(expression=expression), self.assertRaises(b.BackendError):
                b.calculate(expression)


class RequestReadingTests(unittest.IsolatedAsyncioTestCase):
    async def lines(self, data, limit=64):
        reader = asyncio.StreamReader(limit=limit + 1)
        reader.feed_data(data)
        reader.feed_eof()
        found = []
        while (line := await b.read_request(reader, limit)) != b"":
            found.append(line)
        return found

    async def test_oversized_lines_are_skipped_whole_and_reported_with_their_id(self):
        big = b'{"id": 7, "method": "clipboard.write", "params": {"text": "' + b"x" * 500 + b'"}}\n'
        found = await self.lines(b'{"id": 1}\n' + big + b'{"id": 2}\n')
        self.assertEqual(found, [b'{"id": 1}\n', (None, 7), b'{"id": 2}\n'])

    async def test_a_line_exactly_at_the_limit_and_one_without_a_newline(self):
        exact = b"y" * 64 + b"\n"
        self.assertEqual(await self.lines(exact + b'{"id": 3}'), [exact, b'{"id": 3}'])
        self.assertEqual(await self.lines(b"z" * 200), [(None, None)])


class BackendTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name)
        self.paths = patch.multiple(b, CONFIG=self.path / "config.json", STATE=self.path / "state", CACHE=self.path / "cache", RUNTIME=self.path / "runtime")
        self.paths.start()
        self.daemon = patch.object(b.wallpaper, "ensure", AsyncMock(return_value="hyprpaper"))
        self.daemon.start()
        self.backend = b.Backend()

    async def asyncTearDown(self):
        self.paths.stop()
        self.daemon.stop()
        self.tmp.cleanup()

    async def test_media_art_returns_a_local_cover(self):
        with patch.object(b.art, "_fetch", return_value=b"\x89PNG cover"):
            result = await self.backend.dispatch("media.art", {"url": "https://example.com/cover"})
        self.assertTrue(result["path"].startswith(str(self.path / "cache/art/")))
        with self.assertRaises(b.BackendError) as caught:
            await self.backend.dispatch("media.art", {"url": "ftp://example.com/cover"})
        self.assertEqual(caught.exception.code, "unavailable")
        with self.assertRaises(b.BackendError) as caught:
            await self.backend.dispatch("media.art", {"url": 5})
        self.assertEqual(caught.exception.code, "invalid")

    async def test_system_sample_reports_every_section(self):
        first = await self.backend.dispatch("system.sample", {})
        second = await self.backend.dispatch("system.sample", {})
        self.assertEqual(set(first), {"time", "uptime", "cpu", "memory", "disks", "network", "gpus", "fans"})
        self.assertGreaterEqual(second["time"], first["time"])
        self.assertTrue(all("bus" not in gpu and "device" not in gpu for gpu in second["gpus"]))

    async def test_grayscale_lua_toggle_and_restore(self):
        shader = str(ROOT / "assets/grayscale.frag")
        previous = '/tmp/custom "shader".frag'
        for before, after in ((previous, shader), (shader, previous)):
            with patch.object(b, "run", AsyncMock(side_effect=[
                json.dumps({"str": before}).encode(), b"ok",
                json.dumps({"str": after}).encode()
            ])) as run:
                result = await self.backend.dispatch("display.grayscale.toggle", {})
                self.assertEqual(result["enabled"], after == shader)
                command = run.call_args_list[1].args
                self.assertEqual(command[:2], ("hyprctl", "eval"))
                self.assertIn(''.join(f'\\{byte:03d}' for byte in after.encode()), command[2])

    async def test_settings_validation_and_recovery(self):
        result = await self.backend.dispatch("settings.set", {"settings": {"fontSize": 18, "clock24h": False}})
        self.assertEqual(result["fontSize"], 18)
        await self.backend.dispatch("settings.set", {"settings": {"fontSize": 14}})
        self.assertEqual(json.loads(b.CONFIG.with_suffix(".previous.json").read_text())["fontSize"], 18)
        for changes in [{"fontSize": 99}, {"dnd": "yes"}, {"captureDelay": -1}, {"recordingDirectory": "relative/path"}, {"version": 2}]:
            with self.assertRaises(b.BackendError):
                await self.backend.dispatch("settings.set", {"settings": changes})
        b.CONFIG.write_text("invalid json")
        self.assertIn("diagnostic", b.settings())
        self.assertEqual(b.settings()["fontSize"], 14)

    async def test_unreadable_settings_keep_backup_and_original(self):
        await self.backend.dispatch("settings.set", {"settings": {"fontSize": 18}})
        await self.backend.dispatch("settings.set", {"settings": {"fontSize": 16}})
        b.CONFIG.write_text('{"version": 1, "fontSize": 13}')
        loaded = b.settings()
        self.assertIn("diagnostic", loaded)
        # The UI echoes back everything it loaded, including the diagnostic.
        saved = await self.backend.dispatch("settings.set", {"settings": dict(loaded, dnd=True)})
        self.assertNotIn("diagnostic", saved)
        self.assertEqual(b.CONFIG.with_suffix(".invalid.json").read_text(), '{"version": 1, "fontSize": 13}')
        self.assertEqual(json.loads(b.CONFIG.with_suffix(".previous.json").read_text())["fontSize"], 18)
        self.assertNotIn("diagnostic", b.settings())
        self.assertTrue(b.settings()["dnd"])

    async def test_an_invalid_setting_costs_only_that_setting(self):
        original = json.dumps({"version": 1, "fontSize": 13, "dnd": True, "surfaceTone": "oled", "accentColor": "#a5c8ef", "futureKey": 5})
        b.CONFIG.write_text(original)
        loaded = b.settings()
        self.assertEqual((loaded["fontSize"], loaded["surfaceTone"]), (14, "charcoal"))
        self.assertEqual((loaded["dnd"], loaded["accentColor"], loaded["futureKey"]), (True, "#a5c8ef", 5))
        self.assertIn("fontSize, surfaceTone", loaded["diagnostic"])
        await self.backend.dispatch("settings.set", {"settings": dict(loaded, clock24h=False)})
        self.assertEqual(b.CONFIG.with_suffix(".invalid.json").read_text(), original)
        saved = json.loads(b.CONFIG.read_text())
        self.assertEqual(saved, {"version": 1, "dnd": True, "accentColor": "#a5c8ef", "futureKey": 5, "clock24h": False})
        self.assertNotIn("diagnostic", b.settings())

    def test_numeric_params_are_validated(self):
        self.assertEqual(b.number({"delay": "3"}, "delay", 0.2), 3.0)
        self.assertEqual(b.number({}, "delay", 0.2), 0.2)
        for bad in ("soon", None, [], "nan", "inf"):
            with self.subTest(bad=bad), self.assertRaises(b.BackendError) as caught:
                b.number({"delay": bad}, "delay", 0.2)
            self.assertEqual(caught.exception.code, "invalid")

    def test_runtime_fallback_is_private(self):
        runtime = sys.modules["runtime"]  # shared with scripts/session-action
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"XDG_RUNTIME_DIR": ""}), \
                patch.object(runtime, "Path", side_effect=lambda value: Path(directory) / Path(value).name):
            base = b.runtime_base()
            self.assertEqual(base.stat().st_mode & 0o777, 0o700)
            base.chmod(0o755)
            with self.assertRaises(SystemExit):
                b.runtime_base()

    async def test_brightness_prefers_the_panel_backlight_and_tolerates_none(self):
        sysfs = self.path / "backlight"
        with patch.object(b.Backend, "BACKLIGHT", sysfs):
            self.assertEqual(await self.backend.dispatch("brightness.get", {}), {"available": False})
            with self.assertRaises(b.BackendError):
                await self.backend.dispatch("brightness.set", {"value": 0.5})
            for name, kind, value in (("acpi_video0", "firmware", 0), ("amdgpu_bl1", "raw", 0), ("intel_backlight", "raw", 0)):
                (sysfs / name).mkdir(parents=True)
                (sysfs / name / "type").write_text(kind + "\n")
                (sysfs / name / "max_brightness").write_text("100")
                (sysfs / name / "brightness").write_text("40")
            (sysfs / "acpi_video0" / "max_brightness").write_text("0")  # a dead stand-in device
            result = await self.backend.dispatch("brightness.get", {})
            self.assertEqual(result, {"available": True, "value": 0.4, "device": "amdgpu_bl1"})

    async def test_missing_wifi_is_a_state_not_an_error(self):
        class DBusError(Exception):
            def __init__(self, kind):
                self.type = kind
        for failure, reason in ((b.BackendError("unavailable", "No NetworkManager Wi-Fi device is available."), "No NetworkManager Wi-Fi device is available."),
                                (DBusError("org.freedesktop.DBus.Error.ServiceUnknown"), "NetworkManager is not running.")):
            with self.subTest(reason=reason), patch.object(self.backend, "wifi", AsyncMock(side_effect=failure)):
                result = await self.backend.dispatch("wifi.list", {})
                self.assertEqual((result["available"], result["reason"], result["networks"]), (False, reason, []))
        with patch.object(self.backend, "wifi", AsyncMock(return_value={"networks": [], "state": "connected", "powered": True})):
            self.assertTrue((await self.backend.dispatch("wifi.list", {}))["available"])
        with patch.object(self.backend, "wifi", AsyncMock(side_effect=b.BackendError("invalid", "x"))), self.assertRaises(b.BackendError):
            await self.backend.dispatch("wifi.list", {})
        # A one-off failure (here a timeout) is an error, not "Wi-Fi doesn't exist here".
        with patch.object(self.backend, "wifi", AsyncMock(side_effect=DBusError("org.freedesktop.DBus.Error.NoReply"))), self.assertRaises(DBusError):
            await self.backend.dispatch("wifi.list", {})

    async def test_capabilities_report_tools_and_hardware(self):
        monitors = json.dumps([{"name": "HDMI-A-1"}]).encode()
        with patch.object(b, "run", AsyncMock(return_value=monitors)), patch.object(b.shutil, "which", side_effect=lambda x: x == "grim"):
            result = await self.backend.dispatch("capabilities", {})
        self.assertTrue(result["commands"]["grim"])
        self.assertFalse(result["commands"]["hyprlock"])
        self.assertFalse(result["builtinPanel"])
        with patch.object(b, "run", AsyncMock(return_value=json.dumps([{"name": "eDP-1"}]).encode())):
            self.assertTrue((await self.backend.dispatch("capabilities", {}))["builtinPanel"])
        with patch.object(b, "run", AsyncMock(side_effect=b.BackendError("unavailable", "no hyprctl"))):
            self.assertIsNone((await self.backend.dispatch("capabilities", {}))["builtinPanel"])

    async def test_only_changed_settings_are_written(self):
        await self.backend.dispatch("settings.set", {"settings": {"fontSize": 18, "dnd": False}})
        self.assertEqual(json.loads(b.CONFIG.read_text()), {"version": 1, "fontSize": 18})
        self.assertEqual(b.settings()["dnd"], False)

    def test_localized_user_dirs(self):
        home = self.path / "home"
        (home / ".config").mkdir(parents=True)
        dirs = home / ".config/user-dirs.dirs"
        with patch.dict(os.environ, {"XDG_CONFIG_HOME": ""}):
            self.assertEqual(b.user_dir("PICTURES", "~/Pictures", home), "~/Pictures")
            dirs.write_text('# comment\nXDG_PICTURES_DIR="$HOME/Bilder"\nXDG_VIDEOS_DIR="$HOME/"\nXDG_MUSIC_DIR="/data/music"\n')
            self.assertEqual(b.user_dir("PICTURES", "~/Pictures", home), "~/Bilder")
            self.assertEqual(b.user_dir("VIDEOS", "~/Videos", home), "~/Videos")
            self.assertEqual(b.user_dir("MUSIC", "~/Music", home), "/data/music")

    def test_terminal_command_prefix(self):
        installed = set()
        with patch.object(b.shutil, "which", side_effect=lambda name: name in installed), patch.dict(os.environ, {"TERMINAL": ""}):
            self.assertEqual(self.backend.terminal(), [])
            installed.update({"wezterm", "konsole"})
            self.assertEqual(self.backend.terminal(), ["wezterm", "start", "--"])
            installed.add("alacritty")
            self.assertEqual(self.backend.terminal(), ["alacritty", "-e"])
            installed.add("kitty")
            self.assertEqual(self.backend.terminal(), ["kitty"])
            with patch.dict(os.environ, {"TERMINAL": "konsole"}):
                self.assertEqual(self.backend.terminal(), ["konsole", "-e"])
            with patch.dict(os.environ, {"TERMINAL": "missing-term"}):
                self.assertEqual(self.backend.terminal(), ["kitty"])

    async def test_unknown_settings_keys_are_not_saved(self):
        await self.backend.dispatch("settings.set", {"settings": {"diagnostic": "stale", "bogus": 1, "dnd": True}})
        saved = json.loads(b.CONFIG.read_text())
        self.assertNotIn("diagnostic", saved)
        self.assertNotIn("bogus", saved)
        self.assertTrue(saved["dnd"])

    async def test_color_settings_persist_and_reject_unreadable_accents(self):
        changed = await self.backend.dispatch("settings.set", {"accentColor": "#a5c8ef", "surfaceTone": "midnight"})
        self.assertEqual(changed["accentColor"], "#a5c8ef")
        self.assertEqual(changed["surfaceTone"], "midnight")
        self.assertEqual(b.settings()["accentColor"], "#a5c8ef")
        for color in ("blue", "#abc", "#123456", "#000000", "#ffffff00", "#12345g"):
            with self.subTest(color=color), self.assertRaises(b.BackendError):
                await self.backend.dispatch("settings.set", {"accentColor": color})
        with self.assertRaises(b.BackendError):
            await self.backend.dispatch("settings.set", {"surfaceTone": "transparent"})
        self.assertEqual(b.settings()["accentColor"], "#a5c8ef")
        b.CONFIG.write_text(json.dumps({"version": 1, "accentColor": "#000000"}))
        self.assertEqual(b.settings()["accentColor"], "#9ad6c6")
        self.assertIn("diagnostic", b.settings())

    async def test_wallpaper_accent_settings_keep_a_readable_manual_accent(self):
        changed = await self.backend.dispatch("settings.set", {"accentFromWallpaper": True, "accentManual": "#c8b4e9"})
        self.assertEqual((changed["accentFromWallpaper"], changed["accentManual"]), (True, "#c8b4e9"))
        for changes in [{"accentManual": "#101010"}, {"accentManual": "lilac"}, {"accentFromWallpaper": "yes"}]:
            with self.subTest(changes=changes), self.assertRaises(b.BackendError):
                await self.backend.dispatch("settings.set", changes)
        b.CONFIG.write_text(json.dumps({"version": 1, "accentManual": "#000000"}))
        self.assertEqual(b.settings()["accentManual"], "#9ad6c6")

    async def test_active_wallpapers_tolerate_a_missing_hyprpaper(self):
        with patch.object(b.wallpaper, "current", return_value="hyprpaper"):
            with patch.object(b.wallpaper, "active", AsyncMock(return_value={"eDP-1": "/w/a.png"})):
                self.assertEqual(await self.backend.dispatch("wallpaper.active", {}), {"active": {"eDP-1": "/w/a.png"}})
            with patch.object(b.wallpaper, "active", AsyncMock(side_effect=b.BackendError("failed", "hyprpaper is not running"))):
                self.assertEqual(await self.backend.dispatch("wallpaper.active", {}), {"active": {}})

    @patch.object(b.wallpaper, "catalog", lambda folder: {"directory": folder, "entries": [], "limited": False})
    async def test_reading_wallpapers_never_starts_a_daemon(self):
        with patch.object(b.wallpaper, "current", return_value=None), patch.object(b.wallpaper, "active", AsyncMock()) as active:
            with patch.object(b.wallpaper, "installed", return_value=True):
                self.assertEqual(await self.backend.dispatch("wallpaper.active", {}), {"active": {}})
                listed = await self.backend.dispatch("wallpaper.list", {})
                self.assertEqual((listed["active"], listed.get("warning")), ({}, None))
            with patch.object(b.wallpaper, "installed", return_value=False):
                self.assertIn("Install hyprpaper", (await self.backend.dispatch("wallpaper.list", {}))["warning"])
        with patch.object(b.wallpaper, "current", return_value="foreign"):
            self.assertIn("Another wallpaper tool", (await self.backend.dispatch("wallpaper.list", {}))["warning"])
        b.wallpaper.ensure.assert_not_awaited()
        active.assert_not_awaited()

    async def test_weather_settings_are_validated(self):
        place = {"name": "Paris", "region": "France", "latitude": 48.85, "longitude": 2.35}
        changed = await self.backend.dispatch("settings.set", {"weatherLocation": place, "weatherUnits": "imperial"})
        self.assertEqual((changed["weatherLocation"], changed["weatherUnits"]), (place, "imperial"))
        for changes in [{"weatherLocation": {"name": "Paris"}}, {"weatherLocation": []}, {"weatherUnits": "kelvin"}]:
            with self.subTest(changes=changes), self.assertRaises(b.BackendError):
                await self.backend.dispatch("settings.set", changes)
        with self.assertRaises(b.BackendError) as caught:
            await self.backend.dispatch("weather.get", {"location": {}, "units": "metric"})
        self.assertEqual(caught.exception.code, "weather")

    async def test_launcher_settings_are_validated(self):
        changed = await self.backend.dispatch("settings.set", {"searchEngine": "brave", "emojiUsage": {"😀": 3}})
        self.assertEqual((changed["searchEngine"], changed["emojiUsage"]), ("brave", {"😀": 3}))
        for changes in [{"searchEngine": "altavista"}, {"emojiUsage": []}]:
            with self.subTest(changes=changes), self.assertRaises(b.BackendError):
                await self.backend.dispatch("settings.set", changes)

    async def test_equalizer_settings_persist_and_reject_invalid_bands(self):
        bands = [6, 5.5, 4.5, 3, 1, 0, 0, 0, 0, 0]
        changed = await self.backend.dispatch("settings.set", {"eqEnabled": True, "eqPreset": "bass", "eqBands": bands, "visualizer": False})
        self.assertEqual((changed["eqEnabled"], changed["eqPreset"], changed["eqBands"], changed["visualizer"]), (True, "bass", bands, False))
        self.assertEqual(b.settings()["eqBands"], bands)
        for changes in [{"eqBands": [0] * 9}, {"eqBands": [20] + [0] * 9}, {"eqBands": [False] * 10}, {"eqBands": "flat"},
                        {"eqPreset": "rock"}, {"eqEnabled": 1}]:
            with self.subTest(changes=changes), self.assertRaises(b.BackendError):
                await self.backend.dispatch("settings.set", changes)
        b.CONFIG.write_text(json.dumps({"version": 1, "eqBands": [99] * 10}))
        self.assertEqual(b.settings()["eqBands"], [0] * 10)
        self.assertIn("diagnostic", b.settings())

    async def test_equalizer_apply_validates_and_toggles_the_filter(self):
        for params in [{"enabled": "yes", "bands": [0] * 10}, {"enabled": True, "bands": [0] * 3}]:
            with self.subTest(params=params), self.assertRaises(b.BackendError):
                await self.backend.dispatch("eq.apply", params)
        eq = self.backend.equalizer
        state = {"running": False}

        async def start(run, bands):
            state["running"], eq.bands = True, bands
        with patch.object(type(eq), "running", property(lambda _: state["running"])), \
                patch.object(eq, "start", AsyncMock(side_effect=start)) as started, \
                patch.object(eq, "update", AsyncMock()) as updated, \
                patch.object(eq, "stop", side_effect=lambda: state.update(running=False)) as stopped:
            result = await self.backend.dispatch("eq.apply", {"enabled": True, "bands": [3] + [0] * 9})
            self.assertEqual(result, {"enabled": True, "bands": [3.0] + [0.0] * 9})
            await self.backend.dispatch("eq.apply", {"enabled": True, "bands": [3] + [0] * 9})
            updated.assert_not_called()
            await self.backend.dispatch("eq.apply", {"enabled": True, "bands": [4] + [0] * 9})
            updated.assert_awaited_once()
            self.assertEqual(started.await_count, 1)
            result = await self.backend.dispatch("eq.apply", {"enabled": False, "bands": [4] + [0] * 9})
            stopped.assert_called_once()
            self.assertFalse(result["enabled"])
        for error in (RuntimeError("PipeWire could not start the equalizer."), ValueError("Expecting value: line 1 column 1")):
            with self.subTest(error=error), patch.object(eq, "start", AsyncMock(side_effect=error)):
                with self.assertRaises(b.BackendError) as raised:
                    await self.backend.dispatch("eq.apply", {"enabled": True, "bands": [0] * 10})
                # Unreadable pw-dump output is a failure, not invalid bands.
                self.assertEqual(raised.exception.code, "failed")

    async def test_clipboard_data_uses_stdin_and_preserves_binary(self):
        run = AsyncMock(side_effect=[b"\x89PNG\x00binary", b""])
        with patch.object(b, "run", run):
            await self.backend.dispatch("clipboard.copy", {"entry": "12\t[image]"})
        self.assertEqual(run.call_args_list[0].args, ("cliphist", "decode"))
        self.assertEqual(run.call_args_list[0].kwargs["data"], b"12\t[image]")
        self.assertEqual(run.call_args_list[1].kwargs["data"], b"\x89PNG\x00binary")
        with self.assertRaises(b.BackendError):
            await self.backend.dispatch("clipboard.delete", {"entry": "12\tx\n13\ty"})

    async def test_clipboard_unicode_search_and_limit(self):
        with patch.object(b, "run", AsyncMock(return_value="1\tRésumé\n2\tOther\n3\trésumé again\n".encode())):
            result = await self.backend.dispatch("clipboard.list", {"query": "RÉSUMÉ", "limit": 1})
        self.assertEqual([x["id"] for x in result["entries"]], ["1"])

    async def test_clipboard_binary_entries_get_readable_labels(self):
        listing = "4\t[[ binary data 1.2 MiB png 1920x1080 ]]\n5\t[[ binary data 12 KiB pdf ]]\n6\tplain text\n"
        with patch.object(b, "run", AsyncMock(return_value=listing.encode())):
            result = await self.backend.dispatch("clipboard.list", {"query": "", "limit": 10})
        labels = [entry.get("label") for entry in result["entries"]]
        self.assertEqual(labels, ["Image · PNG · 1920×1080 · 1.2 MiB", "Data · PDF · 12 KiB", None])
        self.assertEqual(result["entries"][0]["text"], "[[ binary data 1.2 MiB png 1920x1080 ]]")

    async def test_history_is_opt_in_and_strips_live_actions(self):
        await self.backend.dispatch("notifications.set", {"entries": [{"body": "private"}]})
        self.assertFalse((b.STATE / "notifications.json").exists())
        await self.backend.dispatch("settings.set", {"persistNotifications": True})
        entry = {"id": 1, "body": "hello", "timestamp": b.time.time() * 1000, "actions": ["unsafe"]}
        await self.backend.dispatch("notifications.set", {"entries": [entry, {"timestamp": 1, "body": "expired"}]})
        result = await self.backend.dispatch("notifications.get", {})
        self.assertEqual(len(result["entries"]), 1)
        self.assertNotIn("actions", result["entries"][0])

    async def test_activity_tracking_is_opt_in(self):
        store = b.STATE / "activity.sqlite3"
        sample = {"unlocked": True, "idle": False, "windows": [{"id": "a", "app": "kitty"}], "focused": "a"}
        self.assertEqual((await self.backend.dispatch("settings.get", {}))["activityTracking"], "ask")
        self.assertEqual(await self.backend.dispatch("activity.update", sample), {"tracking": False})
        self.assertFalse(store.exists())
        for value in ("yes", True, ""):
            with self.subTest(value=value), self.assertRaises(b.BackendError):
                await self.backend.dispatch("settings.set", {"activityTracking": value})
        await self.backend.dispatch("settings.set", {"activityTracking": "on"})
        self.assertTrue((await self.backend.dispatch("activity.update", sample))["active"])
        self.assertIsNotNone(self.backend.activity_snapshot)
        await self.backend.dispatch("settings.set", {"activityTracking": "off"})
        self.assertIsNone(self.backend.activity)
        self.assertIsNone(self.backend.activity_snapshot)
        self.assertEqual(await self.backend.dispatch("activity.update", sample), {"tracking": False})
        self.assertIsNone(self.backend.activity)
        self.assertEqual((await self.backend.dispatch("activity.overview", {"weekStart": 0}))["paused"], False)
        with self.assertRaises(b.BackendError):
            await self.backend.dispatch("activity.week", {"date": "2025-06-03", "weekStart": 9})
        self.backend.close_activity()

    async def test_existing_activity_history_keeps_tracking_on(self):
        store = b.activity.ActivityStore(b.STATE / "activity.sqlite3")
        store.ingest({"unlocked": True, "idle": False})
        store.db.close()
        b.CONFIG.write_text(json.dumps({"version": 1, "fontSize": 16}))
        self.assertEqual((await self.backend.dispatch("settings.get", {}))["activityTracking"], "on")
        self.assertEqual(json.loads(b.CONFIG.read_text()), {"version": 1, "fontSize": 16, "activityTracking": "on"})
        # A choice already made is never overridden.
        await self.backend.dispatch("settings.set", {"activityTracking": "off"})
        self.assertEqual((await self.backend.dispatch("settings.get", {}))["activityTracking"], "off")
        # Only a cleanly loaded file is upgraded: an unreadable one, or one with a rejected value, may hold
        # another choice, so tracking stays off until the user answers.
        for text in ("invalid json", json.dumps({"version": 1, "fontSize": 13}),
                     json.dumps({"version": 1, "activityTracking": "never"})):
            with self.subTest(text=text):
                b.CONFIG.write_text(text)
                current = await self.backend.dispatch("settings.get", {})
                self.assertEqual(current["activityTracking"], "ask")
                self.assertIn("diagnostic", current)
                self.assertEqual(b.CONFIG.read_text(), text)
                self.assertEqual(await self.backend.dispatch("activity.update", {"unlocked": True, "idle": False}), {"tracking": False})

    async def test_recording_audio_choice(self):
        self.assertEqual(b.settings()["recordAudio"], "none")
        changed = await self.backend.dispatch("settings.set", {"recordAudio": "microphone", "recordingDirectory": str(self.path / "videos")})
        self.assertEqual(changed["recordAudio"], "microphone")
        for value in ("both", True, "default"):
            with self.subTest(value=value), self.assertRaises(b.BackendError):
                await self.backend.dispatch("settings.set", {"recordAudio": value})
        commands = []
        async def start(*args, **_):
            commands.append(json.loads(args[-2]))
            b.atomic_json(b.RUNTIME / "recording.json", {"pid": 0, "path": args[-1], "active": True})
        with patch.object(b, "run", AsyncMock(side_effect=start)), patch.object(b.shutil, "which", return_value="/usr/bin/wf-recorder"), \
                patch.object(self.backend, "geometry", AsyncMock(return_value=["-o", "eDP-1"])):
            # Older shells sent a flag that meant system audio.
            for audio in ("none", "system", "microphone", True, False):
                (b.RUNTIME / "recording.json").unlink(missing_ok=True)
                await self.backend.dispatch("capture.record.start", {"mode": "output", "audio": audio})
            with self.assertRaises(b.BackendError):
                await self.backend.dispatch("capture.record.start", {"mode": "output", "audio": "both"})
        audio = [[part for part in command if part.startswith("--audio")] for command in commands]
        self.assertEqual(audio, [[], ["--audio=@DEFAULT_MONITOR@"], ["--audio=@DEFAULT_SOURCE@"], ["--audio=@DEFAULT_MONITOR@"], []])
        self.assertTrue(all(command[:3] == ["wf-recorder", "-o", "eDP-1"] for command in commands))

    async def test_capture_geometry_and_cancel(self):
        with patch.object(b, "run", AsyncMock(return_value=b'{"at":[-1920,24],"size":[800,600]}')):
            self.assertEqual(await self.backend.geometry("window"), ["-g", "-1920,24 800x600"])
        with patch.object(b, "run", AsyncMock(side_effect=b.BackendError("cancelled", "Action cancelled."))):
            with self.assertRaises(b.BackendError) as ctx:
                await self.backend.geometry("region")
            self.assertEqual(ctx.exception.code, "cancelled")

    async def test_pairing_reply_does_not_need_finished_pair_request(self):
        self.backend.pairing_reply = asyncio.get_running_loop().create_future()
        await self.backend.dispatch("bluetooth.reply", {"accept": True, "value": "123456"})
        self.assertEqual((await self.backend.pairing_reply)["value"], "123456")

    async def test_unknown_method_fails(self):
        with self.assertRaises(b.BackendError):
            await self.backend.dispatch("system.exec", {"command": "anything"})

    async def test_power_profiles_without_introspected_properties(self):
        variant = lambda value: SimpleNamespace(value=value)
        proxy = SimpleNamespace(call_get_all=AsyncMock(return_value={"ActiveProfile": variant("balanced"), "Profiles": variant([{"Profile":variant("balanced")},{"Profile":variant("power-saver")}])}))
        with patch.object(self.backend, "interface", AsyncMock(return_value=proxy)) as interface:
            result = await self.backend.dispatch("power.profiles", {})
        self.assertEqual({k: result[k] for k in ("active", "profiles")}, {"active":"balanced","profiles":["balanced","power-saver"]})
        self.assertIsInstance(result["tuned"], bool)
        self.assertEqual(interface.call_args.args[2], "org.freedesktop.DBus.Properties")

    def fake_hyprland(self, state):
        """A stand-in hyprctl that understands getoption, monitors and the evals the saver sends."""
        calls = []
        async def run(*args, **_):
            calls.append(args)
            if args[1] == "getoption":
                return json.dumps({"bool": state[args[2].split(":")[1]]}).encode()
            if args[1] == "monitors":
                return json.dumps([{"name": "eDP-1", "width": 1920, "height": 1080, "refreshRate": state["rate"], "x": 0, "y": 0, "scale": 1.0,
                                    "transform": 1, "currentFormat": "XRGB2101010", "availableModes": ["1920x1080@144.00Hz", "1920x1080@60.00Hz"]},
                                   {"name": "HDMI-A-1", "width": 2560, "height": 1440, "refreshRate": 165.0, "x": 1920, "y": 0, "scale": 1.0,
                                    "availableModes": ["2560x1440@165.00Hz", "2560x1440@60.00Hz"]}]).encode()
            code = args[2]
            for option in ("blur", "shadow"):
                if option + " = {enabled" in code:
                    state[option] = "true" in code
            if code.startswith("hl.monitor"):
                state["rate"] = float(code.split("@")[1].split('"')[0])
            return b"ok"
        return calls, run

    async def test_power_saver_trims_compositor_and_restores_it(self):
        state = {"blur": True, "shadow": False, "rate": 144.003}
        calls, run = self.fake_hyprland(state)
        with patch.object(b, "run", run):
            await self.backend.dispatch("power.compositor", {"saver": True, "refresh": True})
            self.assertEqual(state, {"blur": False, "shadow": False, "rate": 60.0})
            self.assertFalse(any("HDMI" in str(call) for call in calls), "external displays keep their refresh rate")
            # hl.monitor replaces the whole rule, so the rotation and 10-bit colour go along.
            code = next(call[2] for call in calls if call[2].startswith("hl.monitor"))
            self.assertIn("transform = 1", code)
            self.assertIn("bitdepth = 10", code)
            # A Hyprland config reload brings everything back; applying again must not lose the originals.
            state.update(blur=True, rate=144.003)
            await self.backend.dispatch("power.compositor", {"saver": True, "refresh": True})
            await self.backend.dispatch("power.compositor", {"saver": False})
        self.assertEqual(state, {"blur": True, "shadow": False, "rate": 144.0})
        self.assertFalse((b.RUNTIME / "power-saver.json").exists())

    async def test_power_saver_refresh_can_be_kept(self):
        state = {"blur": True, "shadow": True, "rate": 144.003}
        _, run = self.fake_hyprland(state)
        with patch.object(b, "run", run):
            await self.backend.dispatch("power.compositor", {"saver": True, "refresh": True})
            await self.backend.dispatch("power.compositor", {"saver": True, "refresh": False})
            self.assertEqual(state, {"blur": False, "shadow": False, "rate": 144.0})
            await self.backend.dispatch("power.compositor", {"saver": False})
        self.assertEqual(state, {"blur": True, "shadow": True, "rate": 144.0})


class DBusError(Exception):
    """Stands in for dbus_next.errors.DBusError: a stable type and a free-form text."""
    def __init__(self, kind, text=""):
        super().__init__(text)
        self.type = kind


class SystemServiceTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name)
        self.paths = patch.multiple(b, CONFIG=self.path / "config.json", STATE=self.path / "state", RUNTIME=self.path / "runtime")
        self.paths.start()
        self.backend = b.Backend()

    async def asyncTearDown(self):
        self.paths.stop()
        self.tmp.cleanup()

    async def test_session_is_found_by_id_then_pid_then_seat(self):
        manager = SimpleNamespace(call_get_session=AsyncMock(return_value="/session/by_id"),
                                  call_get_session_by_pid=AsyncMock(return_value="/session/by_pid"),
                                  call_list_sessions=AsyncMock(return_value=[["c1", os.getuid() + 1, "other", "seat0", "/session/other"],
                                                                             ["3", os.getuid(), "me", "", "/session/ssh"],
                                                                             ["2", os.getuid(), "me", "seat0", "/session/seat"]]))
        with patch.object(self.backend, "interface", AsyncMock(return_value=manager)):
            with patch.dict(os.environ, {"XDG_SESSION_ID": "7"}):
                self.assertEqual(await self.backend.session_path(), "/session/by_id")
                manager.call_get_session.assert_awaited_with("7")
                manager.call_get_session.side_effect = DBusError("org.freedesktop.login1.NoSuchSession")
                self.assertEqual(await self.backend.session_path(), "/session/by_pid")
                manager.call_get_session_by_pid.assert_awaited_with(os.getpid())
            with patch.dict(os.environ, {"XDG_SESSION_ID": ""}):
                manager.call_get_session.reset_mock()
                manager.call_get_session_by_pid.side_effect = DBusError("org.freedesktop.login1.NoSessionForPID")
                # Started from a systemd user unit: neither applies, so the user's seat session it is.
                self.assertEqual(await self.backend.session_path(), "/session/seat")
                manager.call_get_session.assert_not_awaited()

    async def test_locked_hints_reach_logind_in_the_order_sent(self):
        sent, first = [], asyncio.Event()

        async def set_locked_hint(locked):
            if locked:
                await first.wait()  # the lock is slow; the unlock sent after it must still land last
            sent.append(locked)
        session = SimpleNamespace(call_set_locked_hint=set_locked_hint)
        with patch.object(self.backend, "interface", AsyncMock(return_value=session)), \
                patch.object(self.backend, "session_path", AsyncMock(return_value="/session")):
            lock = asyncio.create_task(self.backend.dispatch("session.lockedHint", {"locked": True}))
            unlock = asyncio.create_task(self.backend.dispatch("session.lockedHint", {"locked": False}))
            await asyncio.sleep(0.01)
            first.set()
            await asyncio.gather(lock, unlock)
        self.assertEqual(sent, [True, False])

    async def test_dbus_calls_time_out_but_signals_pass_through(self):
        async def call_slow():
            await asyncio.sleep(1)
        proxy = SimpleNamespace(call_slow=call_slow, call_quick=AsyncMock(return_value=3), on_properties_changed="handler")
        timed = b.TimedInterface(proxy, 0.01)
        self.assertEqual(await timed.call_quick(), 3)
        self.assertEqual(timed.on_properties_changed, "handler")
        with self.assertRaises(b.BackendError) as raised:
            await timed.call_slow()
        self.assertEqual(raised.exception.code, "timeout")

    def test_wpa3_only_networks_use_sae(self):
        self.assertEqual(b.key_management(0x400), "sae")
        self.assertEqual(b.key_management(0x100 | 0x400), "wpa-psk")  # WPA2/WPA3 transition
        self.assertEqual(b.key_management(0x100), "wpa-psk")
        self.assertEqual(b.key_management(0), "wpa-psk")

    async def test_new_wifi_connection_picks_its_key_management(self):
        from dbus_next import Variant
        nm = "org.freedesktop.NetworkManager"
        added = []

        def interface_for(rsn):
            async def add_and_activate(config, device, ap):
                added.append(config)
                return "/settings/1", "/active/1"
            objects = {
                ("/org/freedesktop/NetworkManager", nm): SimpleNamespace(call_get_devices=AsyncMock(return_value=["/dev/1"]),
                                                                         call_add_and_activate_connection=add_and_activate),
                ("/org/freedesktop/NetworkManager/Settings", nm + ".Settings"): SimpleNamespace(call_list_connections=AsyncMock(return_value=[])),
                ("/dev/1", nm + ".Device.Wireless"): SimpleNamespace(call_get_all_access_points=AsyncMock(return_value=["/ap/1"])),
            }
            values = {"WirelessEnabled": True, "DeviceType": 2, "ActiveAccessPoint": "/", "Ssid": b"home"}

            async def get(interface, prop):
                state = 2 if interface.endswith("Connection.Active") else 30
                return Variant("b", values[prop]) if prop == "WirelessEnabled" else SimpleNamespace(value=values.get(prop, state))
            ap = {"Ssid": SimpleNamespace(value=b"home"), "WpaFlags": SimpleNamespace(value=0), "RsnFlags": SimpleNamespace(value=rsn),
                  "Flags": SimpleNamespace(value=1), "Strength": SimpleNamespace(value=70)}
            properties = SimpleNamespace(call_get=get, call_get_all=AsyncMock(return_value=ap))

            async def interface(name, path, kind, **_):
                return properties if kind == "org.freedesktop.DBus.Properties" else objects.get((path, kind), SimpleNamespace())
            return interface
        for rsn, expected in ((0x400, "sae"), (0x500, "wpa-psk")):
            with self.subTest(rsn=rsn), patch.object(self.backend, "interface", interface_for(rsn)):
                self.assertEqual(await self.backend.dispatch("wifi.connect", {"path": "/ap/1", "password": "secret"}), {"done": True})
                self.assertEqual(added[-1]["802-11-wireless-security"]["key-mgmt"].value, expected)

    def enable_equalizer(self, bands=None):
        b.CONFIG.write_text(json.dumps({"version": 1, "eqEnabled": True, "eqBands": bands or [2] + [0] * 9}))

    async def test_equalizer_restore_retries_until_pipewire_is_up(self):
        self.enable_equalizer()
        eq = self.backend.equalizer
        with patch.object(eq, "start", AsyncMock(side_effect=[RuntimeError("The equalizer did not appear in PipeWire."), None])) as start, \
                patch("sys.stderr"):
            self.assertTrue(await self.backend.resume_equalizer((0, 0, 0)))
        self.assertEqual(start.await_count, 2)
        self.assertEqual(start.await_args.args[1], [2.0] + [0.0] * 9)
        with patch.object(eq, "start", AsyncMock(side_effect=b.BackendError("unavailable", "Install pw-dump"))) as start, patch("sys.stderr"):
            self.assertFalse(await self.backend.resume_equalizer((0, 0)))
        self.assertEqual(start.await_count, 2)
        b.CONFIG.write_text(json.dumps({"version": 1}))
        with patch.object(eq, "start", AsyncMock()) as start:
            self.assertTrue(await self.backend.resume_equalizer((0,)))
        start.assert_not_awaited()

    async def test_equalizer_restore_leaves_the_shell_in_charge(self):
        self.enable_equalizer()

        async def start(run, bands):
            self.backend.eq_requests += 1  # the shell sent eq.apply meanwhile
            raise RuntimeError("PipeWire could not start the equalizer.")
        with patch.object(self.backend.equalizer, "start", AsyncMock(side_effect=start)) as started, patch("sys.stderr"):
            self.assertTrue(await self.backend.resume_equalizer((0, 0, 0)))
        self.assertEqual(started.await_count, 1)

    async def test_a_filter_that_exits_is_restarted_or_reported(self):
        self.enable_equalizer()
        eq = self.backend.equalizer
        dead = SimpleNamespace(poll=lambda: 1, pid=4242)
        with patch.object(b, "emit") as emit, patch("sys.stderr"):
            with patch.object(eq, "start", AsyncMock()) as start:
                eq.process, eq.bands = dead, [2.0] + [0.0] * 9
                await self.backend.check_equalizer((0,))
                start.assert_awaited_once()
                emit.assert_not_called()
            with patch.object(eq, "start", AsyncMock(side_effect=RuntimeError("PipeWire could not start the equalizer."))):
                eq.process = dead
                await self.backend.check_equalizer((0, 0))
            emit.assert_called_once_with("eq", {"enabled": False, "bands": None})
            # A filter the shell stopped on purpose is not brought back.
            emit.reset_mock()
            with patch.object(eq, "start", AsyncMock()) as start:
                await self.backend.check_equalizer((0,))
            start.assert_not_awaited()

    async def test_clipboard_keeper_survives_a_failed_watcher_start(self):
        calls = []

        class Stop(Exception):
            pass

        def ensure():
            calls.append(1)
            if len(calls) == 1:
                raise OSError(11, "Resource temporarily unavailable")
            if len(calls) == 3:
                raise Stop()
        with patch("sys.stderr") as stderr, self.assertRaises(Stop):
            await b.keep_clipboard_history(SimpleNamespace(ensure=ensure), interval=0)
        self.assertEqual(len(calls), 3)
        self.assertIn("Resource temporarily unavailable", "".join(str(c.args[0]) for c in stderr.write.call_args_list))

    async def test_watchers_retry_while_their_service_is_missing(self):
        setup = AsyncMock(side_effect=[DBusError("org.freedesktop.DBus.Error.ServiceUnknown"), DBusError("org.freedesktop.DBus.Error.NameHasNoOwner"), None])
        with patch("sys.stderr") as stderr:
            await b.watch_with_retries("Power profile watch", setup, delays=(0, 0, 0, 0))
        self.assertEqual(setup.await_count, 3)
        stderr.write.assert_not_called()
        # Something unexpected is logged and tried again; a deliberate verdict (no dbus-next) stops it.
        setup = AsyncMock(side_effect=[KeyError("LockedHint"), b.BackendError("unavailable", "Install python-dbus-next to enable system controls.")])
        with patch("sys.stderr") as stderr:
            await b.watch_with_retries("Session watch", setup, delays=(0, 0, 0, 0))
        self.assertEqual(setup.await_count, 2)
        logged = "".join(str(c.args[0]) for c in stderr.write.call_args_list)
        self.assertIn("Traceback", logged)
        self.assertIn("KeyError", logged)
        self.assertIn("python-dbus-next", logged)

    def test_unexpected_errors_are_logged_without_dbus_text(self):
        for error, shown, hidden in ((ValueError("bad pw-dump output"), "bad pw-dump output", None),
                                     (DBusError("org.freedesktop.NetworkManager.Failed", "psk hunter2 rejected"), "org.freedesktop.NetworkManager.Failed", "hunter2")):
            try:
                raise error
            except Exception as caught:
                with patch("sys.stderr") as stderr:
                    b.log_unexpected(caught, "wifi.connect")
            logged = "".join(str(c.args[0]) for c in stderr.write.call_args_list)
            with self.subTest(error=type(error).__name__):
                self.assertIn("wifi.connect failed", logged)
                self.assertIn("test_backend.py", logged)  # the traceback
                self.assertIn(shown, logged)
                if hidden:
                    self.assertNotIn(hidden, logged)


class TrayQuitTests(unittest.IsolatedAsyncioTestCase):
    def bus(self, items):
        """A session bus with tray items {"service/path": (id, title)}; services map to pids 100, 101..."""
        pids = {entry.partition("/")[0]: 100 + i for i, entry in enumerate(items)}

        async def call(destination, path, interface, member, signature, body):
            if member == "GetConnectionUnixProcessID":
                return [pids[body[0]]]
            if destination == "org.kde.StatusNotifierWatcher":
                return [SimpleNamespace(value=list(items))]
            for entry, (item_id, title) in items.items():
                service, _, rest = entry.partition("/")
                if service == destination and path == ("/" + rest if rest else "/StatusNotifierItem"):
                    return [SimpleNamespace(value=item_id if body[1] == "Id" else title)]
            raise b.BackendError("unavailable", "org.freedesktop.DBus.Error.ServiceUnknown")
        return call

    async def test_finds_the_owner_by_id_and_title(self):
        call = self.bus({":1.5/StatusNotifierItem": ("TelegramDesktop", "Telegram"), ":1.9": ("steam", "Steam"),
                         ":1.7/org/ayatana/NotificationItem/x": ("steam", "Steam Beta"), ":1.8": ("gone", "")})
        self.assertEqual(await b.tray_owner(call, "TelegramDesktop"), 100)
        self.assertEqual(await b.tray_owner(call, "steam", "Steam Beta"), 102)
        self.assertEqual(await b.tray_owner(call, "steam", "Unknown"), 101)  # no title match: the first one
        with self.assertRaises(b.BackendError):
            await b.tray_owner(call, "missing")

    async def test_quit_refuses_protected_and_foreign_processes(self):
        killed = []
        with tempfile.TemporaryDirectory() as temp:
            proc = Path(temp)
            (proc / "4242").mkdir()
            (proc / "4242/cgroup").write_text("0::/user.slice/user@1000.service/app.slice/app-hyprland-telegram-1.scope\n")
            for pid in (0, 1, os.getpid(), os.getppid(), "4242"):
                with self.subTest(pid=pid), self.assertRaises(b.BackendError):
                    await b.quit_process(pid, proc, kill=lambda *a: killed.append(a))
            with self.assertRaisesRegex(b.BackendError, "already exited"):
                await b.quit_process(5555, proc, kill=lambda *a: killed.append(a))
            with patch.object(b.os, "getuid", return_value=os.getuid() + 1), self.assertRaisesRegex(b.BackendError, "another user"):
                await b.quit_process(4242, proc, kill=lambda *a: killed.append(a))
            self.assertEqual(killed, [])
            self.assertEqual(await b.quit_process(4242, proc, kill=lambda *a: killed.append(a)), {"quit": 4242})
            self.assertEqual(killed, [(4242, b.signal.SIGTERM)])

    async def test_flatpak_apps_are_closed_through_flatpak(self):
        command = AsyncMock(return_value=b"")
        with tempfile.TemporaryDirectory() as temp:
            proc = Path(temp)
            (proc / "4243").mkdir()
            (proc / "4243/cgroup").write_text("0::/user.slice/user@1000.service/app.slice/app-flatpak-com.discordapp.Discord-81234.scope\n")
            result = await b.quit_process(4243, proc, kill=lambda *a: self.fail("signalled the D-Bus proxy"), command=command)
        self.assertEqual(result, {"quit": "com.discordapp.Discord"})
        self.assertEqual(command.call_args.args, ("flatpak", "kill", "com.discordapp.Discord"))

    async def test_dispatch_validates_the_item(self):
        backend = b.Backend()
        for params in ({}, {"id": ""}, {"id": 3}, {"id": "steam", "title": 4}):
            with self.subTest(params=params), self.assertRaises(b.BackendError) as raised:
                await backend.dispatch("tray.quit", params)
            self.assertEqual(raised.exception.code, "invalid")


class ProtocolTests(unittest.TestCase):
    def test_protocol_multiple_requests_and_clean_eof(self):
        with tempfile.TemporaryDirectory() as directory:
            env = dict(os.environ, XDG_CONFIG_HOME=directory, XDG_STATE_HOME=directory, XDG_CACHE_HOME=directory, XDG_RUNTIME_DIR=directory)
            requests = [{"id": 1, "method": "calculator", "params": {"expression": "6 * 7"}}, {"id": 2, "method": "settings.get"}, {"id": 3, "method": "unknown"}]
            result = subprocess.run([sys.executable, str(ROOT / "helpers/backend.py")], input="".join(json.dumps(x)+"\n" for x in requests), text=True, capture_output=True, timeout=5, env=env)
            self.assertEqual(result.returncode, 0, result.stderr)
            replies = {x["id"]: x for x in map(json.loads, result.stdout.splitlines()) if "id" in x}
            self.assertEqual(replies[1]["result"]["value"], 42)
            self.assertEqual(replies[2]["result"]["version"], 1)
            self.assertFalse(replies[3]["ok"])


if __name__ == "__main__":
    unittest.main()
