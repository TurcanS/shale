#!/usr/bin/env python3
"""Preview, install, or remove Wi-Fi power saving that follows the power mode (--apply asks for your password through sudo)."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile

SCRIPT = Path(__file__).resolve()
SOURCE = SCRIPT.parents[1] / 'integration/wifi-power'
PYTHON, SYSTEMCTL = '/usr/bin/python3', '/usr/bin/systemctl'
ROOT_TOOLS = ('/usr/bin/sudo', '/usr/bin/sudo-rs', '/usr/bin/doas', '/usr/bin/pkexec')
UNITS = ('shale-wifi-power.path', 'shale-wifi-power.service')
# Root runs a root-owned copy of the helper, never the repository's (user-writable) file.
FILES = (
    ('shale-wifi-power', Path('/usr/local/libexec/shale-wifi-power'), 0o755),
    ('shale-wifi-power.service', Path('/etc/systemd/system/shale-wifi-power.service'), 0o644),
    ('shale-wifi-power.path', Path('/etc/systemd/system/shale-wifi-power.path'), 0o644),
)
RUNTIME_CONF = Path('/run/NetworkManager/conf.d/50-shale-wifi-power.conf')
# Fixed settings that would override the mode's choice; offered for removal.
FIXED = (
    Path('/etc/NetworkManager/conf.d/wifi-powersave-off.conf'),
    Path('/etc/modprobe.d/rtw89-powersave-off.conf'),
)

def atomic_copy(source, target, mode):
    if source.is_symlink() or not source.is_file():
        raise ValueError(f'Not a regular file: {source}')
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=target.parent, prefix='.shale-')
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(source.read_bytes())
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)

def install(apply):
    if not any((Path('/sys/class/net') / name / 'phy80211').exists() for name in os.listdir('/sys/class/net')):
        raise ValueError('No Wi-Fi card found.')
    for name, target, _ in FILES:
        print(('UPDATE ' if target.exists() else 'CREATE ') + str(target))
    fixed = [path for path in FIXED if path.exists()]
    for path in fixed:
        print(f'REMOVE {path} (a fixed setting that would override the power mode)')
    print('ENABLE ' + ' '.join(UNITS))
    if not apply:
        print('\nPreview only. Re-run with --apply to install; it asks for your password through sudo.')
        return
    for name, target, mode in FILES:
        atomic_copy(SOURCE / name, target, mode)
    for path in fixed:
        path.unlink(missing_ok=True)
    subprocess.run([SYSTEMCTL, 'daemon-reload'], check=True)
    # reenable, not enable: an older install's boot link (multi-user.target) must go, or its ordering cycle stays.
    subprocess.run([SYSTEMCTL, 'reenable', *UNITS], check=True)
    subprocess.run([SYSTEMCTL, 'start', 'shale-wifi-power.path'], check=True)
    subprocess.run([SYSTEMCTL, 'start', 'shale-wifi-power.service'], check=True)
    print(f'\nInstalled. Check it: journalctl -u shale-wifi-power -n 5. Remove: sudo python3 {SCRIPT} --remove --apply')

def remove(apply):
    print('DISABLE ' + ' '.join(UNITS))
    for _, target, _ in FILES:
        print(f'REMOVE {target}')
    print(f'REMOVE {RUNTIME_CONF}')
    print('RELOAD systemd, NetworkManager')
    if not apply:
        print('\nPreview only. Re-run with --apply to remove; it asks for your password through sudo.')
        return
    subprocess.run([SYSTEMCTL, 'disable', '--now', *UNITS], check=False)
    for _, target, _ in FILES:
        target.unlink(missing_ok=True)
    RUNTIME_CONF.unlink(missing_ok=True)
    subprocess.run([SYSTEMCTL, 'daemon-reload'], check=True)
    subprocess.run(['nmcli', 'general', 'reload', 'conf'], check=False)
    print('\nRemoved. NetworkManager uses its own power saving setting again from the next connection.')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--remove', action='store_true')
    args = parser.parse_args()
    if args.apply and os.geteuid() != 0:
        tool = next((tool for tool in ROOT_TOOLS if os.path.exists(tool)), None)
        if tool is None:
            parser.exit(1, 'Error: --apply needs root, and no sudo, doas or pkexec is installed. Run this as root.\n')
        sys.stdout.flush()
        os.execv(tool, [tool, PYTHON, str(SCRIPT), '--apply'] + (['--remove'] if args.remove else []))
    try:
        remove(args.apply) if args.remove else install(args.apply)
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        parser.exit(1, f'Error: {exc}\n')

if __name__ == '__main__':
    main()
