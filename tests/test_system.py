import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import unittest.mock
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import system

spec = importlib.util.spec_from_file_location('installer', Path(__file__).parents[1] / 'scripts/install.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)

DESKTOP = {'battery': False, 'backlight': False, 'bluetooth': False, 'nvidia': False, 'nvidia_driver': False}
LAPTOP = {'battery': True, 'backlight': True, 'bluetooth': True, 'nvidia': False, 'nvidia_driver': False}
SUDO, PACMAN, SYSTEMCTL = '/usr/bin/sudo', '/usr/bin/pacman', '/usr/bin/systemctl'


def nothing_installed(names):
    return list(names)


class HardwareTests(unittest.TestCase):
    def test_reads_sysfs(self):
        with tempfile.TemporaryDirectory() as temp:
            sys_ = Path(temp)
            self.assertEqual(system.hardware(sys_), DESKTOP)
            for path, value in {'class/power_supply/BAT0/type': 'Battery', 'class/power_supply/hidpp_battery_0/type': 'Battery',
                                'class/power_supply/hidpp_battery_0/scope': 'Device', 'class/backlight/intel_backlight/brightness': '5',
                                'class/bluetooth/hci0/name': 'x', 'bus/pci/devices/0000:01:00.0/vendor': '0x10de',
                                'bus/pci/devices/0000:01:00.0/class': '0x030000'}.items():
                (sys_ / path).parent.mkdir(parents=True, exist_ok=True)
                (sys_ / path).write_text(value + '\n')
            facts = system.hardware(sys_)
            self.assertEqual(facts, {**LAPTOP, 'nvidia': True})

    def test_a_wireless_mouse_battery_is_not_a_laptop(self):
        with tempfile.TemporaryDirectory() as temp:
            supply = Path(temp) / 'class/power_supply/hidpp_battery_0'
            supply.mkdir(parents=True)
            (supply / 'type').write_text('Battery\n')
            (supply / 'scope').write_text('Device\n')
            self.assertFalse(system.hardware(Path(temp))['battery'])


class PlanTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        (self.home / '.config/hypr').mkdir(parents=True)
        (self.home / '.config/hypr/hyprland.lua').write_text('')

    def plan(self, facts, absent=nothing_installed, running=('display-manager',), which=lambda name: True, environ=None, connected=False):
        network = [name for name in running if system.NETWORK_UNITS.fullmatch(name + '.service')]
        return system.plan(self.home, facts, absent, lambda name: 'active' if name in running else '', which,
                           {'WAYLAND_DISPLAY': 'wayland-1'} if environ is None else environ,
                           network=lambda: network, connected=lambda: connected)

    def names(self, result):
        return [name for name, _ in result['packages']]

    def test_desktop_gets_only_the_core(self):
        result = self.plan(DESKTOP, running=('NetworkManager', 'display-manager'))
        self.assertEqual(self.names(result), [name for name, _ in system.CORE + system.DESKTOP] + ['hyprpaper'])
        self.assertEqual(result['services'], [])
        self.assertEqual(result['boot'], [])
        self.assertEqual(result['notes'], [])

    def test_laptop_hardware_adds_what_it_needs(self):
        result = self.plan(LAPTOP)
        for name in ('upower', 'power-profiles-daemon', 'brightnessctl', 'bluez', 'bluez-utils', 'networkmanager'):
            self.assertIn(name, self.names(result))
        self.assertEqual(result['services'], ['power-profiles-daemon', 'bluetooth', 'NetworkManager'])

    def test_a_polkit_agent_and_webp_support_are_planned(self):
        names = self.names(self.plan(DESKTOP, running=('NetworkManager', 'display-manager')))
        self.assertIn('hyprpolkitagent', names)  # it pulls in polkit itself
        self.assertNotIn('polkit', names)
        self.assertIn('qt6-imageformats', names)

    def test_other_power_managers_are_kept(self):
        for manager in ('tlp', 'tuned', 'auto-cpufreq'):
            with self.subTest(manager=manager):
                result = self.plan(LAPTOP, absent=lambda names: [n for n in names if n != manager])
                self.assertNotIn('power-profiles-daemon', self.names(result))
                self.assertNotIn('power-profiles-daemon', result['services'])
                self.assertTrue(any(note.startswith(manager + ' manages power') for note in result['notes']))
        self.assertTrue(any('Add tuned-ppd' in note for note in self.plan(LAPTOP, absent=lambda names: [n for n in names if n != 'tuned'])['notes']))
        # tuned with tuned-ppd is a power-profiles provider: nothing to add, nothing to say.
        result = self.plan(LAPTOP, absent=lambda names: [n for n in names if n not in ('tuned', 'tuned-ppd')])
        self.assertNotIn('power-profiles-daemon', self.names(result))
        self.assertFalse(any('manages power' in note for note in result['notes']))

    def test_pulseaudio_is_a_conflict_pacman_has_to_ask_about(self):
        result = self.plan(DESKTOP, absent=lambda names: [n for n in names if n != 'pulseaudio'], running=('NetworkManager', 'display-manager'))
        self.assertIn('pipewire-pulse', self.names(result))
        self.assertEqual(result['conflicts'], ['pulseaudio'])
        self.assertTrue(any('answer y' in note and 'bluetooth' not in note for note in result['notes']))
        installed = ('pulseaudio', 'pulseaudio-bluetooth')
        result = self.plan(DESKTOP, absent=lambda names: [n for n in names if n not in installed], running=('NetworkManager', 'display-manager'))
        self.assertTrue(any('sudo pacman -R pulseaudio-bluetooth' in note for note in result['notes']))
        self.assertEqual(self.plan(DESKTOP, running=('NetworkManager', 'display-manager'))['conflicts'], [])

    def test_existing_choices_are_kept(self):
        installed = {'tuned-ppd', 'awww'}
        result = self.plan(LAPTOP, absent=lambda names: [n for n in names if n not in installed], running=('iwd', 'bluetooth', 'display-manager'))
        names = self.names(result)
        for name in ('power-profiles-daemon', 'hyprpaper', 'networkmanager'):
            self.assertNotIn(name, names)
        self.assertNotIn('NetworkManager', result['services'])
        self.assertTrue(any(note.startswith('iwd manages your network') for note in result['notes']))

    def test_other_network_setups_and_unknown_ones_that_are_online_are_kept(self):
        for unit in ('netctl-auto@wlan0', 'wpa_supplicant@wlp2s0', 'dhcpcd@enp3s0', 'systemd-networkd'):
            with self.subTest(unit=unit):
                result = self.plan(LAPTOP, running=(unit, 'display-manager'))
                self.assertNotIn('networkmanager', self.names(result))
                self.assertNotIn('NetworkManager', result['services'])
        result = self.plan(LAPTOP, running=('display-manager',), connected=True)
        self.assertNotIn('networkmanager', self.names(result))
        self.assertTrue(any('does not recognise' in note for note in result['notes']))
        self.assertIn('networkmanager', self.names(self.plan(LAPTOP, running=('display-manager',), connected=False)))

    def test_reading_units_and_routes(self):
        listing = subprocess.CompletedProcess([], 0, stdout='bluetooth.service loaded active running Bluetooth\n'
                                              'netctl-auto@wlan0.service loaded active running Automatic wireless\n'
                                              'iwd.service loaded active running Wireless service\n')
        failed = subprocess.CompletedProcess([], 1, stdout='', stderr='System has not been booted with systemd')
        with tempfile.TemporaryDirectory() as temp:
            units = Path(temp)
            self.assertEqual(system.network_units(run=lambda *a, **k: listing, units=units), ['netctl-auto@wlan0', 'iwd'])
            # Enabled but not running (or inside a chroot, where systemctl can't list running units) still counts.
            (units / 'multi-user.target.wants').mkdir()
            for name in ('iwd.service', 'systemd-networkd.service', 'sshd.service'):
                (units / 'multi-user.target.wants' / name).symlink_to('/usr/lib/systemd/system/' + name)
            self.assertEqual(system.network_units(run=lambda *a, **k: listing, units=units),
                             ['netctl-auto@wlan0', 'iwd', 'systemd-networkd'])
            self.assertEqual(system.network_units(run=lambda *a, **k: failed, units=units), ['iwd', 'systemd-networkd'])

            def missing(*args, **kwargs):
                raise FileNotFoundError('systemctl')
            self.assertEqual(system.network_units(run=missing, units=units), ['iwd', 'systemd-networkd'])

        with tempfile.TemporaryDirectory() as temp:
            route, route6, booted = Path(temp) / 'route', Path(temp) / 'ipv6_route', Path(temp) / 'systemd'
            booted.mkdir()
            reject = '0' * 32 + ' 00 ' + '0' * 32 + ' 00 ' + '0' * 32 + ' ffffffff 00000001 00000000 00200200 lo\n'
            default6 = '0' * 32 + ' 00 ' + '0' * 32 + ' 00 fe800000000000000000000000000001 00000400 00000001 00000000 00450003 wlan0\n'
            route.write_text('Iface\tDestination\tGateway\nwlan0\t000A14AC\t00000000\n')
            route6.write_text(reject)
            self.assertFalse(system.online(route, route6, booted))
            route6.write_text(reject + default6)
            self.assertTrue(system.online(route, route6, booted))
            route.write_text('Iface\tDestination\tGateway\nwlan0\t00000000\t010A14AC\n')
            route6.unlink()
            self.assertTrue(system.online(route, route6, booted))
            self.assertFalse(system.online(Path(temp) / 'missing', route6, booted))
            # In a chroot the routes are the host's (the live ISO's), not this system's.
            self.assertFalse(system.online(route, route6, Path(temp) / 'not-booted'))

    def test_installed_packages_are_not_planned(self):
        self.assertEqual(self.plan(DESKTOP, absent=lambda names: [], running=('NetworkManager', 'display-manager'))['packages'], [])

    def test_fresh_config_and_terminal(self):
        (self.home / '.config/hypr/hyprland.lua').unlink()
        example = self.home / 'example.lua'
        example.write_text('local terminal    = "kitty"\n')
        with unittest.mock.patch.object(system, 'EXAMPLE_CONFIG', example):
            result = self.plan(DESKTOP, running=('NetworkManager', 'display-manager'), which=lambda name: False)
        self.assertTrue(result['config'])
        self.assertIn('kitty', self.names(result))
        with unittest.mock.patch.object(system, 'EXAMPLE_CONFIG', example):
            self.assertNotIn('kitty', self.names(self.plan(DESKTOP, running=('NetworkManager', 'display-manager'), which=lambda name: name == 'kitty')))

    def test_the_configured_terminal_is_installed(self):
        (self.home / '.config/hypr/hyprland.lua').write_text('local terminal = "foot"\n')
        self.assertIn('foot', self.names(self.plan(DESKTOP, running=('NetworkManager', 'display-manager'), which=lambda name: False)))
        self.assertNotIn('foot', self.names(self.plan(DESKTOP, running=('NetworkManager', 'display-manager'), which=lambda name: name == 'foot')))
        (self.home / '.config/hypr/hyprland.lua').write_text('local terminal = "my-own-term"\n')
        self.assertFalse(any('Super+Q' in reason for _, reason in self.plan(DESKTOP, running=('NetworkManager', 'display-manager'), which=lambda name: False)['packages']))

    def test_login_screen_only_on_a_fresh_setup(self):
        # Someone who already has a config and starts Hyprland from a TTY keeps doing so.
        self.assertNotIn('sddm', self.names(self.plan(DESKTOP, running=('NetworkManager',), environ={})))
        (self.home / '.config/hypr/hyprland.lua').unlink()
        fresh = self.plan(DESKTOP, running=('NetworkManager',), environ={})
        self.assertIn('sddm', self.names(fresh))
        self.assertEqual(fresh['boot'], ['sddm'])
        self.assertNotIn('sddm', self.names(self.plan(DESKTOP, running=('NetworkManager',))))  # inside a desktop
        self.assertNotIn('sddm', self.names(self.plan(DESKTOP, running=('NetworkManager', 'display-manager'), environ={})))

    def test_classic_config_is_never_overridden(self):
        (self.home / '.config/hypr/hyprland.lua').unlink()
        (self.home / '.config/hypr/hyprland.conf').write_text('')
        result = self.plan(DESKTOP, running=('NetworkManager', 'display-manager'))
        self.assertFalse(result['config'])
        self.assertTrue(any('hyprland.conf' in note for note in result['notes']))

    def test_nvidia_without_a_driver_is_a_note_not_a_package(self):
        result = self.plan({**DESKTOP, 'nvidia': True}, running=('NetworkManager', 'display-manager'))
        self.assertTrue(any('NVIDIA' in note for note in result['notes']))
        self.assertFalse(any('nvidia' in name for name in self.names(result)))
        self.assertEqual(self.plan({**DESKTOP, 'nvidia': True, 'nvidia_driver': True}, running=('NetworkManager', 'display-manager'))['notes'], [])


class SetupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.commands = []

    def run_command(self, command, **options):
        self.commands.append(command)
        return subprocess.CompletedProcess(command, 0)

    def setup(self, detected, **options):
        with patch('builtins.print'), patch.object(installer, 'privileged', return_value=[SUDO]):
            installer.setup_system(self.home, apply=True, run=self.run_command, detected=detected, **options)

    def test_installs_packages_enables_services_and_copies_the_example(self):
        example = self.home / 'example.lua'
        example.write_text('local menu        = "hyprlauncher"\n')
        detected = {'packages': [('quickshell', 'the shell'), ('bluez', 'Bluetooth')], 'services': ['bluetooth'], 'boot': ['sddm'], 'config': True, 'notes': []}
        with patch.object(installer.system, 'EXAMPLE_CONFIG', example):
            self.setup(detected, yes=True)
        self.assertEqual(self.commands, [[SUDO, PACMAN, '-S', '--needed', '--noconfirm', 'quickshell', 'bluez'],
                                         [SUDO, SYSTEMCTL, 'enable', '--now', 'bluetooth.service'],
                                         [SUDO, SYSTEMCTL, 'enable', 'sddm.service']])
        self.assertEqual((self.home / '.config/hypr/hyprland.lua').read_text(),
                         'local menu        = os.getenv("HOME") .. "/.local/bin/shale launcher"\n')
        # Recorded for --uninstall, which lists them for the user to remove.
        self.assertEqual(json.loads((self.home / '.local/state/shale/system.json').read_text()),
                         {'version': 1, 'packages': ['quickshell', 'bluez'], 'services': ['bluetooth'], 'boot': ['sddm'],
                          'config': [str(self.home / '.config/hypr/hyprland.lua')]})
        self.setup({'packages': [('bluez', 'Bluetooth'), ('upower', 'battery')], 'services': [], 'config': False, 'notes': []}, yes=True)
        self.assertEqual(json.loads((self.home / '.local/state/shale/system.json').read_text())['packages'], ['quickshell', 'bluez', 'upower'])

    def test_nothing_is_recorded_when_pacman_fails(self):
        detected = {'packages': [('quickshell', 'the shell')], 'services': ['bluetooth'], 'config': False, 'notes': []}
        self.run_command = lambda command, **options: subprocess.CompletedProcess(command, 1)
        with self.assertRaisesRegex(ValueError, 'pacman did not finish'):
            self.setup(detected, yes=True)
        self.assertFalse((self.home / '.local/state/shale/system.json').exists())

    def test_asks_first_and_stops_on_no(self):
        detected = {'packages': [('quickshell', 'the shell')], 'services': [], 'config': False, 'notes': []}
        with self.assertRaisesRegex(ValueError, 'nothing was installed'):
            self.setup(detected, interactive=True, read=lambda prompt: 'n')
        self.assertEqual(self.commands, [])
        self.setup(detected, interactive=True, read=lambda prompt: '')
        self.assertEqual(self.commands, [[SUDO, PACMAN, '-S', '--needed', 'quickshell']])

    def test_the_login_screen_can_be_declined_on_its_own(self):
        detected = {'packages': [('quickshell', 'the shell'), ('sddm', 'login screen')], 'services': [], 'boot': ['sddm'], 'config': False, 'notes': []}
        prompts, answers = [], iter(['n', 'y'])
        with patch('builtins.print') as printed, patch.object(installer, 'privileged', return_value=[SUDO]):
            installer.setup_system(self.home, apply=True, run=self.run_command, detected=detected, interactive=True,
                                   read=lambda prompt: prompts.append(prompt) or next(answers))
        # Asked before the summary, so the confirmed list no longer shows sddm.
        self.assertIn('SDDM', prompts[0])
        self.assertIn('Go ahead', prompts[1])
        self.assertNotIn('sddm', ' '.join(str(call.args) for call in printed.call_args_list))
        self.assertEqual(self.commands, [[SUDO, PACMAN, '-S', '--needed', 'quickshell']])
        self.commands.clear()
        self.setup(detected, yes=True, login_screen=False)
        self.assertEqual(self.commands, [[SUDO, PACMAN, '-S', '--needed', '--noconfirm', 'quickshell']])

    def test_nothing_to_do(self):
        self.setup({'packages': [], 'services': [], 'config': False, 'notes': []})
        self.assertEqual(self.commands, [])

    def test_a_preview_runs_nothing(self):
        detected = {'packages': [('quickshell', 'the shell')], 'services': ['bluetooth'], 'boot': ['sddm'], 'config': True, 'notes': []}
        with patch('builtins.print') as printed:
            installer.setup_system(self.home, run=self.run_command, detected=detected, interactive=True, read=self.fail)
        self.assertEqual(self.commands, [])
        self.assertIn('Preview only', str(printed.call_args_list))
        self.assertFalse((self.home / '.config/hypr/hyprland.lua').exists())

    def test_pacman_asks_about_conflicts_even_with_yes(self):
        detected = {'packages': [('pipewire-pulse', 'audio')], 'services': [], 'config': False, 'notes': [], 'conflicts': ['pulseaudio']}
        self.setup(detected, yes=True)
        self.assertEqual(self.commands, [[SUDO, PACMAN, '-S', '--needed', 'pipewire-pulse']])
        self.commands.clear()
        with self.assertRaisesRegex(ValueError, 'not a terminal'):
            self.setup(detected, yes=True, interactive=False)
        self.assertEqual(self.commands, [])

    def test_root_through_sudo_or_pkexec_without_sudo(self):
        notes = []
        self.assertEqual(installer.privileged(exists=lambda path: True, note=notes.append), [SUDO])
        self.assertEqual(notes, [])
        self.assertEqual(installer.privileged(exists=lambda path: path == '/usr/bin/pkexec', note=notes.append), ['/usr/bin/pkexec'])
        self.assertEqual(notes, ['  sudo is not installed, so this step uses pkexec.'])
        with self.assertRaisesRegex(ValueError, 'Neither sudo nor pkexec'):
            installer.privileged(exists=lambda path: False)


class ReportTests(unittest.TestCase):
    def test_shell_files_are_summarized(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp).resolve()
            shell = home / '.config/quickshell/shale'
            shell.mkdir(parents=True)
            (shell / 'same.qml').write_bytes(b'a')
            (shell / 'old.qml').write_bytes(b'a')
            resolved = {shell / 'same.qml': (b'a', 0o644), shell / 'old.qml': (b'b', 0o644), shell / 'new.qml': (b'c', 0o644),
                        home / '.config/hypr/shale.lua': (b'x', 0o644)}
            output = io.StringIO()
            with patch('sys.stdout', output):
                installer.report_files(home, resolved, [])
            text = output.getvalue()
            self.assertIn('create  ~/.config/hypr/shale.lua', text)
            self.assertIn('shell   ~/.config/quickshell/shale: 1 new, 1 changed, 1 unchanged', text)
            self.assertNotIn('same.qml', text)


if __name__ == '__main__':
    unittest.main()
