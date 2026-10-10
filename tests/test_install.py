import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('installer', Path(__file__).parents[1] / 'scripts/install.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)

STOCK = Path('/usr/share/hypr/hyprland.lua')
NO_CHECKS = lambda: ([], [], [])


def lua_parses(text):
    if not shutil.which('luac'):
        return True
    return subprocess.run(['luac', '-p', '-'], input=text.encode(), capture_output=True).returncode == 0


def answers(*replies):
    replies = iter(replies)
    return lambda prompt: next(replies)


CONFIG = Path('hyprland.lua')


def integrated(text, decide=installer.replace_all, wanted=installer.SHORTCUTS, report=None):
    """hyprland.lua after integrate(), and the specs chosen and skipped."""
    files, chosen, skipped = installer.integrate({CONFIG: text}, wanted, decide, report=report or (lambda line: None))
    return files[CONFIG], chosen, skipped


class HyprlandConfigTests(unittest.TestCase):
    def test_bind_replacement_is_targeted_and_idempotent(self):
        original = '''local mainMod = "SUPER"
hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd(menu))
hl.bind("SUPER + SPACE", hl.dsp.exec_cmd(menu))
hl.bind("SUPER + SHIFT + V", hl.dsp.workspace.toggle_special("magic"))
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"))
'''
        result = integrated(original)[0]
        self.assertEqual(result.count('-- Shale replaced:'), 2)
        self.assertIn('\nhl.bind("SUPER + SHIFT + V"', result)
        self.assertIn('\nhl.bind("XF86AudioMute"', result)
        self.assertEqual(integrated(result)[0], result)

    def test_multi_line_binds_are_commented_whole(self):
        original = '''hl.bind("SUPER + V", function()
    hl.exec_cmd("echo ) inside a string")  -- and a ) in a comment
end)
hl.bind("SUPER + T", hl.dsp.exec_cmd("kitty"))
'''
        result = integrated(original)[0]
        self.assertTrue(lua_parses(result), result)
        self.assertEqual(result.count('-- Shale replaced:'), 3)
        self.assertIn('\nhl.bind("SUPER + T"', result)

    def test_code_after_a_bind_on_the_same_line_stays_live(self):
        result = integrated('hl.bind("SUPER + L", hl.dsp.exec_cmd("hyprlock")) hl.bind("SUPER + T", x)\n')[0]
        self.assertIn('-- Shale replaced: hl.bind("SUPER + L"', result)
        self.assertIn('\n hl.bind("SUPER + T", x)', result)

    def test_quotes_modifier_order_variables_and_assignments(self):
        original = '''local mod = 'SUPER'
hl.bind('SUPER + L', hl.dsp.focus({ direction = "right" }))
hl.bind("SHIFT + SUPER + A", hl.dsp.exec_cmd("a"))
local b = hl.bind(mod .. " + N", hl.dsp.exec_cmd("n"))
hl.bind("super + comma", hl.dsp.exec_cmd("c"))
'''
        result = integrated(original)[0]
        self.assertEqual(result.count('-- Shale replaced:'), 4)
        self.assertTrue(lua_parses(result), result)

    def test_unknown_keys_are_left_alone(self):
        original = '''for i = 1, 9 do
    hl.bind(mainMod .. " + " .. i, hl.dsp.focus({ workspace = i }))
end
'''
        self.assertNotIn('-- Shale replaced:', integrated(original)[0])

    def test_skipped_shortcuts_keep_the_users_bind_and_are_not_bound_by_shale(self):
        original = 'hl.bind("SUPER + V", hl.dsp.window.float({ action = "toggle" }))\nhl.bind("SUPER + M", hl.dsp.exec_cmd("exit"))\n'
        output = io.StringIO()
        decide = installer.ask(answers('s', 'maybe', 'r'), lambda text: output.write(text + '\n'))
        text, chosen, skipped = integrated(original, decide)
        self.assertIn('Super+V is bound to: hl.dsp.window.float', output.getvalue())
        self.assertEqual([spec[0] for spec in skipped], ['SUPER + V'])
        self.assertTrue(text.startswith('hl.bind("SUPER + V"'))
        self.assertIn('-- Shale replaced: hl.bind("SUPER + M"', text)
        rendered = installer.shale_lua(chosen)
        self.assertNotIn('"SUPER + V"', rendered)
        self.assertIn('["SUPER + M"] = "power"', rendered)
        self.assertTrue(lua_parses(rendered), rendered)

    @unittest.skipUnless(STOCK.is_file(), 'Hyprland example config not installed')
    def test_stock_example_config(self):
        text, _, skipped = integrated(STOCK.read_text(), lambda spec, existing: spec[0] != 'SUPER + V')
        self.assertTrue(lua_parses(text))
        self.assertEqual([spec[0] for spec in skipped], ['SUPER + V'])
        self.assertIn('\nhl.bind(mainMod .. " + V", hl.dsp.window.float', text)
        self.assertIn('-- Shale replaced: hl.bind(mainMod .. " + M"', text)


    def test_the_loader_does_nothing_once_the_file_is_gone(self):
        text = integrated('hl.bind("SUPER + T", x)\n')[0]
        self.assertIn(installer.MARKER + '\n' + installer.LOADER.format('shale.lua'), text)
        self.assertTrue(lua_parses(text), text)
        # An earlier install's bare dofile fails on every Hyprland start once shale.lua is gone; it's replaced.
        old = 'x()\n\n' + installer.MARKER + '\n' + installer.OLD_LOADER.format('shale.lua') + '\n'
        upgraded = integrated(old)[0]
        self.assertNotIn('dofile(', upgraded)
        self.assertEqual(upgraded.count(installer.MARKER), 1)
        if not shutil.which('lua'):
            return
        with tempfile.TemporaryDirectory() as home:
            run = lambda: subprocess.run(['lua', '-'], input=installer.LOADER.format('shale.lua'), text=True,
                                         capture_output=True, env={'HOME': home})
            self.assertEqual(run().returncode, 0)
            (Path(home) / '.config/hypr').mkdir(parents=True)
            (Path(home) / '.config/hypr/shale.lua').write_text('error("broken shortcut")\n')
            self.assertIn('broken shortcut', run().stderr)

    def test_later_uses_of_a_replaced_bind_are_commented_out_or_reported(self):
        original = '''local b = hl.bind("SUPER + N", hl.dsp.exec_cmd("n"))
b:set_enabled(false)
b.description = "mine"
hl.on("hyprland.start", function()
    b:set_enabled(
        true)
end)
if b:is_enabled() then print("on") end
local bb = "b" -- b
'''
        reports = []
        text = integrated(original, report=reports.append)[0]
        self.assertTrue(lua_parses(text), text)
        for line in ('b:set_enabled(false)', 'b.description = "mine"', '    b:set_enabled(', '        true)'):
            self.assertIn('\n-- Shale replaced: ' + line + '\n', text)
        self.assertIn('\nif b:is_enabled()', text)
        self.assertIn('\nlocal bb = "b" -- b', text)
        self.assertEqual(reports, ['hyprland.lua still uses a binding Shale replaced, so Hyprland reports an error there '
                                   'until you change it: if b:is_enabled() then print("on") end'])
        self.assertEqual(installer.unintegrate(text), original)

    def test_unintegrate_keeps_what_the_file_had_before_that_install(self):
        before = ('-- Shale replaced: hl.bind("SUPER + V", x)\n\n' + installer.MARKER + '\n'
                  + installer.OLD_LOADER.format('shale.lua') + '\n')
        now = ('-- Shale replaced: hl.bind("SUPER + V", x)\n-- Shale replaced: hl.bind("SUPER + L", y)\nmine()\n\n'
               + installer.MARKER + '\n' + installer.LOADER.format('shale.lua') + '\n\n'
               + installer.WALLPAPER_MARKER + '\n' + installer.LOADER.format('shale-wallpaper.lua') + '\n')
        self.assertEqual(installer.unintegrate(now, before),
                         '-- Shale replaced: hl.bind("SUPER + V", x)\nhl.bind("SUPER + L", y)\nmine()\n\n'
                         + installer.MARKER + '\n' + installer.LOADER.format('shale.lua') + '\n')
        old = 'mine()\n\n' + installer.MARKER + '\n' + installer.OLD_LOADER.format('shale.lua') + '\n'
        self.assertEqual(installer.unintegrate(old), 'mine()\n')


class PayloadTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name).resolve()
        self.config = self.home / '.config/hypr/hyprland.lua'

    def write_config(self, text):
        self.config.parent.mkdir(parents=True, exist_ok=True)
        self.config.write_text(text)

    def test_shell_only_payload_never_touches_bindings_or_service_units(self):
        targets = installer.payload(self.home, shell_only=True)
        self.assertIn(self.home / '.config/quickshell/shale/shell.qml', targets)
        self.assertIn(self.home / '.local/bin/shale', targets)
        self.assertTrue(all(path.is_relative_to(self.home / '.config/quickshell/shale') or path.name == 'shale' for path in targets))
        self.assertFalse((self.home / '.config/hypr').exists())

    def test_wallpaper_shortcut_is_explicit_and_idempotent(self):
        original = 'hl.bind("SUPER + T", hl.dsp.exec_cmd("kitty"))\n'
        self.write_config(original)
        targets = installer.payload(self.home, shell_only=True, wallpaper_shortcut=True)
        updated = targets[self.config][0].decode()
        self.assertTrue(updated.startswith(original))
        self.assertEqual(updated.count('-- Shale wallpaper shortcut'), 1)
        self.config.write_text(updated)
        self.assertEqual(installer.payload(self.home, shell_only=True, wallpaper_shortcut=True)[self.config][0], updated.encode())

    def test_wallpaper_conflict_is_asked_like_any_other(self):
        self.write_config('hl.bind("SUPER + SHIFT + W", hl.dsp.exec_cmd("other"))\n')
        targets = installer.payload(self.home, shell_only=True, wallpaper_shortcut=True, decide=installer.skip_all, report=lambda text: None)
        self.assertNotIn(self.home / '.config/hypr/shale-wallpaper.lua', targets)
        self.assertNotIn('shale-wallpaper.lua', targets[self.config][0].decode())
        targets = installer.payload(self.home, shell_only=True, wallpaper_shortcut=True)
        self.assertIn('-- Shale replaced: hl.bind("SUPER + SHIFT + W"', targets[self.config][0].decode())

    def test_full_install_keeps_the_wallpaper_shortcut(self):
        self.write_config('hl.bind("SUPER + SPACE", hl.dsp.exec_cmd("menu"))\n')
        updated = installer.payload(self.home, wallpaper_shortcut=True)[self.config][0].decode()
        self.assertIn('shale-wallpaper.lua', updated)
        self.assertIn('/.config/hypr/shale.lua', updated)
        self.assertIn('-- Shale replaced: hl.bind("SUPER + SPACE"', updated)

    def test_files_loaded_from_hyprland_lua_are_checked_too(self):
        hypr = self.config.parent
        self.write_config('require("keys")\n'
                          'dofile(os.getenv("HOME") .. "/.config/hypr/more.lua")\n'
                          'dofile(os.getenv("HOME") .. "/.config/hypr/shale.lua")\n'
                          'local extra = "x.lua"\ndofile(extra)\n'
                          '-- dofile("/nowhere.lua")\n')
        (hypr / 'keys.lua').write_text('require("more")\nhl.bind("SUPER + V", hl.dsp.exec_cmd("mine"))\n')
        (hypr / 'more.lua').write_text('require "keys"\nhl.bind("SUPER + L", hl.dsp.exec_cmd("hyprlock"))\n')
        reports = []
        targets = installer.payload(self.home, report=reports.append)
        self.assertIn('-- Shale replaced: hl.bind("SUPER + V"', targets[hypr / 'keys.lua'][0].decode())
        self.assertIn('-- Shale replaced: hl.bind("SUPER + L"', targets[hypr / 'more.lua'][0].decode())
        self.assertEqual(list(targets)[-1], self.config)
        self.assertEqual(reports, ['Shortcut clashes not checked in the file loaded on line 5 of ~/.config/hypr/hyprland.lua: '
                                   'its name is computed.'])
        with patch('builtins.print') as printed:
            installer.payload(self.home, decide=installer.clash, report=lambda text: None)
        self.assertIn('Shortcut clash: Super+V is bound to hl.dsp.exec_cmd("mine")', str(printed.call_args_list))
        # Files that aren't there, or outside ~/.config/hypr, are reported rather than followed.
        (hypr / 'keys.lua').unlink()
        self.write_config('require("keys")\ndofile("/usr/share/hypr/hyprland.lua")\n')
        reports.clear()
        installer.payload(self.home, report=reports.append)
        self.assertIn('~/.config/hypr/keys.lua does not exist', reports[0])
        self.assertIn('/usr/share/hypr/hyprland.lua is outside ~/.config/hypr', reports[1])

    def test_session_action_is_installed_executable(self):
        repo = self.home / 'repo'
        (repo / 'scripts').mkdir(parents=True)
        (repo / 'shell.qml').write_text('')
        (repo / 'scripts/shale').write_text('')
        (repo / 'scripts/session-action').write_text('#!/usr/bin/env python3\n')
        (repo / 'scripts/session-action').chmod(0o644)
        with patch.object(installer, 'ROOT', repo):
            targets = installer.payload(self.home, shell_only=True)
        self.assertEqual(targets[self.home / '.config/quickshell/shale/scripts/session-action'][1], 0o755)

    def test_an_unchecked_syntax_is_reported(self):
        self.write_config('hl.bind("SUPER + V", x)\n')
        reports = []
        with patch.object(installer, 'lua_ok', return_value=None):
            installer.payload(self.home, report=reports.append)
        self.assertIn('luac (from the lua package) is not installed, so the edited Hyprland config was not syntax-checked.', reports)

    def test_missing_or_classic_config_explains_what_to_do(self):
        with self.assertRaisesRegex(ValueError, 'cp /usr/share/hypr/hyprland.lua'):
            installer.payload(self.home)
        (self.home / '.config/hypr').mkdir(parents=True)
        (self.home / '.config/hypr/hyprland.conf').write_text('bind = SUPER, Q, exec, kitty\n')
        with self.assertRaisesRegex(ValueError, 'Lua configuration'):
            installer.payload(self.home)


