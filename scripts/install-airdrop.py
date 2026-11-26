#!/usr/bin/env python3
"""Preview or install AirDrop for Linux (the `airdrop` command Shale's AirDrop drives) on this laptop: build tools,
the libraries it runs on, the command with its root helper, OWL and polkit action (built as an Arch package), the
polkit rule that lets you start it without a password, Bluetooth, the regulatory domain, and the patched driver a
MediaTek MT7921/MT7922 or Realtek RTL8852BE card needs. --apply asks for your password through sudo.

Without --source it builds Samara (https://github.com/TurcanS/samara), kept in ~/.local/src/samara.
"""
import argparse
import grp
import json
import os
from pathlib import Path
import pwd
import re
import shutil
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
import system  # noqa: E402  (package and service checks shared with the installer)

UPSTREAM = 'https://github.com/TurcanS/samara.git'
CHECKOUT = Path.home() / '.local/src/samara'
# What runs as root is named by absolute path: pkexec starts it with a clean environment.
PACMAN, SYSTEMCTL, GROUPADD, GPASSWD, INSTALL, IW = (
    '/usr/bin/pacman', '/usr/bin/systemctl', '/usr/bin/groupadd', '/usr/bin/gpasswd', '/usr/bin/install', '/usr/bin/iw')
# sudo, what people install instead of it, then pkexec: the order install.sh and install.py use.
ROOT_TOOLS = ('/usr/bin/sudo', '/usr/bin/sudo-rs', '/usr/bin/doas', '/usr/bin/pkexec')
# Members of this group start AirDrop without a password (the rule shipped with the source, installed here).
GROUP = 'airdrop'
RULE_SOURCE = 'packaging/50-airdrop-background.rules.example'
RULE = Path('/etc/polkit-1/rules.d/50-airdrop-background.rules')
# The regulatory domain the kernel starts with, so channel 149 may transmit after a reboot too.
REGDOM = Path('/etc/modprobe.d/shale-airdrop-regdom.conf')
# Building it: makepkg, the source and OWL from git, OWL with CMake, the command with Rust.
BUILD = [('base-devel', 'building the package (makepkg)'), ('git', 'fetching the source and OWL'),
         ('cmake', 'building OWL, the AWDL daemon')]
# What the package depends on: the helper runs iw, ip, nmcli and modinfo and talks to NetworkManager and BlueZ;
# OWL needs libpcap, libev and libnl.
RUNTIME = [('openssl', 'encrypted transfers'), ('zlib', 'compressed transfers'),
           ('polkit', 'permission to use the Wi-Fi card'), ('iw', 'switching the Wi-Fi card into AirDrop modes'),
           # Only optional for Arch's kernel, but without it every country is ignored and 5 GHz never transmits.
           ('wireless-regdb', 'the regulatory database, so your country\'s channels can be used'),
           ('iproute2', 'the AirDrop network interface'), ('networkmanager', 'pausing Wi-Fi and giving it back'),
           ('bluez', 'Bluetooth LE: waking iPhones, hearing them open AirDrop'), ('kmod', 'driver checks'),
           ('libpcap', 'OWL'), ('libev', 'OWL'), ('libnl', 'OWL')]
# Cards with a driver patch, by kernel driver: name, build script, load script (load / install-boot), patch, boot unit,
# what the first build downloads.
DRIVERS = {
    'mt7921e': ('MediaTek MT7921/MT7922', 'scripts/mt7921-build.sh', 'scripts/mt7921-ratefix.sh',
                'driver/mt7921-awdl.diff', 'airdrop-mt7921-ratefix.service', 'about 300 MB once'),
    'rtw89_8852be': ('Realtek RTL8852BE', 'scripts/rtw89-build.sh', 'scripts/rtw89-load.sh',
                     'driver/rtw89-awdl.diff', 'airdrop-rtw89.service', 'the rtw89 source once'),
}
COUNTRY = re.compile(r'[A-Z]{2}')


def _read(path):
    try:
        return path.read_text().strip()
    except OSError:
        return ''


def run_text(command, run=subprocess.run):
    """A command's output, or '' when it is missing or fails."""
    try:
        result = run(command, capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired):
        return ''
    return result.stdout if result.returncode == 0 else ''


def wifi_cards(sys_root=Path('/sys'), run=subprocess.run):
    """Wi-Fi interfaces: [{iface, phy, driver, monitor, active}]. monitor/active are None while iw is missing."""
    cards = []
    for net in sorted((sys_root / 'class/net').glob('*')):
        if not (net / 'phy80211').exists():
            continue
        phy = _read(net / 'phy80211/name')
        driver = (net / 'device/driver').resolve().name if (net / 'device/driver').exists() else ''
        info = run_text(['iw', 'phy', phy, 'info'], run) if shutil.which('iw') else ''
        cards.append({'iface': net.name, 'phy': phy, 'driver': driver,
                      'monitor': ('* monitor' in info) if info else None,
                      'active': ('active monitor' in info) if info else None})
    return cards


