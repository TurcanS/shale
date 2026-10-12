"""Album art as a local file. Quickshell's colour quantizer only reads files, while players hand out
https:// covers (Spotify) or whole images in data: URLs (browsers)."""
import base64
import binascii
import hashlib
import http.client
import ipaddress
import os
from pathlib import Path
import socket
import tempfile
from urllib.parse import unquote, unquote_to_bytes, urlsplit
from urllib.request import (HTTPHandler, HTTPRedirectHandler, HTTPSHandler, ProxyHandler, Request, build_opener, getproxies,
                            proxy_bypass)

MAX_BYTES = 5 * 1024 * 1024
KEEP = 20


def public(url, resolve=socket.getaddrinfo):
    """Refuse covers on this machine or the local network: any app can name a cover, and the helper should
    not become a way to poke at local services."""
    parts = urlsplit(url)
    if parts.scheme not in ('http', 'https') or not parts.hostname:
        raise ValueError('Unsupported cover address.')
    try:
        addresses = {info[4][0] for info in resolve(parts.hostname, parts.port or 443, proto=socket.IPPROTO_TCP)}
    except (OSError, UnicodeError):
        raise ValueError('The cover address could not be resolved.') from None
    if not addresses or not all(ipaddress.ip_address(address.split('%')[0]).is_global for address in addresses):
        raise ValueError('Covers are only fetched from public addresses.')


def _connect_public(address, *args, **kwargs):
    """socket.create_connection, refusing the connection unless the address it reached is public. Checked on the
    connected socket itself, so a name that resolves differently the second time (DNS rebinding) can't slip by."""
    sock = socket.create_connection(address, *args, **kwargs)
    if not ipaddress.ip_address(sock.getpeername()[0].split('%')[0]).is_global:
        sock.close()
        raise ValueError('Covers are only fetched from public addresses.')
    return sock


class _PublicHTTPConnection(http.client.HTTPConnection):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._create_connection = _connect_public


class _PublicHTTPSConnection(http.client.HTTPSConnection):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        # Before the TLS handshake: HTTPSConnection.connect opens the plain socket through this.
        self._create_connection = _connect_public


class _PublicHTTP(HTTPHandler):
    def http_open(self, request):
        return self.do_open(_PublicHTTPConnection, request)


class _PublicHTTPS(HTTPSHandler):
    def https_open(self, request):
        return self.do_open(_PublicHTTPSConnection, request, context=self._context)


class _CheckedRedirects(HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, url):
        public(url)
        return super().redirect_request(request, fp, code, message, headers, url)


def _proxied(url, proxies, bypass):
    parts = urlsplit(url)
    return bool(proxies.get(parts.scheme)) and not bypass(parts.hostname or '')


def _opener(url, proxies=None, bypass=proxy_bypass):
    """Direct connections are checked on the socket. Through a configured proxy the socket reaches the proxy (often
    on this machine), so the name check is all there is: the proxy makes the real connection. A redirect must then
    stay on the proxy too, or it would connect directly with only the name check."""
    proxies = getproxies() if proxies is None else proxies
    if not _proxied(url, proxies, bypass):
        return build_opener(ProxyHandler({}), _PublicHTTP, _PublicHTTPS, _CheckedRedirects)

    class StayOnProxy(_CheckedRedirects):
        def redirect_request(self, request, fp, code, message, headers, target):
            if not _proxied(target, proxies, bypass):
                raise ValueError('The cover redirects past the proxy.')
            return super().redirect_request(request, fp, code, message, headers, target)
    return build_opener(ProxyHandler(proxies), StayOnProxy)


def _fetch(url):
    # A quick refusal by name first; for direct connections the connected socket is what actually decides.
    public(url)
    request = Request(url, headers={'User-Agent': 'ShaleShell/1.0', 'Accept': 'image/*', 'Accept-Encoding': 'identity'})
    try:
        with _opener(url).open(request, timeout=5) as response:
            if not response.headers.get_content_type().startswith('image/'):
                raise ValueError('The cover is not an image.')
            return response.read(MAX_BYTES + 1)
    except http.client.HTTPException as error:
        # A dropped or garbled response (IncompleteRead, BadStatusLine…) is a failed download like any other.
        raise OSError(str(error)) from None


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
    try:
        os.utime(target)
        return str(target)
    except FileNotFoundError:
        # Not cached, or pruned by another request a moment ago.
        pass
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
    # Only the newest covers are kept. Requests run in parallel threads, so another one may prune a file first.
    def modified(path):
        try:
            return path.stat().st_mtime
        except FileNotFoundError:
            return 0
    covers = sorted((p for p in folder.iterdir() if not p.name.startswith('.')), key=modified, reverse=True)
    for old in covers[keep:]:
        if old != target:
            old.unlink(missing_ok=True)
    return str(target)