class PreflightTests(unittest.TestCase):
    def check(self, installed, version=(0, 3, 1), modules=('dbus_next',), processes=(), path='/usr/bin', hyprland=(0, 56, 2)):
        def module(name):
            if name not in modules:
                raise ImportError(name)
        return installer.preflight(Path('/home/u'), which=lambda name: name in installed, version=lambda: version,
                                   module=module, processes=lambda: set(processes), path=path, hyprland=lambda: hyprland)

    def test_everything_present(self):
        everything = set(installer.REQUIRED) | set(installer.OPTIONAL) | {'hyprpaper'}
        self.assertEqual(self.check(everything, path='/usr/bin:/home/u/.local/bin'), ([], [], []))

    def test_missing_packages_and_warnings(self):
        required, optional, warnings = self.check({'quickshell', 'hyprctl'}, version=(0, 2, 9), modules=(), processes=('waybar', 'mako', 'kitty'))
        self.assertEqual(required, ['python-dbus-next', 'wl-clipboard', 'quickshell'])
        self.assertIn('hyprpaper', optional)
        self.assertIn('cliphist', optional)
        self.assertTrue(any('older than 0.3.1' in w for w in warnings))
        self.assertTrue(any('mako, waybar' in w for w in warnings))
        self.assertTrue(any('~/.local/bin is not on your PATH' in w for w in warnings))

    def test_hyprland_older_than_the_minimum_is_required_and_an_unknown_one_a_warning(self):
        everything = set(installer.REQUIRED) | set(installer.OPTIONAL) | {'hyprpaper'}
        required, _, warnings = self.check(everything, path='/home/u/.local/bin', hyprland=(0, 55, 9))
        self.assertEqual(required, ['hyprland'])
        self.assertEqual(warnings, ['Hyprland 0.55.9 is older than 0.56; update it first.'])
        required, _, warnings = self.check(everything, path='/home/u/.local/bin', hyprland=None)
        self.assertEqual(required, [])
        self.assertEqual(warnings, ['Could not tell which Hyprland version is installed; Shale needs 0.56 or newer.'])
        self.assertEqual(self.check(everything, path='/home/u/.local/bin', hyprland=(0, 56, 0))[:2], ([], []))
        # Without Hyprland at all, it is just a missing package.
        required, _, warnings = self.check(everything - {'hyprctl'}, path='/home/u/.local/bin', hyprland=None)
        self.assertEqual(required, ['hyprland'])
        self.assertEqual(warnings, [])

    def test_hyprland_version_from_hyprctl_or_the_binary(self):
        calls = []

        def run(outputs):
            def fake(command, **options):
                calls.append(command[0])
                output = outputs[command[0]]
                if isinstance(output, Exception):
                    raise output
                return subprocess.CompletedProcess(command, 0, stdout=output)
            return fake
        running = {'HYPRLAND_INSTANCE_SIGNATURE': 'x'}
        binary = 'Hyprland 0.56.2 built from branch v0.56.2 at commit efb5099 clean ([gha] Nix: update inputs).\nDate: Wed Aug 5\n'
        self.assertEqual(installer.hyprland_version(run({'hyprctl': '{"version": "0.57.1", "tag": "v0.57.1"}'}), running), (0, 57, 1))
        self.assertEqual(installer.hyprland_version(run({'hyprctl': '{"tag": "v0.56.0-12-gabc"}'}), running), (0, 56, 0))
        calls.clear()
        self.assertEqual(installer.hyprland_version(run({'Hyprland': binary}), {}), (0, 56, 2))
        self.assertEqual(calls, ['Hyprland'])  # hyprctl only answers inside a session
        self.assertEqual(installer.hyprland_version(run({'hyprctl': OSError('no hyprctl'), 'Hyprland': binary}), running), (0, 56, 2))
        self.assertEqual(installer.hyprland_version(run({'hyprctl': '{"branch": "main"}', 'Hyprland': binary}), running), (0, 56, 2))
        self.assertIsNone(installer.hyprland_version(run({'Hyprland': subprocess.TimeoutExpired('Hyprland', 10)}), {}))
        self.assertIsNone(installer.hyprland_version(run({'Hyprland': 'garbage'}), {}))


