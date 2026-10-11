"""Album art as a local file. Quickshell's colour quantizer only reads files, while players hand out
https:// covers (Spotify) or whole images in data: URLs (browsers)."""
import base64
import binascii
import hashlib
import os
from pathlib import Path
import tempfile
from urllib.parse import unquote, unquote_to_bytes, urlsplit
from urllib.request import Request, urlopen

MAX_BYTES = 5 * 1024 * 1024
KEEP = 20


def _fetch(url):
    request = Request(url, headers={'User-Agent': 'ShaleShell/1.0', 'Accept': 'image/*', 'Accept-Encoding': 'identity'})
    with urlopen(request, timeout=5) as response:
        if not response.headers.get_content_type().startswith('image/'):
            raise ValueError('The cover is not an image.')
        return response.read(MAX_BYTES + 1)


def _decode(url):
    header, comma, payload = url[len('data:'):].partition(',')
    if not comma or not header.lower().startswith('image/'):
        raise ValueError('The cover is not an image.')
    if len(payload) > MAX_BYTES * 4 // 3 + 4:
        raise ValueError('The cover is too large.')
    if header.lower().endswith(';base64'):
        try:
            return base64.b64decode(unquote(payload), validate=True)
        except (binascii.Error, ValueError):
            raise ValueError('The cover could not be decoded.') from None
    return unquote_to_bytes(payload)


def local(url, folder, fetch=None, keep=KEEP):
    """The path of a file holding the cover at `url`, downloading or decoding it into `folder` when needed."""
    scheme = urlsplit(url).scheme.lower()
    if scheme == 'file':
        path = unquote(urlsplit(url).path)
        if not Path(path).is_file():
            raise ValueError('The cover file is missing.')
        return path
    if scheme not in ('http', 'https', 'data'):
        raise ValueError('Unsupported cover address.')
    folder = Path(folder)
    target = folder / hashlib.sha1(url.encode()).hexdigest()
    if target.is_file():
        os.utime(target)
        return str(target)
    data = _decode(url) if scheme == 'data' else (fetch or _fetch)(url)
    if not data or len(data) > MAX_BYTES:
        raise ValueError('The cover is too large.' if data else 'The cover is empty.')
    folder.mkdir(parents=True, exist_ok=True, mode=0o700)
    handle, temporary = tempfile.mkstemp(dir=folder, prefix='.art-')
    try:
        with os.fdopen(handle, 'wb') as file:
            file.write(data)
        os.replace(temporary, target)
    except BaseException:
        Path(temporary).unlink(missing_ok=True)
        raise
    # Only the newest covers are kept.
    covers = sorted((p for p in folder.iterdir() if not p.name.startswith('.')), key=lambda p: p.stat().st_mtime, reverse=True)
    for old in covers[keep:]:
        old.unlink(missing_ok=True)
    return str(target)
