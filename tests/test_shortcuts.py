import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import AsyncMock, patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "helpers"))
import shortcuts as s  # noqa: E402
spec = importlib.util.spec_from_file_location("backend", ROOT / "helpers/backend.py")
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)
sys.path.insert(0, str(ROOT / "scripts"))
import install as installer  # noqa: E402

# Records what a Hyprland config fragment binds, with a stand-in for Hyprland's `hl` API.
STUB = '''
local calls = {}
hl = {
    bind = function(keys, dispatcher, opts)
        if keys == "BAD" then error("hl.bind: failed to parse key string") end
        table.insert(calls, keys .. "=" .. dispatcher .. "|" .. ((opts and opts.description) or ""))
    end,
    dsp = {exec_cmd = function(command) return command end, submap = function(name) return "submap " .. name end},
    define_submap = function(name, fn) table.insert(calls, "submap " .. name); fn() end,
    config = function() end, layer_rule = function() end, on = function() end,
}
dofile(arg[1])
table.sort(calls)
for _, call in ipairs(calls) do print(call) end
'''


def binds(*entries):
    return [{"modmask": mask, "key": key, "description": description, "submap": "", "mouse": False} for mask, key, description in entries]


class GrammarTests(unittest.TestCase):
    def test_canonical_keys(self):
        cases = {"shift + super + k": "SUPER + SHIFT + K", "SUPER+COMMA": "SUPER + COMMA", "control + alt + Delete": "CTRL + ALT + Delete",
                 "Print": "Print", "SHIFT + Print": "SHIFT + Print", "F5": "F5", "XF86AudioPlay": "XF86AudioPlay",
                 "super + space": "SUPER + SPACE", "Super + Enter": "SUPER + Return", "SUPER + 1": "SUPER + 1", "ctrl + shift + esc": "CTRL + SHIFT + Escape"}
        for given, expected in cases.items():
            with self.subTest(keys=given):
                self.assertEqual(s.canonical(given), expected)
        for keys in ("", "SUPER +", "K", "SHIFT + K", "SUPER + SUPER + K", "HYPER + K", "SUPER + é", "SUPER + K + L", "SUPER + mouse:272"):
            with self.subTest(keys=keys), self.assertRaises(ValueError):
                s.canonical(keys)

    def test_every_default_is_canonical(self):
        for item in s.CATALOG:
            with self.subTest(action=item["action"]):
                self.assertEqual(s.canonical(item["keys"]) if item["keys"] else "", item["keys"])

    def test_check_setting(self):
        s.check({"launcher": "SUPER + D", "clipboard": ""})
        for value in ([], {"nope": "SUPER + D"}, {"launcher": "super + d"}, {"launcher": 5}, {"launcher": "SUPER + D", "clipboard": "SUPER + D"}):
            with self.subTest(value=value), self.assertRaises(ValueError):
                s.check(value)

    def test_labels(self):
        self.assertEqual(s.label("SUPER + COMMA"), "Super + ,")
        self.assertEqual(s.label("CTRL + SHIFT + Escape"), "Ctrl + Shift + Esc")


class ClashTests(unittest.TestCase):
    current = {**{action: "" for action in s.ACTIONS}, "launcher": "SUPER + SPACE", "clipboard": "SUPER + V"}

    def test_other_shale_shortcuts_and_user_binds_clash(self):
        self.assertIn("Clipboard shortcut", s.clash("SUPER + V", "launcher", self.current, []))
        self.assertIn("your Hyprland config", s.clash("SUPER + E", "launcher", self.current, binds((64, "E", ""))))
        self.assertIn("(Files)", s.clash("SUPER + E", "launcher", self.current, binds((64, "e", "Files"))))
        # Caps Lock and Num Lock bits don't matter; another modifier does.
        self.assertIsNotNone(s.clash("SUPER + E", "launcher", self.current, binds((64 | 16, "E", ""))))
        self.assertIsNone(s.clash("SUPER + E", "launcher", self.current, binds((65, "E", ""))))

    def test_own_and_submap_binds_do_not_clash(self):
        self.assertIsNone(s.clash("SUPER + SPACE", "launcher", self.current, binds((64, "SPACE", "Shale: launcher"))))
        # An old fragment without descriptions: the bind on the action's own keys is its own.
        self.assertIsNone(s.clash("SUPER + SPACE", "launcher", self.current, binds((64, "space", ""))))
        submap = [{"modmask": 64, "key": "E", "submap": "resize"}]
        self.assertIsNone(s.clash("SUPER + E", "launcher", self.current, submap))
        self.assertIsNone(s.clash("SUPER + E", "launcher", self.current, "broken"))


class FragmentTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        (self.home / ".config/shale").mkdir(parents=True)
        (self.home / "stub.lua").write_text(STUB)

    def tearDown(self):
        self.tmp.cleanup()

    def load(self, fragment, overrides=None, xdg=""):
        if overrides is not None:
            (Path(xdg or self.home / ".config") / "shale/shortcuts.lua").write_text(overrides)
        result = subprocess.run(["lua", str(self.home / "stub.lua"), str(ROOT / "integration" / fragment)], capture_output=True, text=True,
                                env=dict(os.environ, HOME=str(self.home), XDG_CONFIG_HOME=xdg))
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.splitlines()

    @unittest.skipUnless(shutil.which("lua"), "lua is not installed")
    def test_overrides_replace_unbind_and_add(self):
        command = str(self.home / ".local/bin/shale ")
        plain = self.load("shale.lua")
        self.assertIn("SUPER + V=" + command + "clipboard|Shale: clipboard", plain)
        self.assertIn("submap shale-record", plain)
        self.assertIn("Escape=submap reset|", plain)
        self.assertEqual(len([line for line in plain if "Shale: " in line]), 13)
        changed = self.load("shale.lua", s.overrides_lua({"clipboard": "SUPER + SHIFT + V", "launcher": "", "color": "SUPER + C", "lock": "BAD"}))
        self.assertIn("SUPER + SHIFT + V=" + command + "clipboard|Shale: clipboard", changed)
        self.assertIn("SUPER + C=" + command + "color|Shale: color", changed)
        self.assertFalse(any(line.startswith(("SUPER + V=", "SUPER + SPACE=", "SUPER + L=")) for line in changed))
        # A bad bind costs only itself.
        self.assertIn("SUPER + A=" + command + "control|Shale: control", changed)

    @unittest.skipUnless(shutil.which("lua"), "lua is not installed")
    def test_a_broken_or_hostile_overrides_file_changes_nothing(self):
        plain = self.load("shale.lua")
        self.assertEqual(self.load("shale.lua", "return {"), plain)
        self.assertEqual(self.load("shale.lua", "error('x')"), plain)
        self.assertEqual(self.load("shale.lua", "return 5"), plain)
        hostile = self.load("shale.lua", 'return {["x; rm -rf ~"] = "SUPER + X"}')
        self.assertFalse(any("rm -rf" in line for line in hostile))

    @unittest.skipUnless(shutil.which("lua"), "lua is not installed")
    def test_xdg_config_home_and_the_wallpaper_fragment(self):
        xdg = self.home / "xdg"
        (xdg / "shale").mkdir(parents=True)
        self.assertIn("SUPER + D=" + str(self.home / ".local/bin/shale ") + "launcher|Shale: launcher",
                      self.load("shale.lua", s.overrides_lua({"launcher": "SUPER + D"}), xdg=str(xdg)))
        self.assertEqual(len(self.load("shale-wallpaper.lua")), 1)
        self.assertEqual(self.load("shale-wallpaper.lua", s.overrides_lua({"wallpaper": "SUPER + W"})), [])

    def test_lua_strings_escape_everything_unusual(self):
        self.assertEqual(s.lua_string('a"b\\c\n'), '"a\\034b\\092c\\010"')
        self.assertEqual(s.lua_string("SUPER + K"), '"SUPER + K"')
        self.assertIn('shale launcher"', s.rebind_lua("launcher", ["SUPER + SPACE"], "SUPER + D", "/h/.local/bin/shale"))
        self.assertTrue(s.rebind_lua("launcher", ["SUPER + SPACE"], "", "/h").startswith('pcall(hl.unbind, "SUPER + SPACE")'))
        if shutil.which("luac"):
            for code in (s.overrides_lua({"launcher": "SUPER + D", "close": ""}), s.rebind_lua("lock", ["SUPER + L"], "SUPER + K", '/home/o"k/shale')):
                self.assertEqual(subprocess.run(["luac", "-p", "-"], input=code.encode(), capture_output=True).returncode, 0, code)