class VersionTests(unittest.TestCase):
    def test_the_version_file_is_installed_into_the_shell_folder(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            targets = installer.payload(home, shell_only=True)
        self.assertEqual(targets[home / '.config/quickshell/shale/VERSION'][0], (installer.ROOT / 'VERSION').read_bytes())
        self.assertRegex(installer.version(), r'^\d+\.\d+\.\d+$')

    def test_version_reads_the_first_word_or_says_unknown(self):
        with tempfile.TemporaryDirectory() as temp:
            self.assertEqual(installer.version(temp), 'unknown')
            (Path(temp) / 'VERSION').write_text('')
            self.assertEqual(installer.version(temp), 'unknown')
            (Path(temp) / 'VERSION').write_text('2.0.1\n')
            self.assertEqual(installer.version(temp), '2.0.1')

    def test_version_option(self):
        script = Path(installer.__file__)
        for env in ({}, {'SHALE_INSTALLER': 'install.sh'}):
            result = subprocess.run([sys.executable, str(script), '--version'], capture_output=True, text=True,
                                    env={**os.environ, **env})
            self.assertEqual(result.stdout, f'Shale {installer.version()}\n')
        result = subprocess.run(['bash', str(installer.ROOT / 'install.sh'), '--version'], capture_output=True, text=True)
        self.assertEqual(result.stdout, f'Shale {installer.version()}\n')


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name).resolve()
        self.shell = self.home / '.config/quickshell/shale'
        self.config = self.home / '.config/hypr/hyprland.lua'
        self.repo = self.home / 'repo'
        self.repo.mkdir()
        (self.repo / 'shell.qml').touch()

    def backups(self):
        return [state for state, _ in installer.backup_manifests(self.home)]

    def install_files(self, files, **options):
        """Install exactly `files` ({path: bytes}) from a stand-in checkout."""
        with patch.object(installer, 'payload', return_value={path: (data, 0o644) for path, data in files.items()}), \
                patch.object(installer, 'ROOT', self.repo), patch('builtins.print'):
            installer.install(self.home, True, checks=NO_CHECKS, **options)

    def old_backup(self, files, name='20200101-000000-old'):
        """A backup folder as earlier installers wrote it: [(path, original bytes or None, installed bytes)]."""
        state = self.home / '.local/state/shale/backups' / name
        state.mkdir(parents=True)
        manifest = {'version': 1, 'home': str(self.home), 'files': []}
        for index, (path, original, data) in enumerate(files):
            if original is not None:
                (state / str(index)).write_bytes(original)
            manifest['files'].append({'path': str(path), 'backup': None if original is None else str(index), 'mode': 0o644,
                                      'installed_sha256': installer.digest(data)})
        (state / 'manifest.json').write_text(json.dumps(manifest))
        return state

    def test_preview_and_rollback_preserve_user_edits(self):
        home = self.home
        first, second = home / 'existing', home / 'new'
        first.write_bytes(b'original')
        with patch.object(installer, 'payload', return_value={first: (b'installed', 0o644), second: (b'new', 0o644)}), \
                patch.object(installer, 'ROOT', self.repo), patch('builtins.print'):
            installer.install(home, checks=NO_CHECKS)
            self.assertEqual(first.read_bytes(), b'original')
            self.assertFalse(second.exists())
            installer.install(home, True, checks=NO_CHECKS)
        second.write_bytes(b'user-edited')
        with patch('builtins.print'):
            self.assertEqual(installer.rollback(home, self.backups()[0], True), 1)
        self.assertEqual(first.read_bytes(), b'original')
        self.assertEqual(second.read_bytes(), b'user-edited')

    def test_a_checkout_inside_the_shell_folder_is_refused(self):
        for root in (self.shell, self.shell / 'sub', self.home / '.config'):
            with self.subTest(root=root):
                root.mkdir(parents=True, exist_ok=True)
                (root / 'shell.qml').write_text('mine')
                (root / '.git').mkdir(exist_ok=True)
                with patch.object(installer, 'ROOT', root), patch('builtins.print'), self.assertRaisesRegex(ValueError, 'overlaps'):
                    installer.install(self.home, True, shell_only=True, checks=NO_CHECKS)
                self.assertTrue((root / '.git').is_dir())
                self.assertEqual((root / 'shell.qml').read_text(), 'mine')

    def test_missing_required_packages_stop_apply_unless_forced(self):
        missing = lambda: (['quickshell'], [], [])
        with patch.object(installer, 'payload', return_value={}), patch('builtins.print'):
            with self.assertRaisesRegex(ValueError, '--force'):
                installer.install(self.home, True, checks=missing)
            installer.install(self.home, True, force=True, checks=missing)
            installer.install(self.home, False, checks=missing)

    def test_package_hints_use_sudo(self):
        with patch.object(installer, 'payload', return_value={}), patch('builtins.print') as printed:
            installer.install(self.home, False, checks=lambda: (['quickshell'], ['fd'], []))
        output = str(printed.call_args_list)
        self.assertIn('Optional, for every feature: sudo pacman -S --needed fd', output)
        self.assertIn('Required: sudo pacman -S --needed quickshell', output)
        self.assertNotIn('pkexec', output)

    def test_without_a_terminal_conflicts_are_kept_unless_yes(self):
        config = self.config
        config.parent.mkdir(parents=True)
        config.write_text('hl.bind("SUPER + V", hl.dsp.window.float({ action = "toggle" }))\n')
        with patch('builtins.print'):
            installer.install(self.home, True, interactive=False, checks=NO_CHECKS)
            self.assertTrue(config.read_text().startswith('hl.bind("SUPER + V"'))
            self.assertNotIn('"SUPER + V"', (self.home / '.config/hypr/shale.lua').read_text())
            installer.install(self.home, True, yes=True, checks=NO_CHECKS)
        self.assertTrue(config.read_text().startswith('-- Shale replaced: hl.bind("SUPER + V"'))
        self.assertIn('["SUPER + V"] = "clipboard"', (self.home / '.config/hypr/shale.lua').read_text())

    def test_interactive_answers(self):
        config = self.config
        config.parent.mkdir(parents=True)
        config.write_text('hl.bind("SUPER + V", x)\nhl.bind("SUPER + L", y)\n')
        with patch('builtins.print'):
            installer.install(self.home, True, interactive=True, read=answers('r', 's'), checks=NO_CHECKS)
        text = config.read_text()
        self.assertIn('-- Shale replaced: hl.bind("SUPER + V"', text)
        self.assertIn('\nhl.bind("SUPER + L", y)', text)

    def test_stow_style_symlinks_are_followed_within_home(self):
        dotfiles = self.home / 'dotfiles/hypr'
        dotfiles.mkdir(parents=True)
        (dotfiles / 'hyprland.lua').write_text('hl.bind("SUPER + T", x)\n')
        (self.home / '.config').mkdir()
        (self.home / '.config/hypr').symlink_to(dotfiles, target_is_directory=True)
        with patch('builtins.print'):
            installer.install(self.home, True, yes=True, checks=NO_CHECKS)
        self.assertTrue((self.home / '.config/hypr').is_symlink())
        self.assertIn('shale.lua', (dotfiles / 'hyprland.lua').read_text())
        self.assertTrue((dotfiles / 'shale.lua').is_file())

    def test_symlinks_out_of_home_are_refused(self):
        with tempfile.TemporaryDirectory() as outside:
            (self.home / '.config').mkdir()
            (self.home / '.config/quickshell').symlink_to(outside, target_is_directory=True)
            with patch('builtins.print'), self.assertRaisesRegex(ValueError, 'outside your home'):
                installer.install(self.home, True, shell_only=True, checks=NO_CHECKS)

    def test_only_files_shale_installed_are_removed_as_stale(self):
        old, mine = self.shell / 'components/Old.qml', self.shell / 'components/Mine.qml'
        old.parent.mkdir(parents=True)
        old.write_text('old')
        mine.write_text('mine')
        installer.save_record(self.home, {str(old): installer.digest(b'old')})
        with patch('builtins.print'):
            installer.install(self.home, True, shell_only=True, checks=NO_CHECKS)
            self.assertFalse(old.exists())
            self.assertEqual(mine.read_text(), 'mine')
            self.assertNotIn(str(old), installer.installed(self.home))
            self.assertIn(str(self.shell / 'shell.qml'), installer.installed(self.home))
            installer.rollback(self.home, self.backups()[0], True)
        self.assertEqual(old.read_text(), 'old')
        self.assertEqual(mine.read_text(), 'mine')
        # Restored, it is tracked again: the next install removes it as stale once more.
        self.assertEqual(installer.installed(self.home)[str(old)], installer.digest(b'old'))
        with patch('builtins.print'):
            installer.install(self.home, True, shell_only=True, checks=NO_CHECKS)
        self.assertFalse(old.exists())
        self.assertEqual(mine.read_text(), 'mine')

    def test_installs_older_than_the_record_are_read_from_their_backups(self):
        old, mine = self.shell / 'components/Old.qml', self.shell / 'components/Mine.qml'
        old.parent.mkdir(parents=True)
        old.write_text('old')
        mine.write_text('mine')
        self.old_backup([(old, None, b'old')])
        with patch('builtins.print'):
            installer.install(self.home, True, shell_only=True, checks=NO_CHECKS)
        self.assertFalse(old.exists())
        self.assertTrue(mine.exists())
        self.assertTrue((self.home / '.local/state/shale/installed.json').is_file())

    def test_originals_are_kept_once_and_backups_only_cover_changes(self):
        mine, same, added = self.home / 'mine.conf', self.home / 'same.conf', self.home / 'added.conf'
        mine.write_bytes(b'my original')
        self.install_files({mine: b'shale 1', same: b'same'})
        self.install_files({mine: b'shale 2', same: b'same', added: b'new'})
        self.assertEqual(len(self.backups()), 2)
        manifest = json.loads((self.backups()[1] / 'manifest.json').read_text())
        self.assertEqual(sorted(entry['path'] for entry in manifest['files']), [str(added), str(mine)])
        # Nothing to change: no backup at all.
        with patch.object(installer, 'payload', return_value={mine: (b'shale 2', 0o644), same: (b'same', 0o644)}), \
                patch.object(installer, 'ROOT', self.repo), patch('builtins.print') as printed:
            installer.install(self.home, True, checks=NO_CHECKS)
        self.assertIn('nothing was written', str(printed.call_args_list))
        self.assertEqual(len(self.backups()), 2)
        originals = self.home / '.local/state/shale/originals'
        kept = {entry['path']: entry for entry in json.loads((originals / 'manifest.json').read_text())['files']}
        self.assertEqual((originals / kept[str(mine)]['backup']).read_bytes(), b'my original')
        self.assertIsNone(kept[str(same)]['backup'])
        self.assertIsNone(kept[str(added)]['backup'])
        self.assertEqual(installer.installed(self.home)[str(mine)], installer.digest(b'shale 2'))

    def test_originals_start_from_the_oldest_backups_of_earlier_installs(self):
        config = self.home / 'hyprland.lua'
        config.write_bytes(b'shale 2')
        self.old_backup([(config, b'before shale', b'shale 1')], '20200101-000000-first')
        self.old_backup([(config, b'shale 1', b'shale 2')], '20200202-000000-second')
        self.install_files({config: b'shale 3'})
        originals = self.home / '.local/state/shale/originals'
        entry = json.loads((originals / 'manifest.json').read_text())['files'][0]
        self.assertEqual((originals / entry['backup']).read_bytes(), b'before shale')

    def test_a_failed_write_says_how_to_undo(self):
        first, second = self.home / 'first', self.home / 'second'
        write = installer.atomic_write

        def failing(path, data, mode=0o644):
            if path == second:
                raise OSError('No space left on device')
            write(path, data, mode)
        output = io.StringIO()
        with patch.object(installer, 'payload', return_value={first: (b'1', 0o644), second: (b'2', 0o644)}), \
                patch.object(installer, 'ROOT', self.repo), patch.object(installer, 'atomic_write', failing), \
                patch('sys.stdout', output), self.assertRaises(OSError):
            installer.install(self.home, True, checks=NO_CHECKS)
        state = self.backups()[0]
        self.assertIn(f'Everything they replaced is in ~/{state.relative_to(self.home)}', output.getvalue())
        self.assertIn(f'--rollback ~/{state.relative_to(self.home)} --apply', output.getvalue())

    def test_rollback_takes_shale_out_of_an_edited_config(self):
        self.config.parent.mkdir(parents=True)
        self.config.write_text('hl.bind("SUPER + V", hl.dsp.window.float({ action = "toggle" }))\n')
        with patch('builtins.print'):
            installer.install(self.home, True, yes=True, checks=NO_CHECKS)
        self.config.write_text(self.config.read_text() + 'hl.bind("SUPER + T", hl.dsp.exec_cmd("kitty"))\n')
        with patch('builtins.print') as printed:
            self.assertEqual(installer.rollback(self.home, self.backups()[0], True), 0)
        self.assertIn("UNDO Shale's lines in", str(printed.call_args_list))
        self.assertEqual(self.config.read_text(), 'hl.bind("SUPER + V", hl.dsp.window.float({ action = "toggle" }))\n'
                                                  'hl.bind("SUPER + T", hl.dsp.exec_cmd("kitty"))\n')
        self.assertFalse((self.home / '.config/hypr/shale.lua').exists())
        self.assertFalse(self.shell.exists() and any(self.shell.rglob('*.qml')))

    def test_rollback_of_an_earlier_install_keeps_files_a_bare_dofile_still_loads(self):
        hypr = self.config.parent
        hypr.mkdir(parents=True)
        shale = hypr / 'shale.lua'
        shale.write_text('-- shortcuts\n')
        installed = 'mine()\n\n' + installer.MARKER + '\n' + installer.OLD_LOADER.format('shale.lua') + '\n'
        state = self.old_backup([(shale, None, b'-- shortcuts\n'), (self.config, b'mine()\n', installed.encode())])
        # Edited since, and the block no longer looks like Shale's: the dofile stays, so shale.lua must too.
        self.config.write_text('mine()\nother()\n' + installer.OLD_LOADER.format('shale.lua') + '\n')
        with patch('builtins.print'):
            self.assertEqual(installer.rollback(self.home, state, True), 2)
        self.assertTrue(shale.exists())
        # An edited config whose block is intact loses it, and then shale.lua can go.
        self.config.write_text(installed + 'other()\n')
        with patch('builtins.print'):
            self.assertEqual(installer.rollback(self.home, state, True), 0)
        self.assertEqual(self.config.read_text(), 'mine()\nother()\n')
        self.assertFalse(shale.exists())

    def test_bindings_the_user_kept_are_not_asked_about_again(self):
        self.config.parent.mkdir(parents=True)
        self.config.write_text('hl.bind("SUPER + V", x)\nhl.bind("SUPER + L", y)\n')

        def run(**options):
            output = io.StringIO()
            with patch('sys.stdout', output):
                installer.install(self.home, options.pop('apply', True), checks=NO_CHECKS, **options)
            return output.getvalue()
        run(interactive=True, read=answers('r', 's'))
        self.assertEqual(installer.choices(self.home), {'SUPER+V': 'replace', 'SUPER+L': 'keep'})
        # A re-install or update keeps Super+L without asking, even with --yes, and says so once.
        for options in ({'interactive': True, 'read': self.fail}, {'yes': True}, {'apply': False}):
            with self.subTest(options=options):
                output = run(**options)
                self.assertIn('Kept your Super+L binding, as you chose before; add --ask-again to be asked again.', output)
                self.assertNotIn('Shale lock screen has no shortcut', output)
                self.assertNotIn('Shortcut clash', output)
                self.assertIn('\nhl.bind("SUPER + L", y)', self.config.read_text())
        run(interactive=True, read=answers('r'), ask_again=True)
        self.assertIn('-- Shale replaced: hl.bind("SUPER + L"', self.config.read_text())
        self.assertEqual(installer.choices(self.home), {'SUPER+L': 'replace'})
        # Kept without a terminal is not the user's answer, so nothing is remembered.
        installer.save_choices(self.home, {})
        self.config.write_text('hl.bind("SUPER + N", z)\n')
        run(interactive=False)
        self.assertEqual(installer.choices(self.home), {})


class UninstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name).resolve()
        self.shell = self.home / '.config/quickshell/shale'
        self.config = self.home / '.config/hypr/hyprland.lua'
        self.config.parent.mkdir(parents=True)
        self.original = STOCK.read_text() if STOCK.is_file() else (
            'local mainMod = "SUPER"\nhl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))\n'
            'hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("exit"))\n')
        self.config.write_text(self.original)
        self.commands = []

    def run_command(self, command, **options):
        self.commands.append(command)
        return subprocess.CompletedProcess(command, 0)

    def snapshot(self):
        """Every file in home outside Shale's state folder: {relative path: (bytes, mode)}."""
        return {str(path.relative_to(self.home)): (path.read_bytes(), path.stat().st_mode & 0o777)
                for path in self.home.rglob('*') if path.is_file() and not path.is_relative_to(self.home / '.local/state/shale')}

    def install(self, **options):
        with patch('sys.stdout', io.StringIO()):
            installer.install(self.home, True, yes=True, checks=NO_CHECKS, **options)

    def uninstall(self, apply=True, own=True, **options):
        """Uninstall from the test home, as the user's own home (Path.home) unless `own` is False."""
        output = io.StringIO()
        options.setdefault('yes', True)
        with patch('sys.stdout', output), patch.object(installer.Path, 'home', return_value=self.home if own else self.home / 'other'):
            skipped = installer.uninstall(self.home, apply, run=self.run_command, **options)
        return skipped, output.getvalue()

    def test_install_then_uninstall_restores_everything_byte_for_byte(self):
        (self.home / '.config/shale').mkdir(parents=True)
        (self.home / '.config/shale/config.json').write_text('{}')
        before = self.snapshot()
        self.install(wallpaper_shortcut=True)
        self.assertNotEqual(self.config.read_text(), self.original)
        self.assertTrue((self.shell / 'VERSION').is_file())
        skipped, output = self.uninstall()
        self.assertEqual(skipped, 0, output)
        self.assertEqual(self.snapshot(), before)
        self.assertFalse(self.shell.parent.exists())
        self.assertEqual(self.commands[:2], [['systemctl', '--user', 'stop', 'shale.service'],
                                             ['systemctl', '--user', 'disable', 'shale.service']])
        self.assertEqual(self.commands[-1], ['systemctl', '--user', 'daemon-reload'])
        self.assertTrue(any(command[0] == 'pkill' and 'shale-hypridle' in command[-1] for command in self.commands))
        self.assertEqual(installer.installed(self.home), {})
        self.assertIn('Kept: ~/.config/shale (settings)', output)
        # The uninstall's own backup can undo it.
        state = installer.backup_manifests(self.home)[-1][0]
        self.assertIn(f'Backup of everything it changed or removed: ~/{state.relative_to(self.home)}', output)

    def test_another_home_leaves_the_running_session_alone(self):
        before = self.snapshot()
        self.install()
        skipped, output = self.uninstall(apply=False, own=False)
        self.assertIn(f'Service steps skipped: {self.home} is not your home directory', output)
        self.assertNotIn('stop     shale.service', output)
        skipped, output = self.uninstall(own=False)
        self.assertEqual(skipped, 0, output)
        self.assertEqual(self.commands, [])
        self.assertEqual(output.count('Service steps skipped'), 1)
        self.assertEqual(self.snapshot(), before)
        # The user's own home stops and disables the service, and reloads systemd once its unit is gone.
        self.install()
        skipped, output = self.uninstall()
        self.assertNotIn('Service steps skipped', output)
        self.assertEqual([command[:3] for command in self.commands],
                         [['systemctl', '--user', 'stop'], ['systemctl', '--user', 'disable'], ['pkill', '-u', str(os.getuid())],
                          ['systemctl', '--user', 'daemon-reload']])

    def test_a_second_uninstall_has_nothing_to_do(self):
        self.install()
        self.uninstall()
        after, commands = self.snapshot(), len(self.commands)
        skipped, output = self.uninstall()
        self.assertEqual(skipped, 0)
        self.assertIn('nothing to remove', output)
        self.assertEqual(self.snapshot(), after)
        self.assertEqual(len(self.commands), commands)

    def test_a_preview_changes_nothing(self):
        self.install()
        before = self.snapshot()
        skipped, output = self.uninstall(apply=False, yes=False, interactive=True, read=self.fail)
        self.assertEqual(skipped, 0)
        self.assertIn('restore  ~/.config/hypr/hyprland.lua', output)
        self.assertIn('remove   ~/.config/quickshell/shale:', output)
        self.assertIn('Preview only', output)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(self.commands, [])

    def test_it_asks_first_and_needs_yes_without_a_terminal(self):
        self.install()
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, 'nothing was removed'):
            self.uninstall(yes=False, interactive=True, read=lambda prompt: '')
        with self.assertRaisesRegex(ValueError, 'Pass --yes'):
            self.uninstall(yes=False, interactive=False)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(self.commands, [])
        prompts = []
        self.uninstall(yes=False, purge=True, interactive=True, read=lambda prompt: prompts.append(prompt) or 'y')
        self.assertIn('delete the folders above for good', prompts[0])
        self.assertFalse(self.shell.exists())

    def test_an_edited_config_keeps_the_users_edits(self):
        self.install()
        self.config.write_text(self.config.read_text() + 'hl.bind("SUPER + T", hl.dsp.exec_cmd("kitty"))\n')
        skipped, output = self.uninstall()
        self.assertEqual(skipped, 0)
        self.assertIn("undo     ~/.config/hypr/hyprland.lua: only Shale's lines", output)
        self.assertEqual(self.config.read_text(), self.original + 'hl.bind("SUPER + T", hl.dsp.exec_cmd("kitty"))\n')
        self.assertFalse((self.home / '.config/hypr/shale.lua').exists())

    def test_edits_made_between_installs_are_kept(self):
        self.install()
        self.config.write_text(self.config.read_text().replace(installer.MARKER, 'mine()\n' + installer.MARKER))
        self.install()  # now the file matches what Shale last wrote, edits included
        self.uninstall()
        self.assertIn('mine()', self.config.read_text())
        self.assertNotIn('Shale', self.config.read_text())

    def test_a_reinstall_after_an_uninstall_starts_from_the_config_as_it_is_then(self):
        self.install()
        self.uninstall()
        self.config.write_text(self.original + 'later()\n')
        self.install()
        self.uninstall()
        self.assertEqual(self.config.read_text(), self.original + 'later()\n')

    def test_files_that_are_not_shales_stay(self):
        self.install()
        mine, edited = self.shell / 'mine.qml', self.shell / 'shell.qml'
        mine.write_text('mine')
        edited.write_text('edited')
        (self.shell / 'helpers/__pycache__').mkdir(exist_ok=True)
        (self.shell / 'helpers/__pycache__/backend.cpython-314.pyc').write_bytes(b'cache')
        skipped, output = self.uninstall()
        self.assertEqual(skipped, 1)
        self.assertIn('keep     ~/.config/quickshell/shale/mine.qml: not installed by Shale', output)
        self.assertIn('skip     ~/.config/quickshell/shale/shell.qml: changed since Shale installed it', output)
        self.assertEqual(sorted(str(path.relative_to(self.shell)) for path in self.shell.rglob('*')), ['mine.qml', 'shell.qml'])
        self.assertEqual(self.config.read_text(), self.original)
        # Still recorded: once it's dealt with, the next uninstall finishes the job.
        self.assertEqual(list(installer.installed(self.home)), [str(edited)])
        edited.unlink()
        self.assertEqual(self.uninstall()[0], 0)

    def test_purge_deletes_settings_and_state_unless_files_were_left_alone(self):
        for folder in ('.config/shale', '.cache/shale'):
            (self.home / folder).mkdir(parents=True)
            (self.home / folder / 'file').write_text('x')
        self.install()
        (self.shell / 'shell.qml').write_text('edited')
        skipped, output = self.uninstall(purge=True)
        self.assertEqual(skipped, 1)
        self.assertIn('--purge would keep ~/.local/state/shale too', output)
        self.assertFalse((self.home / '.config/shale').exists())
        self.assertFalse((self.home / '.cache/shale').exists())
        self.assertTrue((self.home / '.local/state/shale/originals').is_dir())
        (self.shell / 'shell.qml').unlink()
        skipped, output = self.uninstall(purge=True)
        self.assertEqual(skipped, 0)
        self.assertIn('Deleted for good (--purge): ~/.local/state/shale', output)
        self.assertFalse((self.home / '.local/state/shale').exists())

    def test_configs_an_older_install_edited_without_a_record_lose_shales_lines(self):
        keys = self.config.parent / 'keys.lua'
        keys.write_text('-- Shale replaced: hl.bind("SUPER + V", x)\n')
        self.config.write_text('require("keys")\nmine()\n\n' + installer.MARKER + '\n' + installer.OLD_LOADER.format('shale.lua') + '\n')
        skipped, output = self.uninstall()
        self.assertEqual(skipped, 0)
        self.assertEqual(self.config.read_text(), 'require("keys")\nmine()\n')
        self.assertEqual(keys.read_text(), 'hl.bind("SUPER + V", x)\n')

    def test_an_install_known_only_from_its_backups(self):
        shale, qml = self.config.parent / 'shale.lua', self.shell / 'shell.qml'
        qml.parent.mkdir(parents=True)
        installed = self.original + '\n' + installer.MARKER + '\n' + installer.OLD_LOADER.format('shale.lua') + '\n'
        files = [(shale, None, b'-- shortcuts\n'), (qml, None, b'qml'), (self.config, self.original.encode(), installed.encode())]
        state = self.home / '.local/state/shale/backups/20200101-000000-old'
        state.mkdir(parents=True)
        manifest = {'version': 1, 'home': str(self.home), 'files': []}
        for index, (path, original, data) in enumerate(files):
            path.write_bytes(data)
            if original is not None:
                (state / str(index)).write_bytes(original)
            manifest['files'].append({'path': str(path), 'backup': None if original is None else str(index), 'mode': 0o644,
                                      'installed_sha256': installer.digest(data)})
        (state / 'manifest.json').write_text(json.dumps(manifest))
        skipped, output = self.uninstall()
        self.assertEqual(skipped, 0, output)
        self.assertEqual(self.config.read_text(), self.original)
        self.assertFalse(shale.exists())
        self.assertFalse(self.shell.exists())
        self.assertIn('this install has no record of it', output)
        self.assertEqual(self.uninstall()[0], 0)

    def test_what_install_sh_set_up_is_listed_not_removed(self):
        installer.remember_system(self.home, packages=['quickshell', 'bluez'], services=['bluetooth'])
        installer.remember_system(self.home, packages=['bluez', 'sddm'], boot=['sddm'], config=[str(self.config)])
        self.config.write_text('local menu = os.getenv("HOME") .. "/.local/bin/shale launcher"\n')
        self.install()
        skipped, output = self.uninstall()
        self.assertIn('sudo systemctl disable --now bluetooth.service', output)
        self.assertIn('sudo systemctl disable sddm.service', output)
        self.assertIn('sudo pacman -Rns quickshell bluez sddm', output)
        self.assertNotIn('pkexec', output)
        self.assertIn("~/.config/hypr/hyprland.lua, copied from Hyprland's example", output)
        self.assertIn('line 1 of ~/.config/hypr/hyprland.lua runs the shale command', output)
        self.assertFalse(any('pacman' in ' '.join(command) for command in self.commands))


    def test_the_example_copy_gets_its_app_menu_back(self):
        example = self.home / 'example.lua'
        example.write_text('local terminal = "kitty"\nlocal menu   = "hyprlauncher"  -- apps\nhl.bind("SUPER + R", hl.dsp.exec_cmd(menu))\n')
        detected = {'packages': [], 'services': [], 'boot': [], 'config': True, 'notes': []}
        with patch.object(installer.system, 'EXAMPLE_CONFIG', example):
            with patch('builtins.print'):
                installer.setup_system(self.home, apply=True, yes=True, run=self.run_command, detected=detected)
            self.assertIn('local menu   = os.getenv("HOME") .. "/.local/bin/shale launcher"  -- apps\n', self.config.read_text())
            self.install()
            skipped, output = self.uninstall()
        self.assertEqual(skipped, 0, output)
        self.assertEqual(self.config.read_text(), example.read_text())
        self.assertIn("goes back to the example's hyprlauncher", output)
        self.assertNotIn('runs the shale command', output)
        # Undone by its own backup, like the rest of the uninstall.
        state, manifest = installer.backup_manifests(self.home)[-1]
        entry = next(entry for entry in manifest['files'] if entry['path'] == str(self.config))
        self.assertIn('local menu   = os.getenv', (state / entry['backup']).read_text())

    def test_a_changed_app_menu_or_a_config_of_the_users_keeps_the_warning(self):
        with patch.object(installer.system, 'EXAMPLE_CONFIG', self.home / 'missing.lua'):
            original, rewritten = installer.example_menu()
            self.assertEqual(original, 'local menu        = "hyprlauncher"')
            self.assertEqual(rewritten, 'local menu        = os.getenv("HOME") .. "/.local/bin/shale launcher"')
            for text, recorded in ((rewritten + '\n', False), (rewritten + ' .. " --x"\n', True)):
                with self.subTest(text=text, recorded=recorded):
                    self.config.write_text(text)
                    if recorded:
                        installer.remember_system(self.home, config=[str(self.config)])
                    skipped, output = self.uninstall()
                    self.assertEqual(self.config.read_text(), text)
                    self.assertIn('line 1 of ~/.config/hypr/hyprland.lua runs the shale command', output)
                    self.assertIn('nothing to remove', output)


class UpdateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()

    def git(self, *args, cwd):
        subprocess.run(['git', '-c', 'user.name=t', '-c', 'user.email=t@t', '-c', 'init.defaultBranch=main', '-c', 'commit.gpgsign=false', *args],
                       cwd=cwd, check=True, capture_output=True)

    def pull(self, root):
        output = io.StringIO()
        with patch('sys.stdout', output):
            pulled = installer.pull(root, lambda command, **options: subprocess.run(command, **{'capture_output': True, **options}))
        return pulled, output.getvalue()

    @unittest.skipUnless(shutil.which('git'), 'git not installed')
    def test_pull_fast_forwards_a_checkout_that_tracks_a_remote(self):
        remote, checkout, other = self.base / 'remote.git', self.base / 'checkout', self.base / 'other'
        self.git('init', '--bare', str(remote), cwd=self.base)
        self.git('clone', str(remote), str(other), cwd=self.base)
        (other / 'VERSION').write_text('1.0.0\n')
        self.git('add', 'VERSION', cwd=other)
        self.git('commit', '-m', 'one', cwd=other)
        self.git('push', 'origin', 'HEAD', cwd=other)
        self.git('clone', str(remote), str(checkout), cwd=self.base)
        (other / 'VERSION').write_text('1.1.0\n')
        self.git('commit', '-am', 'two', cwd=other)
        self.git('push', 'origin', 'HEAD', cwd=other)
        self.assertTrue(self.pull(checkout)[0])
        self.assertEqual(installer.version(checkout), '1.1.0')
        # A checkout with local commits of its own can't fast-forward: nothing is installed.
        (checkout / 'VERSION').write_text('9.9.9\n')
        self.git('commit', '-am', 'mine', cwd=checkout)
        (other / 'VERSION').write_text('1.2.0\n')
        self.git('commit', '-am', 'three', cwd=other)
        self.git('push', 'origin', 'HEAD', cwd=other)
        with self.assertRaisesRegex(ValueError, 'nothing was installed'):
            self.pull(checkout)

    @unittest.skipUnless(shutil.which('git'), 'git not installed')
    def test_without_git_or_a_remote_branch_the_local_copy_is_installed(self):
        pulled, output = self.pull(self.base)
        self.assertFalse(pulled)
        self.assertIn('is not a git checkout', output)
        self.git('init', cwd=self.base)
        pulled, output = self.pull(self.base)
        self.assertFalse(pulled)
        self.assertIn("doesn't track a remote branch", output)

    def main(self, *args, running=False, own=True, output=None):
        """main() on the test home, as the user's own home (Path.home) unless `own` is False."""
        output, home = output or io.StringIO(), str(self.base)
        with patch.object(sys, 'argv', ['install.py', '--home', home, *args]), patch('sys.stdout', output), \
                patch.object(installer.Path, 'home', return_value=self.base if own else self.base / 'other'), \
                patch.object(installer, 'shell_running', return_value=running) as shell_running, \
                patch.object(installer, 'missing_packages', return_value=['adwaita-fonts']), \
                patch.object(installer, 'setup_system') as setup, patch.object(installer, 'install') as install, \
                patch.object(installer.subprocess, 'run') as run:
            installer.main()
        setup.assert_not_called()
        self.shell_running = shell_running
        return install, run, output.getvalue()

    def test_update_pulls_then_runs_the_pulled_installer(self):
        class Output(io.StringIO):
            flushed = 0

            def flush(self):
                self.flushed = self.tell()
        output = Output()

        def pull():
            print('Updating from origin/main')
            return True

        def execv(*args):
            # What was printed so far reaches a pipe before the pulled installer replaces this process.
            self.assertEqual(output.flushed, output.tell())
            raise SystemExit
        with patch.object(installer, 'pull', side_effect=pull), patch.object(installer.os, 'execv', side_effect=execv) as exec_, \
                self.assertRaises(SystemExit):
            self.main('--apply', '--update', '--yes', output=output)
        self.assertEqual(exec_.call_args.args[1][1:], [str(installer.ROOT / 'scripts/install.py'), '--home', str(self.base),
                                                        '--apply', '--yes', '--pulled'])

    def test_update_without_apply_only_shows_the_plan(self):
        with patch.object(installer, 'pull') as pull, patch.object(installer.os, 'execv') as execv:
            install, run, output = self.main('--update', running=True)
        pull.assert_not_called()
        execv.assert_not_called()
        self.shell_running.assert_not_called()
        run.assert_not_called()
        self.assertIn('Preview only: with --apply, this first runs git pull --ff-only', output)
        self.assertFalse(install.call_args.args[1])
        self.assertEqual(install.call_args.kwargs['packages'], ['adwaita-fonts'])

    def test_after_the_pull_it_reinstalls_without_packages_and_restarts_a_running_shell(self):
        install, run, output = self.main('--apply', '--pulled', running=True)
        self.assertIn(f'Updating Shale unknown to {installer.version()}', output)
        self.assertEqual(install.call_args.kwargs['packages'], ['adwaita-fonts'])
        self.assertFalse(install.call_args.kwargs['hints'])
        run.assert_called_once_with([str(self.base / '.local/bin/shale'), 'restart'])
        self.assertIn('Restarted the shell', output)
        install, run, output = self.main('--apply', '--pulled', running=False)
        self.assertTrue(install.call_args.kwargs['hints'])
        run.assert_not_called()
        # Without a remote to pull from, --update goes on with the local copy.
        with patch.object(installer, 'pull', return_value=False):
            install, run, output = self.main('--apply', '--update', running=True)
        run.assert_called_once()

    def test_another_home_is_updated_without_touching_the_running_session(self):
        install, run, output = self.main('--apply', '--pulled', running=True, own=False)
        install.assert_called_once()
        self.shell_running.assert_not_called()
        run.assert_not_called()
        self.assertTrue(install.call_args.kwargs['hints'])
        self.assertIn(f'Service steps skipped: {self.base} is not your home directory', output)
        self.assertNotIn('Restarted', output)
        install, run, output = self.main('--apply', '--pulled', running=True)
        self.shell_running.assert_called_once()
        run.assert_called_once_with([str(self.base / '.local/bin/shale'), 'restart'])
        self.assertNotIn('Service steps skipped', output)

    def test_missing_packages_are_shown_not_installed(self):
        output = io.StringIO()
        with patch.object(installer, 'payload', return_value={}), patch('sys.stdout', output):
            installer.install(self.base, True, checks=lambda: ([], ['fd'], []), packages=['fd', 'adwaita-fonts'])
        self.assertIn('Optional, for every feature: sudo pacman -S --needed fd\n', output.getvalue())
        self.assertIn('Not installed yet (./install.sh adds them): sudo pacman -S --needed adwaita-fonts', output.getvalue())