def country(run=subprocess.run):
    """The regulatory domain the kernel uses ('00' is none, under which 5 GHz never transmits), or '' unknown."""
    match = re.search(r'country (\w\w):', run_text(['iw', 'reg', 'get'], run))
    return match[1] if match else ''


def kernel_headers(run=subprocess.run, release=None):
    """(package with the running kernel's headers, whether they are installed). ('', False) for a kernel pacman doesn't
    know, e.g. one built by hand."""
    release = release or os.uname().release
    owner = run_text(['pacman', '-Qqo', f'/usr/lib/modules/{release}/vmlinuz'], run).strip()
    return (owner + '-headers' if owner else ''), Path(f'/usr/lib/modules/{release}/build').is_dir()


def clang_kernel():
    """Kernels built with clang (CachyOS's, for one) build their modules with it too."""
    return 'clang' in _read(Path('/proc/version'))


def source_tree(path):
    """A source tree of AirDrop for Linux: it has the Arch package and the polkit rule."""
    return (path / 'packaging/PKGBUILD').is_file() and (path / RULE_SOURCE).is_file()


def plan(source, user, args, absent=system.missing, services=system.service_state, network=system.network_units,
         facts=None, run=subprocess.run):
    """{packages, steps, notes, blockers, driver (iface or '')} for this laptop. Steps are (label, kind), run in order."""
    cards = wifi_cards(run=run) if facts is None else facts['cards']
    bluetooth = any(Path('/sys/class/bluetooth').glob('hci*')) if facts is None else facts['bluetooth']
    packages, steps, notes, blockers = list(BUILD) + list(RUNTIME), [], [], []

    if not cards:
        blockers.append('No Wi-Fi card was found. AirDrop runs over Wi-Fi (Apple\'s AWDL), so it needs one.')
    usable = [card for card in cards if card['monitor'] is not False]
    if cards and not usable:
        blockers.append('No Wi-Fi card here has monitor mode (' + ', '.join(f"{c['iface']}: {c['driver'] or 'unknown driver'}"
                        for c in cards) + '). AirDrop needs monitor mode and frame injection. A USB card with both may '
                        'work; the MediaTek MT7921 and Realtek RTL8852BE are tested.')
    for card in usable:
        if card['monitor'] is None:
            notes.append(f"Whether {card['iface']} has monitor mode is checked once iw is installed (airdrop doctor).")
        elif not card['active'] and not card['driver'].startswith('rtw89_'):
            notes.append(f"{card['iface']} has no active monitor mode, so it may not answer an iPhone's frames. Sending "
                         'can work; receiving often doesn\'t. The MediaTek MT7921 and Realtek RTL8852BE are tested.')
    if not shutil.which('cargo'):
        packages.append(('rust', 'building the airdrop command'))

    if bluetooth:
        packages.append(('bluez-utils', 'Bluetooth from the terminal'))
        if services('bluetooth') != 'enabled':
            steps.append(('Enable Bluetooth (bluetooth.service)', 'bluetooth'))
    else:
        notes.append('No Bluetooth adapter was found. Sending can\'t wake an iPhone\'s AirDrop and Background can\'t '
                     'hear one, so only Visible works, with the iPhone already showing its AirDrop list.')
    running = network()
    if 'NetworkManager' not in running:
        notes.append(f"{running[0] if running else 'Something other than NetworkManager'} runs your network. AirDrop "
                     'pauses Wi-Fi and gives it back through NetworkManager, so it can\'t start until NetworkManager '
                     'manages Wi-Fi. Your network is not touched.')

    patched = next((card for card in usable if card['driver'] in DRIVERS), None)
    driver = patched['iface'] if patched else ''
    kind = patched['driver'] if patched else ''
    name, _, load, _, unit, download = DRIVERS.get(kind, ('',) * 6)
    if driver and not args.no_driver:
        headers, present = kernel_headers(run)
        if not present and headers:
            packages.append((headers, 'building the patched Wi-Fi driver for this kernel'))
        elif not present:
            blockers.append('This kernel has no headers installed and pacman doesn\'t know its package. Install its '
                            'headers, or pass --no-driver.')
        if clang_kernel():
            packages += [('clang', 'this kernel builds its modules with clang'), ('llvm', 'the same'), ('lld', 'the same')]

    steps.append((f'Get the source: {source}' + (' (clone or update)' if source == CHECKOUT else ''), 'source'))
    steps.append(('Build and install the airdrop package: the command, its root helper, OWL, the polkit action '
                  '(makepkg -si; pacman asks before installing)', 'package'))
    member = user in _members(GROUP)
    steps.append((f'Polkit: add the {GROUP} group' + ('' if _group(GROUP) else ' (new)') + f', with {user} in it'
                  + (' (already)' if member else ''), 'group'))
    rule_text = _read(source / RULE_SOURCE) if source_tree(source) else None
    if rule_text is None or _read(RULE) != rule_text:
        steps.append((f'Polkit: install {RULE} (members of {GROUP} start AirDrop without a password)', 'rule'))
    if args.country:
        steps.append((f'Regulatory domain {args.country}: now (iw reg set) and at boot ({REGDOM})', 'country'))
    else:
        current = country(run)
        if current == '00':
            blockers.append('No regulatory domain is set (iw reg get says country 00), so the kernel silently drops '
                            'every frame on channel 149, AirDrop\'s. Pass your country: --country DE (two letters).')
        elif not current:
            notes.append('The regulatory domain is checked once iw is installed. If airdrop doctor says channel 149 is '
                         'No-IR, run this again with --country and your two-letter country code.')
    if driver and not args.no_driver:
        steps.append((f'Build the patched {name} driver ({kind}) for this kernel (downloads {download}) and load it '
                      'until the next reboot; Wi-Fi drops for a few seconds', 'driver'))
        if args.driver_at_boot:
            steps.append((f'Load the patched driver at every boot ({unit})', 'boot'))
        else:
            notes.append(f'The patched driver lasts until the next reboot. Load it again with {source}/{load} '
                         'load, or run this with --driver-at-boot. After a kernel update, run this '
                         'again to rebuild it.')
    steps.append(('Check: airdrop doctor, and that the command speaks Shale\'s --json interface', 'check'))
    return {'packages': packages, 'steps': steps, 'notes': notes, 'blockers': blockers, 'driver': driver,
            'driver_kind': kind}


