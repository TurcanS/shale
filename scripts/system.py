"""What this machine needs for Shale and a usable Hyprland: packages (each with its reason), services, notes.

Only what the shell and Hyprland itself use is planned. Drivers, browsers and other app choices stay with the user.
"""
import os
from pathlib import Path
import re
import shutil
import subprocess

# The shell and what it runs on. Everything else is added only when the hardware calls for it.
CORE = [
    ('quickshell', 'the shell itself'), ('hyprland', 'the compositor Shale runs on'),
    ('python', "Shale's helper"), ('python-dbus-next', 'Wi-Fi, Bluetooth pairing and power modes'),
    ('pipewire', 'audio'), ('wireplumber', 'audio'), ('pipewire-pulse', 'audio for apps and the visualizer'),
    ('wl-clipboard', 'copying'), ('cliphist', 'clipboard history'),
    ('hyprlock', 'lock fallback'), ('hypridle', 'idle dim, lock and screen off'),
    ('grim', 'screenshots'), ('slurp', 'choosing a region'), ('wf-recorder', 'screen recording'),
    ('hyprpicker', 'color picker'), ('xdg-utils', 'opening files and links'),
    ('adwaita-fonts', "Shale's typeface"), ('noto-fonts-emoji', 'emoji'), ('fd', 'file search'),
    ('xdg-terminal-exec', 'opening terminal apps'), ('qt6-imageformats', 'WebP wallpapers'),
]
# What a Hyprland session needs around the shell, whatever the hardware.
DESKTOP = [
    ('xdg-desktop-portal-hyprland', 'screen sharing and portals for apps'), ('xdg-desktop-portal-gtk', 'file pickers in apps'),
    ('hyprpolkitagent', 'password prompts from apps'), ('noto-fonts', 'text in apps'),
    ('playerctl', 'media keys in Hyprland\'s example config'),
]
WALLPAPER_DAEMONS = ('hyprpaper', 'awww', 'swww')
POWER_PROVIDERS = ('power-profiles-daemon', 'tuned-ppd')
# Power managers without the power-profiles API. They are kept; Shale's power modes then stay hidden.
OTHER_POWER = ('tlp', 'tuned', 'auto-cpufreq')
# Services that already run the network on Arch, including templated ones (netctl-auto@wlan0).
NETWORK_UNITS = re.compile(r'(NetworkManager|iwd|systemd-networkd|connman|dhcpcd(@.+)?|netctl(-auto|-ifplugd)?(@.+)?|wpa_supplicant@.+)\.service')
# Terminals that are also their package's name.
TERMINALS = ('kitty', 'foot', 'alacritty', 'wezterm', 'ghostty', 'konsole', 'gnome-terminal')
EXAMPLE_CONFIG = Path('/usr/share/hypr/hyprland.lua')


def _read(path):
    try:
        return path.read_text().strip()
    except OSError:
        return ''


def hardware(sys=Path('/sys')):
    """Facts about this machine read from sysfs."""
    supplies = list((sys / 'class/power_supply').glob('*'))
    return {
        # A system battery, not a wireless mouse or headset (those report scope "Device").
        'battery': any(_read(s / 'type') == 'Battery' and _read(s / 'scope') != 'Device' for s in supplies),
        'backlight': any((sys / 'class/backlight').glob('*')),
        'bluetooth': any((sys / 'class/bluetooth').glob('hci*')),
        'nvidia': any(_read(d / 'vendor') == '0x10de' and _read(d / 'class').startswith('0x03') for d in (sys / 'bus/pci/devices').glob('*')),
        'nvidia_driver': (sys / 'module/nvidia').exists(),
    }


def missing(packages, run=subprocess.run):
    """Packages pacman would still have to install (`pacman -T` prints the unsatisfied ones)."""
    if not packages:
        return []
    result = run(['pacman', '-T', *packages], capture_output=True, text=True)
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def service_state(name, run=subprocess.run):
    """'enabled', 'active' or '' for a system unit."""
    for state in ('is-enabled', 'is-active'):
        if run(['systemctl', '--quiet', state, name + '.service'], capture_output=True).returncode == 0:
            return 'enabled' if state == 'is-enabled' else 'active'
    return ''


def configured_terminal(text):
    """The terminal a hyprland.lua opens (`local terminal = "kitty"`), or ''."""
    match = re.search(r'^\s*local\s+terminal\s*=\s*["\']([^"\'\s]+)', text, re.M)
    return match[1] if match else ''


def network_units(run=subprocess.run, units=Path('/etc/systemd/system')):
    """Services that manage the network, running or enabled for boot, e.g. ['iwd', 'netctl-auto@wlan0'].

    Enabled ones are read from the .wants links, which works in a chroot where systemd isn't running."""
    names = []
    try:
        result = run(['systemctl', 'list-units', '--type=service', '--state=active', '--plain', '--no-legend'],
                     capture_output=True, text=True)
    except OSError:
        result = None
    if result and result.returncode == 0:
        names += [line.split()[0] for line in result.stdout.splitlines() if line.split()]
    names += sorted(link.name for link in units.glob('*.wants/*.service'))
    found = [name.removesuffix('.service') for name in names if NETWORK_UNITS.fullmatch(name)]
    return list(dict.fromkeys(found))