class MainTests(unittest.TestCase):
    def main(self, *args):
        output = io.StringIO()
        with patch.object(sys, 'argv', ['install.py', *args]), patch('sys.stdout', output):
            installer.main()
        return output.getvalue()

    def test_install_sh_help_leaves_out_what_it_always_passes(self):
        script = Path(installer.__file__)
        result = subprocess.run([sys.executable, str(script), '--help'], capture_output=True, text=True,
                                env={**os.environ, 'SHALE_INSTALLER': 'install.sh'})
        self.assertIn('usage: ./install.sh', result.stdout)
        for option in ('--apply', '--setup', '--rollback', '--pulled'):
            self.assertNotIn(option, result.stdout)
        for option in ('--no-packages', '--update', '--uninstall', '--purge', '--ask-again', '--version'):
            self.assertIn(option, result.stdout)
        self.assertIn('--apply', subprocess.run([sys.executable, str(script), '--help'], capture_output=True, text=True,
                                                env={k: v for k, v in os.environ.items() if k != 'SHALE_INSTALLER'}).stdout)

    def test_setup_options_without_setup_are_reported(self):
        with tempfile.TemporaryDirectory() as home, patch.object(installer, 'install') as install:
            output = self.main('--home', home, '--no-packages', '--no-login-screen')
        self.assertIn('--no-packages and --no-login-screen only apply with --setup', output)
        install.assert_called_once()

    def test_setup_without_apply_changes_nothing(self):
        plan = {'packages': [('quickshell', 'the shell')], 'services': ['bluetooth'], 'boot': [], 'config': False, 'notes': []}
        with tempfile.TemporaryDirectory() as home, patch.object(installer.system, 'plan', return_value=plan), \
                patch.object(installer.subprocess, 'run') as run, patch.object(installer, 'install') as install:
            output = self.main('--home', home, '--setup')
        run.assert_not_called()
        self.assertIn('Preview only', output)
        install.assert_called_once()
        self.assertFalse(install.call_args.args[1])

    def test_rollback_exits_non_zero_when_files_are_left_alone(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp).resolve()
            state = home / 'backup'
            state.mkdir()
            (state / 'manifest.json').write_text(json.dumps({'version': 2, 'home': str(home), 'files': [
                {'path': str(home / 'gone'), 'backup': None, 'mode': 0o644, 'installed_sha256': 'x'}]}))
            with self.assertRaises(SystemExit) as exit, patch('sys.stderr', io.StringIO()):
                self.main('--home', str(home), '--rollback', str(state), '--apply')
        self.assertEqual(exit.exception.code, 1)

    def test_uninstall_exits_non_zero_when_files_are_left_alone(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp).resolve()
            installer.save_record(home, {str(home / '.local/bin/shale'): 'not what is there'})
            (home / '.local/bin').mkdir(parents=True)
            (home / '.local/bin/shale').write_text('mine')
            error = io.StringIO()
            with self.assertRaises(SystemExit) as exit, patch('sys.stderr', error):
                self.main('--home', str(home), '--uninstall', '--apply', '--yes')
            self.assertEqual((home / '.local/bin/shale').read_text(), 'mine')
        self.assertEqual(exit.exception.code, 1)
        self.assertIn('1 file left alone (skip above)', error.getvalue())

    def test_install_sh_uninstall_does_no_package_setup(self):
        with tempfile.TemporaryDirectory() as home:
            result = subprocess.run(['bash', str(installer.ROOT / 'install.sh'), '--uninstall', '--home', home],
                                    capture_output=True, text=True, stdin=subprocess.DEVNULL)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('Checking this machine', result.stdout)
        self.assertIn('Uninstalling Shale', result.stdout)
        self.assertIn('nothing to remove', result.stdout)


if __name__ == '__main__':
    unittest.main()
