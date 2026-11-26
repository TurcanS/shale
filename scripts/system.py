"""What this machine needs for Shale and a usable Hyprland: packages (each with its reason), services, notes.

Only what the shell and Hyprland itself use is planned, with the graphics drivers and firmware this hardware needs to
run them (unless --no-drivers), and the apps the shell opens things in (unless --no-apps): a browser for links, a file
manager for folders, an image viewer for screenshots and a video player for recordings, each only when nothing installed
opens that kind of thing yet.
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
# What the shell hands to xdg-open, and the app added when nothing installed opens it: (a MIME type the shell opens, the
# categories an installed app needs to count as opening it, package, its .desktop file names, the MIME types it becomes
# the default for where none is set, why). An exact MIME type and a category both count: kitty's "Open in kitty" claims
# image/* and folders, and code editors claim folders too.
APPS = (
    ('x-scheme-handler/https', ('WebBrowser',), 'firefox', ('firefox.desktop',),
     ('x-scheme-handler/http', 'x-scheme-handler/https', 'text/html'), 'web links, web search and what changed in an update'),
    ('inode/directory', ('FileManager',), 'thunar', ('thunar.desktop',), ('inode/directory',),
     'folders: screenshots, recordings, wallpapers and files Find found'),
    ('image/png', ('Graphics', 'Viewer'), 'ristretto', ('org.xfce.ristretto.desktop', 'ristretto.desktop'),
     ('image/png', 'image/jpeg', 'image/webp'), 'opening screenshots'),
    ('video/mp4', ('Video', 'Player'), 'mpv', ('mpv.desktop', 'io.mpv.Mpv.desktop'),
     ('video/mp4', 'video/webm', 'video/x-matroska'), 'playing screen recordings'),
)
# What makes Thunar whole: the trash and removable drives (gvfs) and picture thumbnails (tumbler).
THUNAR_PARTS = (('gvfs', "Thunar's trash and USB drives"), ('tumbler', 'thumbnails of screenshots and wallpapers in Thunar'))
# File managers Super+E can open, by command.
FILE_MANAGERS = ('thunar', 'nautilus', 'dolphin', 'nemo', 'pcmanfm-qt', 'pcmanfm', 'caja')
# Where installed apps' .desktop files are, system-wide (the home ones are added per user, ahead of these).
APPLICATION_DIRS = (Path('/usr/local/share/applications'), Path('/usr/share/applications'),
                    Path('/var/lib/flatpak/exports/share/applications'))
EXAMPLE_CONFIG = Path('/usr/share/hypr/hyprland.lua')
# Graphics vendors by PCI id.
NVIDIA, AMD, INTEL = '0x10de', '0x1002', '0x8086'
# Arch's kernels. NVIDIA's open module comes built for the first two; the others build it with DKMS.
KERNELS = ('linux', 'linux-lts', 'linux-zen', 'linux-hardened')
NVIDIA_MODULES = {'linux': 'nvidia-open', 'linux-lts': 'nvidia-open-lts'}
# NVIDIA's own driver (not nouveau) with its open kernel module: NVIDIA's choice for Turing (GTX 16, RTX 20) and newer,
# device ids from 0x1e00, and the only one RTX 50 cards run on. Older cards need a legacy driver from the AUR.
OPEN_MODULE_FROM = 0x1e00
# Hand suspend and hibernation to the NVIDIA driver, so the desktop comes back from a sleep.
NVIDIA_SLEEP = ('nvidia-suspend', 'nvidia-hibernate', 'nvidia-resume')


def _read(path):
    try:
        return path.read_text().strip()
    except OSError:
        return ''


def gpus(sys=Path('/sys')):
    """Display controllers on the PCI bus: [(vendor, device id)], e.g. [('0x1002', 0x1900), ('0x10de', 0x2d98)]."""
    found = []
    for device in sorted((sys / 'bus/pci/devices').glob('*')):
        if _read(device / 'class').startswith('0x03'):
            try:
                found.append((_read(device / 'vendor'), int(_read(device / 'device'), 16)))
            except ValueError:
                continue
    return found


def hardware(sys=Path('/sys'), firmware=Path('/usr/lib/firmware')):
    """Facts about this machine read from sysfs, and which GPU firmware is on disk."""
    supplies = list((sys / 'class/power_supply').glob('*'))
    graphics = gpus(sys)
    return {
        # A system battery, not a wireless mouse or headset (those report scope "Device").
        'battery': any(_read(s / 'type') == 'Battery' and _read(s / 'scope') != 'Device' for s in supplies),
        'backlight': any((sys / 'class/backlight').glob('*')),
        'bluetooth': any((sys / 'class/bluetooth').glob('hci*')),
        'nvidia': any(vendor == NVIDIA for vendor, _ in graphics),
        'nvidia_driver': (sys / 'module/nvidia').exists(),
        'gpus': graphics,
        # Sound Open Firmware drives this audio chip; without its firmware the speakers and microphone stay silent.
        'sof': any((sys / 'module').glob('snd_sof*')),
        'firmware': {name for name in ('amdgpu', 'i915', 'xe') if (firmware / name).is_dir()},
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


def application_dirs(home):
    """Where .desktop files are, the user's first: theirs override the system's of the same name."""
    return [home / '.local/share/applications', home / '.local/share/flatpak/exports/share/applications', *APPLICATION_DIRS]


def desktop_entries(home, folders=None):
    """{desktop file id: (MIME types, categories)} for the installed apps. A file of the user's that hides one of the
    system's (Hidden=true) removes it."""
    found = {}
    for folder in application_dirs(home) if folders is None else folders:
        if not folder.is_dir():
            continue
        for path in sorted(folder.rglob('*.desktop')):
            ident = str(path.relative_to(folder)).replace('/', '-')
            if ident in found:
                continue
            try:
                # Only the [Desktop Entry] group: actions further down have keys of their own.
                entry = path.read_text(errors='replace').split('\n[', 1)[0]
            except OSError:
                continue
            values = dict(re.findall(r'^([A-Za-z]+)=(.*)$', entry, re.M))
            hidden = values.get('Hidden', '').strip() == 'true'
            found[ident] = (set() if hidden else {t for t in values.get('MimeType', '').split(';') if t},
                            set() if hidden else {c for c in values.get('Categories', '').split(';') if c})
    return found