def _group(name):
    try:
        return grp.getgrnam(name)
    except KeyError:
        return None


def _members(name):
    group = _group(name)
    return group.gr_mem if group else []


def privileged():
    """The first of ROOT_TOOLS that is installed."""
    tool = next((tool for tool in ROOT_TOOLS if os.path.exists(tool)), None)
    if tool is None:
        raise ValueError('No sudo, doas or pkexec is installed. As root: pacman -S sudo, then add yourself to the wheel group.')
    return tool


def step(command, cwd=None, env=None):
    print('$ ' + ' '.join(command), flush=True)
    subprocess.run(command, check=True, cwd=cwd, env=env)


def get_source(source):
    if source != CHECKOUT:
        return
    if (source / '.git').is_dir():
        step(['git', '-C', str(source), 'pull', '--ff-only'])
    else:
        source.parent.mkdir(parents=True, exist_ok=True)
        step(['git', 'clone', '--depth', '1', UPSTREAM, str(source)])
    if not source_tree(source):
        raise ValueError(f'{source} is not an AirDrop for Linux source tree (packaging/PKGBUILD is missing)')


def speaks_json(command):
    """Whether `airdrop --json config show` answers in JSON, which Shale needs to show AirDrop at all."""
    try:
        result = subprocess.run([command, '--json', 'config', 'show'], capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired):
        return False
    for line in result.stdout.splitlines():
        try:
            json.loads(line)
            return True
        except ValueError:
            continue
    return False


def check(source):
    """Which airdrop Shale will find, and what doctor says."""
    found = shutil.which('airdrop') or ''
    local = Path.home() / '.local/bin/airdrop'
    if not found and local.exists():
        found = str(local)
    if found and Path(found).resolve() != Path('/usr/bin/airdrop'):
        print(f'\nNote: Shale uses {found}, which comes before /usr/bin/airdrop. Move it aside to use the one just '
              f'installed: mv {found} {found}.old')
    command = found or '/usr/bin/airdrop'
    print('\n$ airdrop doctor', flush=True)
    subprocess.run([command, 'doctor'])
    if not speaks_json(command):
        print(f'\nWarning: {command} doesn\'t speak --json, so Shale keeps AirDrop hidden (the terminal command works). '
              'Build a source that has it: --source DIR.' + (f' The one from {UPSTREAM} doesn\'t yet.' if source == CHECKOUT else ''))


