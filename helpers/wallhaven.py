"""Wallhaven SFW search and download-on-apply using the Python standard library."""
import json
import os
import socket
import ssl
from pathlib import Path
import re
import tempfile
import threading
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlparse
from urllib.request import Request, HTTPRedirectHandler, build_opener

_API = 'https://wallhaven.cc/api/v1'
_SEARCH_CACHE = {}
_CACHE_LOCK = threading.Lock()  # searches run on worker threads
_MAX_IMAGE = 40 * 1024 * 1024

def image_signature_ok(head, suffix):
    """The first bytes must match the advertised type, not just the Content-Type header."""
    if suffix == '.webp':
        return head[:4] == b'RIFF' and head[8:12] == b'WEBP'
    return head.startswith({'.jpg': b'\xff\xd8\xff', '.png': b'\x89PNG\r\n\x1a\n'}[suffix])

def _url(value, hosts):
    parsed = urlparse(str(value))
    if parsed.scheme != 'https' or parsed.hostname not in hosts or parsed.username or parsed.password or parsed.port not in (None, 443):
        raise ValueError('Unexpected image address from Wallhaven.')
    return str(value)

class _RestrictedRedirect(HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, newurl):
        _url(newurl, {'wallhaven.cc', 'w.wallhaven.cc', 'th.wallhaven.cc'})
        return super().redirect_request(request, response, code, message, headers, newurl)

def _open(url):
    api_request = urlparse(url).hostname == 'wallhaven.cc'
    headers = {
        'User-Agent': 'ShaleShell/1.0',
        'Accept': 'application/json' if api_request else 'image/jpeg,image/png,image/webp',
        'Accept-Encoding': 'identity',
    }
    # Retry a temporary upstream failure once. Do not retry denied or rate-limited requests.
    for attempt in range(2):
        try:
            return build_opener(_RestrictedRedirect()).open(Request(url, headers=headers), timeout=25)
        except HTTPError as error:
            if attempt == 0 and error.code in (502, 503, 504):
                error.close()
                time.sleep(1)
                continue
            raise

def _json(url):
    with _open(url) as response:
        content = response.read(2 * 1024 * 1024 + 1)
    if len(content) > 2 * 1024 * 1024:
        raise ValueError('Wallhaven returned too much data.')
    try:
        return json.loads(content)
    except (ValueError, UnicodeDecodeError):
        raise ValueError('Wallhaven returned a web page or invalid data instead of an API response. The API may be blocked or temporarily unavailable.') from None

def _id(value):
    if not isinstance(value, str) or not re.fullmatch(r'[a-zA-Z0-9]{6}', value):
        raise ValueError('Choose a valid Wallhaven wallpaper.')
    return value

def _saved(folder, identity):
    for suffix in ('.jpg', '.png', '.webp'):
        path = Path(folder).expanduser().resolve() / 'Wallhaven' / ('wallhaven-' + identity + suffix)
        if path.is_file() and path.stat().st_size > 0:
            return path
    return None

def _entry(path, identity):
    return {'id': identity, 'path': str(path), 'url': path.as_uri(), 'name': 'Wallhaven ' + identity, 'file': path.name, 'remote': True}

def search(query, page, folder):
    if not isinstance(query, str) or len(query) > 200:
        raise ValueError('Use a search of up to 200 characters.')
    if type(page) is not int or not 1 <= page <= 100:
        raise ValueError('Invalid search page.')
    query = query.strip()
    key = (query, page)
    cached = _SEARCH_CACHE.get(key)
    warning = ''
    if cached and time.monotonic() - cached[0] < 300:
        payload = cached[1]
    else:
        params = {'q': query, 'page': page, 'purity': '100', 'categories': '111', 'sorting': 'relevance' if query else 'toplist', 'order': 'desc'}
        try:
            payload = _json(_API + '/search?' + urlencode(params))
        except (HTTPError, URLError, TimeoutError) as error:
            if not cached or (isinstance(error, HTTPError) and error.code not in (502, 503, 504)):
                raise
            payload = cached[1]
            warning = 'Wallhaven is temporarily unreachable. Showing previously loaded results; saved wallpapers remain available.'
        if not isinstance(payload, dict) or not isinstance(payload.get('data'), list):
            raise ValueError('Wallhaven returned an unexpected response.')
        if not warning:
            with _CACHE_LOCK:
                if len(_SEARCH_CACHE) >= 20:
                    _SEARCH_CACHE.pop(next(iter(_SEARCH_CACHE)), None)
                _SEARCH_CACHE[key] = (time.monotonic(), payload)
    entries = []
    for item in payload['data'][:24]:
        try:
            identity = _id(item['id'])
            thumb = _url(item['thumbs']['large'], {'th.wallhaven.cc'})
            local = _saved(folder, identity)
            entries.append({'id': identity, 'name': 'Wallhaven ' + identity, 'file': identity,
                            'url': local.as_uri() if local else thumb, 'path': str(local) if local else '', 'remote': True,
                            'resolution': str(item.get('resolution', ''))})
        except (ValueError, KeyError, TypeError):
            continue
    meta = payload.get('meta') or {}
    return {'entries': entries, 'page': page, 'hasMore': page < min(100, int(meta.get('last_page', page))), 'warning': warning}