def opens(entries, mime, categories):
    """Whether an installed app opens `mime` (named exactly, not by a wildcard) and is one of `categories`."""
    return any(mime in types and set(categories) & kinds for types, kinds in entries.values())


def desktop_file(names, home, folders=None):
    """The first of `names` (.desktop file names) that is installed, or None."""
    for name in names:
        for folder in application_dirs(home) if folders is None else folders:
            if (folder / name).is_file():
                return name
    return None


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


def graphics(facts, present, services):
    """(packages, boot units, notes, whether a kernel module is added) for this machine's GPUs: firmware and Vulkan for
    AMD and Intel graphics, and NVIDIA's driver unless one is installed already. `present` is the set of installed
    packages among KERNELS and nvidia-utils."""
    found = facts.get('gpus', [])
    vendors = {vendor for vendor, _ in found}
    packages, boot, notes = [], [], []
    # Firmware only when its files are missing (a minimal install without linux-firmware), whichever package has them.
    firmware = facts.get('firmware', {'amdgpu', 'i915', 'xe'})
    if AMD in vendors:
        if 'amdgpu' not in firmware:
            packages.append(('linux-firmware-amdgpu', 'firmware the AMD graphics needs'))
        packages.append(('vulkan-radeon', 'Vulkan apps and games on the AMD graphics'))
    if INTEL in vendors:
        if not firmware & {'i915', 'xe'}:
            packages.append(('linux-firmware-intel', 'firmware the Intel graphics needs'))
        packages.append(('vulkan-intel', 'Vulkan apps and games on the Intel graphics'))
    nvidia = [device for vendor, device in found if vendor == NVIDIA]
    if not nvidia:
        return packages, boot, notes, False
    module = False
    if 'nvidia-utils' in present or facts.get('nvidia_driver'):
        pass  # a driver is chosen already, perhaps a legacy one: it stays
    elif any(device < OPEN_MODULE_FROM for device in nvidia):
        notes.append('This NVIDIA GPU is older than the GTX 16 and RTX 20 series, so it needs a legacy driver from the AUR '
                     '(see https://wiki.archlinux.org/title/NVIDIA). Install it before starting Hyprland.')
        return packages, boot, notes, False
    else:
        kernels = [kernel for kernel in KERNELS if kernel in present]
        if not kernels:
            notes.append("NVIDIA graphics found, but none of Arch's kernel packages is installed, so its driver is not "
                         "added. Install nvidia-open-dkms with your kernel's headers before starting Hyprland.")
            return packages, boot, notes, False
        if all(kernel in NVIDIA_MODULES for kernel in kernels):
            packages += [(NVIDIA_MODULES[kernel], f"NVIDIA's own driver, for the {kernel} kernel") for kernel in kernels]
        else:
            packages.append(('nvidia-open-dkms', "NVIDIA's own driver, built for each kernel"))
            packages += [(kernel + '-headers', f'building the NVIDIA driver for {kernel}') for kernel in kernels]
        module = True
    if module or 'nvidia-utils' in present:
        boot += [unit for unit in NVIDIA_SLEEP if services(unit) != 'enabled']
    if vendors & {AMD, INTEL}:
        other = 'AMD' if AMD in vendors else 'Intel'
        packages.append(('nvidia-prime', f'prime-run <app> runs a game on the NVIDIA GPU; the desktop stays on the {other} one'))
    return packages, boot, notes, module