def apply(source, user, args, result):
    root = privileged()
    if root != ROOT_TOOLS[0]:
        print(f'sudo is not installed, so this uses {os.path.basename(root)}.')
    needed = [name for name, _ in result['packages']]
    if needed:
        step([root, PACMAN, '-S', '--needed', *needed])
    for label, kind in result['steps']:
        print(f'\n== {label}', flush=True)
        if kind == 'bluetooth':
            step([root, SYSTEMCTL, 'enable', '--now', 'bluetooth.service'])
        elif kind == 'source':
            get_source(source)
        elif kind == 'package':
            step(['makepkg', '-sif'], cwd=source / 'packaging')
        elif kind == 'group':
            if not _group(GROUP):
                step([root, GROUPADD, '-r', GROUP])
            if user not in _members(GROUP):
                step([root, GPASSWD, '-a', user, GROUP])
        elif kind == 'rule':
            step([root, INSTALL, '-Dm644', '-o', 'root', '-g', 'root', str(source / RULE_SOURCE), str(RULE)])
        elif kind == 'country':
            text = f'# AirDrop needs channel 149 to transmit, which only a real regulatory domain allows.\n' \
                   f'options cfg80211 ieee80211_regdom={args.country}\n'
            step([root, '/usr/bin/sh', '-c', f'umask 022; printf %s "$1" > {REGDOM}', 'sh', text])
            # The kernel tried to load the database at boot and doesn't try again by itself: a country set before
            # wireless-regdb was installed is ignored until it reloads.
            step([root, IW, 'reg', 'reload'])
            step([root, IW, 'reg', 'set', args.country])
            got = ''
            for _ in range(10):  # the kernel applies it a moment later
                got = country()
                if got == args.country:
                    break
                time.sleep(0.5)
            if got != args.country:
                print(f'Warning: the kernel still uses country {got or "unknown"}. It takes {args.country} from the next '
                      f'boot ({REGDOM}); reboot, then check with: iw reg get')
        elif kind == 'driver':
            _, build, load, patch, _, _ = DRIVERS[result['driver_kind']]
            missing = [name for name in (build, load, patch) if not (source / name).is_file()]
            if missing:
                print(f'Skipped: {source} has no {", ".join(missing)}. Build from Samara\'s source for the driver patch.')
                continue
            step([str(source / build)])
            step([str(source / load), 'load'], env=dict(os.environ, IFACE=result['driver']))
        elif kind == 'boot':
            load = DRIVERS[result['driver_kind']][2]
            if (source / load).is_file():
                step([str(source / load), 'install-boot'], env=dict(os.environ, IFACE=result['driver']))
        elif kind == 'check':
            check(source)
    print('\nInstalled. Restart the shell (shale restart) so it finds the command, then open Settings → AirDrop.')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--apply', action='store_true', help='install (without it, only show what would be done)')
    parser.add_argument('--source', type=Path, help=f'an AirDrop for Linux source tree to build (default: {CHECKOUT})')
    parser.add_argument('--country', type=str.upper, help='your two-letter country code, for the regulatory domain')
    parser.add_argument('--no-driver', action='store_true', help='skip the patched Wi-Fi driver (MediaTek MT7921, Realtek RTL8852BE)')
    parser.add_argument('--driver-at-boot', action='store_true',
                        help='load the patched driver at every boot (a root service that runs the source tree\'s script)')
    parser.add_argument('--force', action='store_true', help='install even when this laptop looks unable to run AirDrop')
    args = parser.parse_args()
    if os.geteuid() == 0:
        parser.exit(1, 'Error: run this as your normal user, not root. It asks for your password when it needs it.\n')
    if not shutil.which('pacman'):
        parser.exit(1, 'Error: this supports Arch Linux (pacman was not found).\n')
    if args.country and (not COUNTRY.fullmatch(args.country) or args.country == '00'):
        parser.exit(1, f'Error: --country takes a two-letter country code such as DE or US, not {args.country}.\n')
    source = args.source.expanduser().resolve() if args.source else CHECKOUT
    if args.source and not source_tree(source):
        parser.exit(1, f'Error: {source} is not an AirDrop for Linux source tree (no packaging/PKGBUILD).\n')
    user = pwd.getpwuid(os.getuid()).pw_name

    result = plan(source, user, args)
    needed = set(system.missing([name for name, _ in result['packages']]))
    result['packages'] = [(name, why) for name, why in result['packages'] if name in needed]
    if result['packages']:
        print('Packages:')
        for name, why in result['packages']:
            print(f'  {name:<16} {why}')
    print('\nSteps:')
    for number, (label, _) in enumerate(result['steps'], 1):
        print(f'  {number}. {label}')
    for note in result['notes']:
        print('\nNote: ' + note)
    for blocker in result['blockers']:
        print('\nCan\'t run AirDrop yet: ' + blocker)
    if not args.apply:
        print('\nPreview only. Re-run with --apply to install; it asks for your password through sudo.')
        return
    if result['blockers'] and not args.force:
        parser.exit(1, '\nNothing was installed. Fix the above, or pass --force to install anyway.\n')
    try:
        apply(source, user, args, result)
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        parser.exit(1, f'Error: {exc}\n')


if __name__ == '__main__':
    main()
