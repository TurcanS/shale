#!/usr/bin/env python3
"""Preview, install, or remove Shale's Max performance mode for Lenovo laptops (--apply asks for your password through sudo)."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile

SCRIPT = Path(__file__).resolve()
SOURCE = SCRIPT.parents[1] / 'integration/power-max'
PYTHON, SYSTEMCTL = '/usr/bin/python3', '/usr/bin/systemctl'
ROOT_TOOLS = ('/usr/bin/sudo', '/usr/bin/sudo-rs', '/usr/bin/doas', '/usr/bin/pkexec')
ATTRIBUTES = Path('/sys/class/firmware-attributes/lenovo-wmi-other-0/attributes')
# Root runs a root-owned copy of the helper, never the repository's (user-writable) file.
FILES = (
    ('shale-power-max', Path('/usr/local/libexec/shale-power-max'), 0o755),
    ('shale-power-max.service', Path('/etc/systemd/system/shale-power-max.service'), 0o644),
    ('50-shale-power-max.rules', Path('/etc/polkit-1/rules.d/50-shale-power-max.rules'), 0o644),
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
    if not ATTRIBUTES.is_dir():
        raise ValueError(f'This needs a Lenovo laptop with the lenovo-wmi-other driver ({ATTRIBUTES} is missing).')
    for name, target, _ in FILES:
        print(('UPDATE ' if target.exists() else 'CREATE ') + str(target))
    print('RELOAD systemd')
    if not apply:
        print('\nPreview only. Re-run with --apply to install; it asks for your password through sudo.')
        return
    for name, target, mode in FILES:
        atomic_copy(SOURCE / name, target, mode)
    subprocess.run([SYSTEMCTL, 'daemon-reload'], check=True)
    print(f'\nInstalled. Pick Max performance in Control → Power. Remove: sudo python3 {SCRIPT} --remove --apply')

def remove(apply):
    for _, target, _ in FILES:
        print(f'REMOVE {target}')
    print('RELOAD systemd')
    if not apply:
        print('\nPreview only. Re-run with --apply to remove; it asks for your password through sudo.')
        return
    for _, target, _ in FILES:
        target.unlink(missing_ok=True)
    subprocess.run([SYSTEMCTL, 'daemon-reload'], check=True)
    print('\nRemoved. Choose any power mode to put the firmware limits back.')

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