def plan(home, facts=None, absent=missing, services=service_state, which=shutil.which, environ=os.environ,
         network=network_units, connected=online, drivers=True, apps=True, entries=None):
    """{packages, services (enable now), boot (enable for next boot), config, notes, conflicts (installed packages
    pacman has to replace), reboot (a kernel module is added, so it loads from the next boot), defaults (the apps added
    here: their .desktop file names and the MIME types they open), fileManager (the command Super+E opens in a new
    config)} for this machine.

    `absent(names)` returns the packages not installed yet; only those are planned. Without `drivers`, graphics
    drivers and firmware are left out; without `apps`, the apps the shell opens things in. `entries` stands in for
    the installed apps' .desktop files (desktop_entries())."""
    facts = hardware() if facts is None else facts
    packages, units, boot, notes = list(CORE) + list(DESKTOP), [], [], []

    candidates = (list(WALLPAPER_DAEMONS) + list(POWER_PROVIDERS) + list(OTHER_POWER) + ['pulseaudio', 'pulseaudio-bluetooth']
                  + list(KERNELS) + ['nvidia-utils'])
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
    elif not any(which(name) for name in TERMINALS):
        packages.append(('kitty', 'a terminal: Shale runs terminal apps and its updates in one'))

    # The apps the shell opens links, folders, screenshots and recordings in, where nothing installed opens them yet.
    opening = []
    if apps:
        entries = desktop_entries(home) if entries is None else entries
        for mime, kinds, package, files, types, reason in APPS:
            if not opens(entries, mime, kinds):
                packages.append((package, reason))
                opening.append((package, files, types))
                if package == 'thunar':
                    packages += THUNAR_PARTS
    # What Super+E opens in a config copied from the example (which names Dolphin): an installed file manager, or
    # Thunar once it is added.
    file_manager = next((name for name in FILE_MANAGERS if which(name)), '')
    if not file_manager and any(package == 'thunar' for package, *_ in opening):
        file_manager = 'thunar'

    # A login screen only on a fresh setup: no Hyprland config yet, no display manager, not inside a desktop.
    # Someone who already starts Hyprland from a TTY keeps doing so.
    if config and not services('display-manager') and not (environ.get('WAYLAND_DISPLAY') or environ.get('DISPLAY')):
        packages.append(('sddm', 'login screen; choose Hyprland there'))
        boot.append('sddm')
    module = False
    if drivers:
        added, sleep, found, module = graphics(facts, present, services)
        packages += added
        boot += sleep
        notes += found
        if facts.get('sof'):
            packages.append(('sof-firmware', 'speakers and microphone (this audio chip needs it)'))
    elif facts['nvidia'] and not facts.get('nvidia_driver') and 'nvidia-utils' not in present:
        notes.append('NVIDIA graphics found. Install its driver before starting Hyprland (see https://wiki.hypr.land/Nvidia/); '
                     '--no-drivers leaves that to you.')

    needed = set(absent([name for name, _ in packages]))
    # pipewire-pulse conflicts with pulseaudio. pacman asks before replacing it, and pulseaudio-bluetooth (which
    # needs pulseaudio) would make it fail, so that one goes first.
    conflicts = ['pulseaudio'] if 'pipewire-pulse' in needed and 'pulseaudio' in present else []
    if conflicts:
        notes.append('PulseAudio is installed. pipewire-pulse replaces it (Shale\'s audio runs on PipeWire), so pacman asks '
                     'to remove pulseaudio; answer y.' + (' First remove pulseaudio-bluetooth: sudo pacman -R '
                     'pulseaudio-bluetooth' if 'pulseaudio-bluetooth' in present else ''))
    return {'packages': [(n, r) for n, r in packages if n in needed], 'services': units, 'boot': boot, 'config': config,
            'notes': notes, 'conflicts': conflicts, 'reboot': module,
            'defaults': [(files, types) for package, files, types in opening if package in needed], 'fileManager': file_manager}
