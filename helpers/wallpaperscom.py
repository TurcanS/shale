"""Keyless Wallpapers.com keyword browsing and download-on-apply."""
import json
import os
from pathlib import Path
import re
import tempfile
import threading
import time
from urllib.parse import urlparse
from urllib.request import Request, HTTPRedirectHandler, build_opener

import wallhaven

_CACHE = {}
_CACHE_LOCK = threading.Lock()  # searches run on worker threads
_MAX_IMAGE = 40 * 1024 * 1024


def _url(value, image=False):
    parsed = urlparse(str(value))
    if (parsed.scheme != 'https' or parsed.hostname != 'wallpapers.com'
            or parsed.username or parsed.password or parsed.port not in (None, 443)
            or (image and not parsed.path.startswith('/images/'))):
        raise ValueError('Unexpected address from Wallpapers.com.')
    return str(value)


class _Redirect(HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, newurl):
        _url(newurl)
        return super().redirect_request(request, response, code, message, headers, newurl)


def _open(url):
    return build_opener(_Redirect()).open(Request(_url(url), headers={
        'User-Agent': 'ShaleShell/1.0', 'Accept-Encoding': 'identity',
    }), timeout=25)


def _id(value):
    if not isinstance(value, str) or not re.fullmatch(r'[0-9]{1,16}', value):
        raise ValueError('Choose a valid Wallpapers.com wallpaper.')
    return value


def _saved(folder, identity):
    for suffix in ('.jpg', '.png', '.webp'):
        path = Path(folder).expanduser().resolve() / 'Wallpapers.com' / (identity + suffix)
        if path.is_file() and path.stat().st_size > 0:
            return path
    return None


def search(query, page, folder):
    if not isinstance(query, str) or len(query) > 200:
        raise ValueError('Use a search of up to 200 characters.')
    if type(page) is not int or page != 1:
        raise ValueError('This source offers up to 60 wallpapers per keyword.')
    slug = re.sub(r'[^a-z0-9]+', '-', query.strip().lower()).strip('-') if query.strip() else 'desktop'
    if not slug:
        raise ValueError('Search using a keyword such as abstract, anime, or dark.')
    cached = _CACHE.get(slug)
    if cached and time.monotonic() - cached[0] < 300:
        payload = cached[1]
    else:
        with _open('https://wallpapers.com/api/v1/keyword/' + slug + '?limit=60') as response:
            data = response.read(2 * 1024 * 1024 + 1)
        if len(data) > 2 * 1024 * 1024:
            raise ValueError('Wallpapers.com returned too much data.')
        try:
            payload = json.loads(data)
        except (ValueError, UnicodeDecodeError):
            raise ValueError('Wallpapers.com returned an invalid response. Try again later.') from None
        if not isinstance(payload, dict) or not isinstance(payload.get('items'), list):
            raise ValueError('Wallpapers.com returned an unexpected response.')
        with _CACHE_LOCK:
            if len(_CACHE) >= 20:
                _CACHE.pop(next(iter(_CACHE)), None)
            _CACHE[slug] = (time.monotonic(), payload)
    entries = []
    for item in payload['items'][:60]:
        try:
            if item.get('type') != 'wallpaper':
                continue
            identity = _id(str(item['id']))
            local = _saved(folder, identity)
            entries.append({'id': identity, 'provider': 'wallpaperscom', 'remote': True,
                'name': str(item.get('title') or item.get('alt') or 'Wallpaper').strip(),
                'file': identity, 'path': str(local) if local else '',
                'url': local.as_uri() if local else _url(item['thumb'], True),
                'downloadUrl': _url(item['high'], True),
                'creditUrl': _url(item.get('credit_url', 'https://wallpapers.com/'))})
        except (KeyError, TypeError, ValueError):
            continue
    return {'entries': entries, 'page': 1, 'hasMore': False}


def download(identity, image_url, name, folder):
    identity = _id(identity)
    path = _saved(folder, identity)
    if not path:
        image_url = _url(image_url, True)
        directory = Path(folder).expanduser().resolve() / 'Wallpapers.com'
        directory.mkdir(parents=True, exist_ok=True)
        temporary = None
        try:
            with _open(image_url) as response:
                suffix = {'image/jpeg': '.jpg', 'image/png': '.png', 'image/webp': '.webp'}.get(response.headers.get_content_type())
                if not suffix:
                    raise ValueError('Wallpapers.com did not return a supported image.')
                if int(response.headers.get('Content-Length', '0')) > _MAX_IMAGE:
                    raise ValueError('This image is larger than 40 MB.')
                fd, temporary = tempfile.mkstemp(prefix='.download-', dir=directory)
                total, deadline = 0, time.monotonic() + 90
                with os.fdopen(fd, 'wb') as stream:
                    while True:
                        block = response.read(128 * 1024)
                        if not block:
                            break
                        if not total and not wallhaven.image_signature_ok(block, suffix):
                            raise ValueError('Wallpapers.com did not return a valid image.')
                        total += len(block)
                        if total > _MAX_IMAGE or time.monotonic() > deadline:
                            raise ValueError('The wallpaper download exceeded its size or time limit.')
                        stream.write(block)
                if not total:
                    raise ValueError('The downloaded image was empty.')
            path = directory / (identity + suffix)
            os.replace(temporary, path)
            temporary = None
        finally:
            if temporary:
                os.unlink(temporary)
    return {'id': identity, 'provider': 'wallpaperscom', 'remote': True,
            'path': str(path), 'url': path.as_uri(), 'file': path.name,
            'name': str(name or 'Wallpaper')[:300]}


def message(error):
    return wallhaven.message(error).replace('Wallhaven', 'Wallpapers.com').replace('wallhaven.cc', 'wallpapers.com')
