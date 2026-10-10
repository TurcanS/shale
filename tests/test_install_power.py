import importlib.util
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('install_power', Path(__file__).parents[1] / 'scripts/install-power.py')
power = importlib.util.module_from_spec(spec)
spec.loader.exec_module(power)


class InstallPowerTests(unittest.TestCase):
    def test_reinstall_keeps_the_original_backup(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(power.os, 'geteuid', return_value=0), \
                patch.object(power, 'restart', return_value=[]), patch('builtins.print'):
            etc = Path(temp)
            (etc / 'ppd.conf').write_text('[profiles]\nbalanced=balanced\n')
            driver = etc / 'scaling_driver'
            driver.write_text('intel_pstate\n')
            power.install(etc, apply=True, driver=driver)
            backups = list(etc.glob('ppd.conf.shale-*'))
            self.assertEqual(len(backups), 1)
            self.assertIn('=shale-', (etc / 'ppd.conf').read_text())
            power.install(etc, apply=True, driver=driver)
            self.assertEqual(list(etc.glob('ppd.conf.shale-*')), backups)
            self.assertEqual(backups[0].read_text(), '[profiles]\nbalanced=balanced\n')
            self.assertTrue((etc / 'profiles/shale-balanced/tuned.conf').is_file())
            power.restore(etc, backups[0], apply=True)
            self.assertEqual((etc / 'ppd.conf').read_text(), '[profiles]\nbalanced=balanced\n')
            self.assertFalse((etc / 'profiles/shale-balanced').exists())

    def test_refuses_cpu_drivers_where_powersave_means_minimum_clock(self):
        with tempfile.TemporaryDirectory() as temp:
            etc = Path(temp)
            (etc / 'ppd.conf').write_text('[profiles]\n')
            driver = etc / 'scaling_driver'
            for name in ('acpi-cpufreq', 'amd-pstate'):
                driver.write_text(name + '\n')
                with self.subTest(driver=name), self.assertRaises(ValueError):
                    power.install(etc, driver=driver)
            driver.write_text('amd-pstate-epp\n')
            with patch('builtins.print'):
                power.install(etc, driver=driver)

    def elevate(self, present):
        output = io.StringIO()
        with patch.object(sys, 'argv', ['install-power.py', '--apply', '--restore', 'ppd.conf.shale-1']), \
                patch.object(power.os, 'geteuid', return_value=1000), patch.object(power.os.path, 'exists', lambda path: path in present), \
                patch.object(power.os, 'execv', side_effect=SystemExit(0)) as execv, patch('sys.stdout', output), \
                patch('sys.stderr', output), self.assertRaises(SystemExit) as exit:
            power.main()
        return execv.call_args.args if execv.called else None, exit.exception.code, output.getvalue()

    def test_apply_runs_itself_again_through_sudo_with_absolute_paths(self):
        rest = ['/usr/bin/python3', str(Path(power.__file__).resolve()), '--apply', '--etc', '/etc/tuned',
                '--restore', os.path.join(os.getcwd(), 'ppd.conf.shale-1')]
        call, _, output = self.elevate({'/usr/bin/sudo', '/usr/bin/pkexec'})
        self.assertEqual(call, ('/usr/bin/sudo', ['/usr/bin/sudo', *rest]))
        self.assertNotIn('pkexec', output)
        # pkexec only where there's no sudo, and it says so.
        call, _, output = self.elevate({'/usr/bin/pkexec'})
        self.assertEqual(call, ('/usr/bin/pkexec', ['/usr/bin/pkexec', *rest]))
        self.assertIn('sudo is not installed, so this uses pkexec', output)
        call, code, output = self.elevate(set())
        self.assertIsNone(call)
        self.assertEqual(code, 1)
        self.assertIn('neither sudo nor pkexec is installed', output)

    def test_a_stopped_tuned_is_reported_instead_of_a_plain_installed(self):
        def run(command, **options):
            return subprocess.CompletedProcess(command, 3 if 'is-active' in command else 0)
        with tempfile.TemporaryDirectory() as temp, patch.object(power.os, 'geteuid', return_value=0), \
                patch.object(power.subprocess, 'run', side_effect=run), patch('builtins.print') as printed:
            etc = Path(temp)
            (etc / 'ppd.conf').write_text('[profiles]\n')
            (etc / 'scaling_driver').write_text('intel_pstate\n')
            power.install(etc, apply=True, driver=etc / 'scaling_driver')
        output = str(printed.call_args_list)
        self.assertIn('tuned.service and tuned-ppd.service are not running', output)
        self.assertIn('sudo systemctl enable --now tuned.service tuned-ppd.service', output)
        self.assertIn(f'Restore: sudo python3 {Path(power.__file__).resolve()} --restore ', output)
        self.assertNotIn('pkexec', output)


if __name__ == '__main__':
    unittest.main()