def online(route=Path('/proc/net/route'), route6=Path('/proc/net/ipv6_route'), booted=Path('/run/systemd/system')):
    """Whether there is a default route (IPv4 or IPv6), i.e. something already brought the network up.

    Not from a chroot (systemd isn't running there): the route it sees belongs to the host, such as the live ISO."""
    if not booted.is_dir():
        return False
    try:
        rows = route.read_text().splitlines()[1:]
    except OSError:
        rows = []
    if any(len(fields) > 1 and fields[1] == '00000000' for fields in map(str.split, rows)):
        return True
    try:
        rows = route6.read_text().splitlines()
    except OSError:
        return False
    # ::/0 that is up (flag 0x1) and not a reject route (0x200), which the kernel keeps on lo.
    return any(len(fields) > 9 and fields[0] == '0' * 32 and fields[1] == '00' and fields[9] != 'lo'
               and int(fields[8], 16) & 0x201 == 0x1 for fields in map(str.split, rows))


def plan(home, facts=None, absent=missing, services=service_state, which=shutil.which, environ=os.environ,
         network=network_units, connected=online):
    """{packages, services (enable now), boot (enable for next boot), config, notes, conflicts (installed packages
    pacman has to replace)} for this machine.

    `absent(names)` returns the packages not installed yet; only those are planned."""
    facts = hardware() if facts is None else facts
    packages, units, boot, notes = list(CORE) + list(DESKTOP), [], [], []

    candidates = list(WALLPAPER_DAEMONS) + list(POWER_PROVIDERS) + list(OTHER_POWER) + ['pulseaudio', 'pulseaudio-bluetooth']
    present = set(candidates) - set(absent(candidates))
    if not set(WALLPAPER_DAEMONS) & present:
        packages.append(('hyprpaper', 'drawing the wallpaper'))

    if facts['battery']:
        packages.append(('upower', 'battery level (this is a laptop)'))
        provider, others = set(POWER_PROVIDERS) & present, [name for name in OTHER_POWER if name in present]
        if not provider and others:
            notes.append(f"{others[0]} manages power here, so power-profiles-daemon is not added and Shale's power modes stay "
                         'hidden.' + (' Add tuned-ppd to use them with TuneD.' if others[0] == 'tuned' else ''))
        elif not provider:
            packages.append(('power-profiles-daemon', 'power modes'))
            units.append('power-profiles-daemon')
    if facts['backlight']:
        packages.append(('brightnessctl', 'screen brightness'))
    if facts['bluetooth']:
        packages += [('bluez', 'Bluetooth (an adapter was found)'), ('bluez-utils', 'Bluetooth')]
        if services('bluetooth') != 'enabled':
            units.append('bluetooth')

    # Never swap out a working network setup; Shale just hides its Wi-Fi controls.
    running = network()
    if 'NetworkManager' in running:
        pass
    elif running:
        notes.append(f'{running[0]} manages your network. Shale controls Wi-Fi through NetworkManager, so its Wi-Fi '
                     'controls stay hidden; your connection is not touched.')
    elif connected():
        notes.append('Your network is up through a setup Shale does not recognise, so NetworkManager is not added; '
                     "Shale's Wi-Fi controls stay hidden and your connection is not touched.")
    else:
        packages.append(('networkmanager', 'network and Wi-Fi controls'))
        units.append('NetworkManager')

    lua = home / '.config/hypr/hyprland.lua'
    config = not lua.exists()
    if config and (home / '.config/hypr/hyprland.conf').exists():
        notes.append('Your Hyprland config is hyprland.conf; Shale needs the Lua config. A new hyprland.lua takes '
                     'precedence once it exists, so port your settings to it first. See "Requirements" in the README.')
        config = False
    # The terminal Super+Q opens: the one your config names, or the example's (kitty) for a new config.
    try:
        terminal = configured_terminal((EXAMPLE_CONFIG if config else lua).read_text())
    except OSError:
        terminal = 'kitty' if config else ''
    if terminal in TERMINALS and not which(terminal):
        packages.append((terminal, 'the terminal your Hyprland config opens with Super+Q'))

    # A login screen only on a fresh setup: no Hyprland config yet, no display manager, not inside a desktop.
    # Someone who already starts Hyprland from a TTY keeps doing so.
    if config and not services('display-manager') and not (environ.get('WAYLAND_DISPLAY') or environ.get('DISPLAY')):
        packages.append(('sddm', 'login screen; choose Hyprland there'))
        boot.append('sddm')
    if facts['nvidia'] and not facts.get('nvidia_driver'):
        notes.append('NVIDIA graphics found. Install its driver before starting Hyprland (see https://wiki.hypr.land/Nvidia/); '
                     'Shale does not choose drivers for you.')

    needed = set(absent([name for name, _ in packages]))
    # pipewire-pulse conflicts with pulseaudio. pacman asks before replacing it, and pulseaudio-bluetooth (which
    # needs pulseaudio) would make it fail, so that one goes first.
    conflicts = ['pulseaudio'] if 'pipewire-pulse' in needed and 'pulseaudio' in present else []
    if conflicts:
        notes.append('PulseAudio is installed. pipewire-pulse replaces it (Shale\'s audio runs on PipeWire), so pacman asks '
                     'to remove pulseaudio; answer y.' + (' First remove pulseaudio-bluetooth: sudo pacman -R '
                     'pulseaudio-bluetooth' if 'pulseaudio-bluetooth' in present else ''))
    return {'packages': [(n, r) for n, r in packages if n in needed], 'services': units, 'boot': boot, 'config': config,
            'notes': notes, 'conflicts': conflicts}
