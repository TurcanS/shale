#!/usr/bin/env python3
"""Preview, install, or restore Shale's TuneD power profiles for tuned-ppd (--apply asks for your password through sudo)."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

SCRIPT = Path(__file__).resolve()
ROOT = SCRIPT.parents[1]
# What runs as root is named by absolute path: pkexec, used when there's no sudo, starts it with a clean environment.
SUDO, PKEXEC, PYTHON, SYSTEMCTL = '/usr/bin/sudo', '/usr/bin/pkexec', '/usr/bin/python3', '/usr/bin/systemctl'
AS_ROOT = f'sudo python3 {SCRIPT}'
SOURCE = ROOT / 'integration/tuned'
PROFILES = ('shale-powersave', 'shale-balanced', 'shale-balanced-battery', 'shale-performance')
SERVICES = ('tuned.service', 'tuned-ppd.service')
# The profiles use governor=powersave with EPP hints. On these drivers that is a dynamic governor;
# on acpi-cpufreq or passive amd-pstate it would pin every core at its lowest clock.
DRIVERS = ('intel_pstate', 'amd-pstate-epp')
DRIVER = Path('/sys/devices/system/cpu/cpu0/cpufreq/scaling_driver')

def check_driver(path=DRIVER):
    try:
        driver = path.read_text().strip()
    except OSError:
        driver = 'unknown'
    if driver not in DRIVERS:
        raise ValueError(f'These profiles need the intel_pstate or amd-pstate-epp CPU driver; this machine uses {driver}. '
                         'Keep your current power profiles.')

def restart(apply):
    """Restart TuneD so it reads the profiles. Returns the services that aren't running: try-restart leaves those
    stopped, and the profiles only apply once they start."""
    stopped = []
    for service in SERVICES:
        print(f'RESTART {service}')
        if apply:
            subprocess.run([SYSTEMCTL, 'try-restart', service], check=True)
            if subprocess.run([SYSTEMCTL, '--quiet', 'is-active', service]).returncode != 0:
                stopped.append(service)
    return stopped

def report(stopped, done):
    if stopped:
        print(f'\nWarning: {" and ".join(stopped)} {"is" if len(stopped) == 1 else "are"} not running, so the power modes '
              f'apply once {"it starts" if len(stopped) == 1 else "they start"}: sudo systemctl enable --now ' + ' '.join(stopped))
    print('\n' + done)

def ours(path):
    return '=shale-' in path.read_text()

def atomic_copy(source, target):
    fd, temporary = tempfile.mkstemp(dir=target.parent, prefix='.shale-')
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(source.read_bytes())
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o644)
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)

def install(etc, apply=False, driver=DRIVER):
    check_driver(driver)
    if not (etc / 'ppd.conf').is_file():
        raise ValueError(f'tuned-ppd is not configured: {etc / "ppd.conf"} is missing')
    for name in PROFILES:
        target = etc / 'profiles' / name / 'tuned.conf'
        print(('UPDATE ' if target.exists() else 'CREATE ') + str(target))
    # A reinstall must not replace the backup of the original with a copy of Shale's own file.
    reinstall = ours(etc / 'ppd.conf')
    backups = sorted(etc.glob('ppd.conf.shale-*'))
    if reinstall:
        backup = backups[-1] if backups else None
        print(f'KEEP {backup}' if backup else 'NOTE ppd.conf already uses Shale profiles; no original backup found')
    else:
        backup = etc / ('ppd.conf.shale-' + time.strftime('%Y%m%d-%H%M%S'))
        print(f'BACKUP {etc / "ppd.conf"} -> {backup}')
    print(f'UPDATE {etc / "ppd.conf"}')
    if not apply:
        restart(False)
        print('\nPreview only. Re-run with --apply to install; it asks for your password through sudo.')
        return
    if os.geteuid() != 0:
        raise ValueError(f'Installing system profiles needs root: {AS_ROOT} --apply')
    for name in PROFILES:
        target = etc / 'profiles' / name
        target.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(SOURCE / name / 'tuned.conf', target / 'tuned.conf')
    if not reinstall:
        shutil.copy2(etc / 'ppd.conf', backup)
    atomic_copy(SOURCE / 'ppd.conf', etc / 'ppd.conf')
    report(restart(True), 'Installed.' + (f' Restore: {AS_ROOT} --restore {backup.absolute()} --apply' if backup else ''))

def restore(etc, backup, apply=False):
    if not backup.is_file() or backup.parent.resolve() != etc.resolve():
        raise ValueError(f'Not a ppd.conf backup in {etc}: {backup}')
    print(f'RESTORE {etc / "ppd.conf"} <- {backup}')
    for name in PROFILES:
        print(f'REMOVE {etc / "profiles" / name}')
    if not apply:
        restart(False)
        print('\nPreview only. Re-run with --apply to restore; it asks for your password through sudo.')
        return
    if os.geteuid() != 0:
        raise ValueError(f'Restoring system profiles needs root: {AS_ROOT} --restore {backup.absolute()} --apply')
    atomic_copy(backup, etc / 'ppd.conf')
    stopped = restart(True)
    for name in PROFILES:
        shutil.rmtree(etc / 'profiles' / name, ignore_errors=True)
    report(stopped, 'Restored.')

def elevated(args):
    """This run again as root through sudo, or pkexec where there's no sudo, with every path absolute; None
    without either."""
    tool = next((tool for tool in (SUDO, PKEXEC) if os.path.exists(tool)), None)
    if tool is None:
        return None
    command = [tool, PYTHON, str(SCRIPT), '--apply', '--etc', str(args.etc.absolute())]
    return command + (['--restore', str(args.restore.absolute())] if args.restore else [])

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--etc', type=Path, default=Path('/etc/tuned'), help='TuneD configuration directory')
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--restore', type=Path, metavar='PPD_BACKUP')
    args = parser.parse_args()
    if args.apply and os.geteuid() != 0:
        command = elevated(args)
        if not command:
            parser.exit(1, 'Error: --apply needs root, and neither sudo nor pkexec is installed. Run this as root.\n')
        if command[0] == PKEXEC:
            print('sudo is not installed, so this uses pkexec.')
        sys.stdout.flush()
        os.execv(command[0], command)
    try:
        restore(args.etc, args.restore, args.apply) if args.restore else install(args.etc, args.apply)
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        parser.exit(1, f'Error: {exc}\n')

if __name__ == '__main__':
    main()
