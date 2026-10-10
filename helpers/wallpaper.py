"""Local wallpaper catalog and the wallpaper daemons Shale drives: hyprpaper 0.8 IPC, or awww/swww.

No image downloads happen here."""
import asyncio
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

# Daemons Shale can drive, in the order it starts one when none is running: (process, client, daemon command).
DAEMONS = (("hyprpaper", "hyprpaper", ["hyprpaper"]), ("awww-daemon", "awww", ["awww-daemon"]), ("swww-daemon", "swww", ["swww-daemon"]))
# Wallpaper tools Shale can't drive; while one runs, Shale doesn't start a competing daemon.
FOREIGN = ("swaybg", "wpaperd", "mpvpaper", "hyprlax")
QUERY_LINE = re.compile(r"^:?\s*([^:\s]+): .*?currently displaying: image: (.+)$")

EXTENSIONS = {'.jpg', '.jpeg', '.png', '.webp', '.bmp'}
CATALOG_LIMIT = 500

def catalog(folder):
    """Images in the folder and its subfolders; `limited` says the listing stopped at CATALOG_LIMIT entries."""
    directory = Path(folder).expanduser().resolve()
    if not directory.is_dir():
        return {'directory': str(directory), 'entries': [], 'limited': False}
    entries = []
    for base, dirs, files in os.walk(directory, followlinks=False):
        dirs[:] = sorted(d for d in dirs if not d.startswith('.'))
        for name in sorted(files):
            path = Path(base) / name
            if path.suffix.lower() not in EXTENSIONS or not path.is_file():
                continue
            resolved = path.resolve()
            entries.append({'path': str(resolved), 'url': resolved.as_uri(), 'name': path.stem.replace('_', ' ').replace('-', ' '), 'file': name})
            if len(entries) >= CATALOG_LIMIT:
                return {'directory': str(directory), 'entries': entries, 'limited': True}
    return {'directory': str(directory), 'entries': entries, 'limited': False}

def running(proc=Path('/proc')):
    """Names (comm) of this user's running processes."""
    names, uid = set(), os.getuid()
    for entry in proc.glob('[0-9]*'):
        try:
            if entry.stat().st_uid == uid:
                names.add((entry / 'comm').read_text().strip())
        except OSError:
            continue
    return names

def current(proc=Path('/proc')):
    """The running daemon Shale drives ("hyprpaper", "awww", "swww"), "foreign" for another tool, or None."""
    names = running(proc)
    for process, client, _ in DAEMONS:
        if process in names:
            return client
    return 'foreign' if names & set(FOREIGN) else None

def installed(which=shutil.which):
    """Whether a daemon Shale can start is installed."""
    return any(which(command[0]) and which(client) for _, client, command in DAEMONS)

async def ensure(proc=Path('/proc'), which=shutil.which, spawn=subprocess.Popen, sleep=asyncio.sleep):
    """The daemon to use, starting the first installed one when nothing draws the wallpaper yet."""
    daemon = current(proc)
    if daemon:
        return daemon
    for _, client, command in DAEMONS:
        if which(command[0]) and which(client):
            # Its own session: the wallpaper must outlive helper restarts.
            spawn(command, start_new_session=True, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            for _ in range(30):
                await sleep(0.1)
                if current(proc) == client:
                    break
            await sleep(0.3)  # the IPC socket appears just after the process
            return client
    return None

def unavailable(daemon, error):
    if daemon == 'foreign':
        return error('unavailable', 'Another wallpaper tool is running. Shale sets wallpapers with hyprpaper or awww.')
    return error('unavailable', 'Install hyprpaper or awww to set wallpapers.')

async def active(run, daemon='hyprpaper'):
    if daemon in ('awww', 'swww'):
        output = (await run(daemon, 'query')).decode(errors='replace')
        return {match[1]: match[2].strip() for match in map(QUERY_LINE.match, output.splitlines()) if match}
    output = (await run('hyprctl', 'hyprpaper', 'listactive')).decode()
    return dict(line.split(': ', 1) for line in output.splitlines() if ': ' in line)

async def apply(run, path, monitor, error, daemon='hyprpaper'):
    image = Path(path).expanduser().resolve()
    if not image.is_file() or image.suffix.lower() not in EXTENSIONS:
        raise error('invalid', 'Choose an existing JPG, PNG, WebP, or BMP image.')
    if any(c in str(image) + monitor for c in ('\n', '\r')) or (daemon == 'hyprpaper' and ',' in str(image) + monitor):
        raise error('invalid', 'Hyprpaper cannot accept commas or line breaks in wallpaper paths.')
    monitors = json.loads((await run('hyprctl', 'monitors', '-j')).decode())
    if monitor not in [m['name'] for m in monitors]:
        raise error('unavailable', 'The selected monitor is no longer connected.')
    if daemon in ('awww', 'swww'):
        # Shale crossfades itself, so the daemon switches instantly underneath.
        await run(daemon, 'img', '--outputs', monitor, '--transition-type', 'none', str(image))
    else:
        response = (await run('hyprctl', 'hyprpaper', 'wallpaper', f'{monitor},{image},cover')).decode().strip()
        if response and response.lower() != 'ok':
            raise error('failed', 'Hyprpaper could not set this image. Check that it is a supported image.')
    reported = (await active(run, daemon)).get(monitor, '')
    if not reported or Path(reported).expanduser().resolve() != image:
        raise error('failed', 'The wallpaper daemon did not confirm the selected wallpaper.')
    return {'path': str(image), 'url': image.as_uri(), 'monitor': monitor}