def download(identity, folder):
    identity = _id(identity)
    existing = _saved(folder, identity)
    if existing:
        return _entry(existing, identity)
    payload = _json(_API + '/w/' + identity)
    data = payload.get('data') if isinstance(payload, dict) else None
    if not isinstance(data, dict) or data.get('purity') != 'sfw':
        raise ValueError('This wallpaper is not available in the public collection.')
    url = _url(data.get('path', ''), {'w.wallhaven.cc'})
    directory = Path(folder).expanduser().resolve() / 'Wallhaven'
    directory.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with _open(url) as response:
            suffix = {'image/jpeg': '.jpg', 'image/png': '.png', 'image/webp': '.webp'}.get(response.headers.get_content_type())
            if not suffix:
                raise ValueError('Wallhaven did not return a supported image.')
            if int(response.headers.get('Content-Length', '0')) > _MAX_IMAGE:
                raise ValueError('This image is larger than 40 MB.')
            fd, temporary = tempfile.mkstemp(prefix='.wallhaven-', dir=directory)
            total = 0
            deadline = time.monotonic() + 90
            with os.fdopen(fd, 'wb') as stream:
                while True:
                    block = response.read(128 * 1024)
                    if not block: break
                    if not total and not image_signature_ok(block, suffix):
                        raise ValueError('Wallhaven did not return a valid image.')
                    total += len(block)
                    if total > _MAX_IMAGE or time.monotonic() > deadline:
                        raise ValueError('The wallpaper download exceeded its size or time limit.')
                    stream.write(block)
                if total == 0:
                    raise ValueError('The downloaded image was empty.')
            destination = directory / ('wallhaven-' + identity + suffix)
            os.replace(temporary, destination)
            temporary = None
            return _entry(destination, identity)
    finally:
        if temporary and os.path.exists(temporary): os.unlink(temporary)

def message(error):
    if isinstance(error, HTTPError):
        if error.code == 503:
            return 'Wallhaven service unavailable (HTTP 503). Try again later, or use My wallpapers for saved images.'
        if error.code == 429:
            return 'Wallhaven rate limit reached (HTTP 429). Wait a minute before searching again.'
        if error.code == 403:
            return 'Wallhaven denied the API request (HTTP 403). Retry later; this may be a service-side or network access restriction.'
        if error.code == 401:
            return 'Wallhaven requires authentication for this request (HTTP 401).'
        if error.code == 404:
            return 'Wallhaven could not find that wallpaper or endpoint (HTTP 404).'
        return f'Wallhaven returned HTTP {error.code}. Try again shortly.'
    reason = error.reason if isinstance(error, URLError) else error
    if isinstance(reason, ssl.SSLCertVerificationError):
        return 'The Wallhaven TLS certificate could not be validated. Check your system clock and certificate configuration.'
    if isinstance(reason, socket.gaierror):
        return 'Could not resolve wallhaven.cc. Check your DNS or network connection.'
    if isinstance(reason, (TimeoutError, socket.timeout)):
        return 'Wallhaven did not respond in time. Try again.'
    if isinstance(reason, ConnectionRefusedError):
        return 'The connection to Wallhaven was refused. Check network or proxy settings.'
    if isinstance(error, URLError):
        return 'Could not connect to Wallhaven. Check your connection or proxy settings.'
    if isinstance(error, ValueError):
        return str(error)
    if isinstance(error, PermissionError):
        return 'The wallpaper folder is not writable. Choose another folder in Appearance settings.'
    return 'The wallpaper request failed. Check the connection and available disk space.'