class CatalogTests(unittest.TestCase):
    def test_installer_template_and_cli_agree_with_the_catalog(self):
        template = (ROOT / "integration/shale.lua").read_text()
        table = dict((action, keys) for keys, action in re.findall(r'\["([^"]+)"\] = "([^"]+)"', template))
        self.assertEqual(table, {action: keys for keys, action, _ in installer.SHORTCUTS})
        self.assertEqual(installer.WALLPAPER[:2], ("SUPER + SHIFT + W", "wallpaper"))
        self.assertIn('"' + installer.WALLPAPER[0] + '"', (ROOT / "integration/shale-wallpaper.lua").read_text())
        cli = (ROOT / "scripts/shale").read_text()
        verbs = {verb for line in re.findall(r"^  ([a-z|-]+)\)", cli, re.M) for verb in line.split("|")}
        for action in s.ACTIONS:
            with self.subTest(action=action):
                self.assertIn(action.split()[0], verbs)
        self.assertIn("toggle)", cli)

    def test_installed_fragments_are_read(self):
        with tempfile.TemporaryDirectory() as directory:
            hypr = Path(directory)
            self.assertEqual(s.installed(hypr), ({}, False))
            (hypr / "shale.lua").write_text(installer.shale_lua(installer.SHORTCUTS[:2]))
            self.assertEqual(s.installed(hypr), ({"launcher": "SUPER + SPACE", "clipboard": "SUPER + V"}, True))
            (hypr / "shale-wallpaper.lua").write_text((ROOT / "integration/shale-wallpaper.lua").read_text())
            self.assertEqual(s.installed(hypr)[0]["wallpaper"], "SUPER + SHIFT + W")
            (hypr / "shale.lua").write_text('local shortcuts = {\n    ["SUPER + V"] = "clipboard",\n}\n')
            self.assertEqual(s.installed(hypr), ({"clipboard": "SUPER + V", "wallpaper": "SUPER + SHIFT + W"}, False))


class BackendShortcutTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name)
        hypr = self.path / "hypr"
        hypr.mkdir()
        (hypr / "shale.lua").write_text(installer.shale_lua(installer.SHORTCUTS))
        self.paths = patch.multiple(b, CONFIG=self.path / "shale/config.json", STATE=self.path / "state", CACHE=self.path / "cache",
                                    RUNTIME=self.path / "runtime", HYPR=hypr, SHALE_COMMAND="/h/.local/bin/shale")
        self.paths.start()
        self.backend = b.Backend()
        self.live = binds((64, "E", ""), (64, "SPACE", "Shale: launcher"), (64, "V", "Shale: clipboard"))
        self.evals = []

    async def asyncTearDown(self):
        self.paths.stop()
        self.tmp.cleanup()

    async def fake_run(self, *args, **kwargs):
        if args[:2] == ("hyprctl", "binds"):
            return json.dumps(self.live).encode()
        if args[:2] == ("hyprctl", "eval"):
            self.evals.append(args[2])
            return b"ok"
        if args[:3] == ("hyprctl", "-j", "submap"):
            return b'"shale-record"'
        return b""

    async def call(self, method, params=None):
        with patch.object(b, "run", AsyncMock(side_effect=self.fake_run)) as run:
            result = await self.backend.dispatch(method, params or {})
        self.runs = [call.args for call in run.call_args_list]
        return result

    def keys(self, listing):
        return {item["action"]: item["keys"] for item in listing["shortcuts"]}

    async def test_set_moves_the_bind_now_and_for_later(self):
        result = await self.call("shortcuts.set", {"action": "clipboard", "keys": "shift+super+v"})
        self.assertTrue(result["ready"])
        self.assertEqual(self.keys(result)["clipboard"], "SUPER + SHIFT + V")
        self.assertEqual(b.settings()["shortcuts"], {"clipboard": "SUPER + SHIFT + V"})
        self.assertIn('["clipboard"] = "SUPER + SHIFT + V"', (self.path / "shale/shortcuts.lua").read_text())
        self.assertEqual(self.evals, ['pcall(hl.unbind, "SUPER + V") hl.bind("SUPER + SHIFT + V", hl.dsp.exec_cmd("/h/.local/bin/shale clipboard"), '
                                      '{description = "Shale: clipboard"})'])
        # Back to the installed keys: no longer a change.
        result = await self.call("shortcuts.set", {"action": "clipboard", "keys": "SUPER + V"})
        self.assertEqual(b.settings()["shortcuts"], {})
        self.assertEqual(self.keys(result)["clipboard"], "SUPER + V")

    async def test_clashes_and_bad_keys_are_refused(self):
        for keys, code in (("SUPER + E", "clash"), ("SUPER + SPACE", "clash"), ("K", "invalid")):
            with self.subTest(keys=keys), self.assertRaises(b.BackendError) as caught:
                await self.call("shortcuts.set", {"action": "clipboard", "keys": keys})
            self.assertEqual(caught.exception.code, code)
        with self.assertRaises(b.BackendError):
            await self.call("shortcuts.set", {"action": "rm -rf", "keys": "SUPER + K"})
        self.assertEqual(b.settings()["shortcuts"], {})
        self.assertFalse(self.evals)

    async def test_unbind_reset_and_a_failed_eval_reloads(self):
        await self.call("shortcuts.set", {"action": "launcher", "keys": ""})
        self.assertEqual(self.keys(await self.call("shortcuts.list"))["launcher"], "")
        self.assertIn('["launcher"] = false', (self.path / "shale/shortcuts.lua").read_text())
        await self.call("shortcuts.set", {"action": "color", "keys": "SUPER + SPACE"})
        with patch.object(self.backend, "hypr_eval", AsyncMock(return_value=False)):
            result = await self.call("shortcuts.reset", {})
        self.assertIn(("hyprctl", "reload"), self.runs)
        self.assertEqual((self.keys(result)["launcher"], self.keys(result)["color"]), ("SUPER + SPACE", ""))
        self.assertEqual(b.settings()["shortcuts"], {})

    async def test_settings_set_never_changes_shortcuts(self):
        await self.call("shortcuts.set", {"action": "clipboard", "keys": "SUPER + SHIFT + V"})
        await self.backend.dispatch("settings.set", {"settings": {"shortcuts": {}, "dnd": True}})
        self.assertEqual(b.settings()["shortcuts"], {"clipboard": "SUPER + SHIFT + V"})
        with self.assertRaises(b.BackendError):
            await self.backend.dispatch("settings.reset", {"keys": ["shortcuts"]})

    async def test_an_old_fragment_is_read_only(self):
        (b.HYPR / "shale.lua").write_text('local shortcuts = {\n    ["SUPER + V"] = "clipboard",\n}\n')
        self.assertFalse((await self.call("shortcuts.list"))["ready"])
        with self.assertRaises(b.BackendError) as caught:
            await self.call("shortcuts.set", {"action": "clipboard", "keys": "SUPER + K"})
        self.assertEqual(caught.exception.code, "unavailable")
        self.assertEqual(await self.call("shortcuts.record", {"active": True}), {"active": False})

    async def test_recording_enters_and_leaves_the_submap(self):
        self.assertEqual(await self.call("shortcuts.record", {"active": True}), {"active": True})
        self.assertIn('hl.dsp.submap("shale-record")', self.evals[-1])
        self.assertIsNotNone(self.backend.record_timeout)
        self.assertEqual(await self.call("shortcuts.record", {"active": False}), {"active": False})
        self.assertIn('hl.dsp.submap("reset")', self.evals[-1])
        self.assertIsNone(self.backend.record_timeout)

    async def test_imported_shortcuts_apply_only_when_they_fit(self):
        target = self.path / "backup.json"
        target.write_text(json.dumps({"version": 1, "dnd": True, "shortcuts": {"clipboard": "SUPER + SHIFT + V"}}))
        result = await self.call("settings.import", {"path": str(target)})
        self.assertEqual((result["applied"], result["settings"]["shortcuts"]), (["dnd", "shortcuts"], {"clipboard": "SUPER + SHIFT + V"}))
        target.write_text(json.dumps({"version": 1, "shortcuts": {"clipboard": "SUPER + E"}}))
        result = await self.call("settings.import", {"path": str(target)})
        self.assertEqual((result["skipped"], b.settings()["shortcuts"]), (["shortcuts"], {"clipboard": "SUPER + SHIFT + V"}))
