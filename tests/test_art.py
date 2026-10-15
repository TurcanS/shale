import base64
from pathlib import Path
import os
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "helpers"))
import art

PNG = b"\x89PNG\r\n\x1a\n" + b"\0" * 32


class ArtTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.folder = Path(self.tmp.name) / "art"
        self.fetched = []

    def tearDown(self):
        self.tmp.cleanup()

    def fetch(self, url):
        self.fetched.append(url)
        return PNG

    def test_local_files_pass_through(self):
        cover = Path(self.tmp.name) / "my cover.png"
        cover.write_bytes(PNG)
        self.assertEqual(art.local(cover.as_uri(), self.folder, self.fetch), str(cover))
        with self.assertRaisesRegex(ValueError, "missing"):
            art.local((Path(self.tmp.name) / "gone.png").as_uri(), self.folder, self.fetch)

    def test_remote_covers_are_downloaded_once(self):
        first = art.local("https://i.scdn.co/image/abc", self.folder, self.fetch)
        again = art.local("https://i.scdn.co/image/abc", self.folder, self.fetch)
        self.assertEqual(first, again)
        self.assertEqual(Path(first).read_bytes(), PNG)
        self.assertEqual(self.fetched, ["https://i.scdn.co/image/abc"])

    def test_data_urls_are_decoded(self):
        url = "data:image/png;base64," + base64.b64encode(PNG).decode()
        self.assertEqual(Path(art.local(url, self.folder, self.fetch)).read_bytes(), PNG)
        self.assertEqual(self.fetched, [])
        for bad, message in (("data:image/png;base64,***", "decoded"), ("data:text/html;base64,AAAA", "not an image"),
                             ("data:image/png;base64," + "A" * (art.MAX_BYTES * 2), "too large")):
            with self.subTest(bad=bad[:30]), self.assertRaisesRegex(ValueError, message):
                art.local(bad, self.folder, self.fetch)

    def test_other_schemes_and_oversized_downloads_are_refused(self):
        with self.assertRaisesRegex(ValueError, "Unsupported"):
            art.local("ftp://example.com/cover.png", self.folder, self.fetch)
        with self.assertRaisesRegex(ValueError, "too large"):
            art.local("https://example.com/huge", self.folder, lambda url: b"x" * (art.MAX_BYTES + 1))
        self.assertFalse(self.folder.exists() and any(self.folder.iterdir()))

    def test_only_public_addresses_are_fetched(self):
        resolver = lambda addresses: lambda host, port, proto=0: [(0, 0, 0, "", (address, port)) for address in addresses]
        art.public("https://i.scdn.co/image/abc", resolver(["151.101.2.248"]))
        for url, addresses in (("http://localhost:631/", ["127.0.0.1"]), ("http://router/", ["192.168.1.1"]),
                               ("http://[::1]/cover", ["::1"]), ("http://metadata/", ["169.254.169.254"]),
                               ("https://mixed.example/", ["151.101.2.248", "10.0.0.5"])):
            with self.subTest(url=url), self.assertRaisesRegex(ValueError, "public addresses"):
                art.public(url, resolver(addresses))
        with self.assertRaisesRegex(ValueError, "Unsupported"):
            art.public("file:///etc/passwd")

    def test_the_connected_address_must_be_public(self):
        # A name that passes the first lookup but then connects somewhere local (DNS rebinding) is refused.
        import http.server, threading
        server = http.server.HTTPServer(("127.0.0.1", 0), http.server.SimpleHTTPRequestHandler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            original = art.public
            art.public = lambda url, resolve=None: None
            with self.assertRaisesRegex(ValueError, "public addresses"):
                art._fetch(f"http://127.0.0.1:{server.server_address[1]}/cover.png")
        finally:
            art.public = original
            server.shutdown()
            server.server_close()

    def test_a_configured_proxy_is_used_instead_of_refused(self):
        handlers = lambda opener: {type(handler).__name__ for handler in opener.handlers}
        proxied = art._opener("https://i.scdn.co/a", {"https": "http://127.0.0.1:3128"}, bypass=lambda host: False)
        self.assertNotIn("_PublicHTTPS", handlers(proxied))
        direct = art._opener("https://i.scdn.co/a", {}, bypass=lambda host: False)
        self.assertIn("_PublicHTTPS", handlers(direct))
        bypassed = art._opener("https://i.scdn.co/a", {"https": "http://127.0.0.1:3128"}, bypass=lambda host: True)
        self.assertIn("_PublicHTTPS", handlers(bypassed))

    def test_a_proxied_fetch_never_redirects_past_the_proxy(self):
        proxies = {"https": "http://127.0.0.1:3128"}
        opener = art._opener("https://i.scdn.co/a", proxies, bypass=lambda host: host == "localhost")
        redirects = next(h for h in opener.handlers if isinstance(h, art._CheckedRedirects))
        request = art.Request("https://i.scdn.co/a")
        resolve = lambda host, port, proto=0: [(0, 0, 0, "", ("151.101.2.248", port))]
        original = art.public
        art.public = lambda url, resolve_=None: original(url, resolve)
        try:
            for target in ("http://i.scdn.co/b", "https://localhost/b"):
                with self.subTest(target=target), self.assertRaisesRegex(ValueError, "past the proxy"):
                    redirects.redirect_request(request, None, 302, "Found", {}, target)
            self.assertIsNotNone(redirects.redirect_request(request, None, 302, "Found", {}, "https://other.example/b"))
        finally:
            art.public = original

    def test_a_broken_response_is_a_failed_download(self):
        import http.client
        class Broken:
            def open(self, request, timeout):
                raise http.client.IncompleteRead(b"partial")
        original_opener, original_public = art._opener, art.public
        art._opener, art.public = (lambda url: Broken()), (lambda url: None)
        try:
            with self.assertRaises(OSError):
                art._fetch("https://i.scdn.co/a")
        finally:
            art._opener, art.public = original_opener, original_public

    def test_the_proxy_bypass_sees_the_port_as_urllib_does(self):
        # NO_PROXY=cdn.example:8080 makes urllib connect directly, so the direct, checked handlers must be used.
        handlers = lambda opener: {type(handler).__name__ for handler in opener.handlers}
        bypass = lambda host: host == "cdn.example:8080"
        opener = art._opener("http://user@cdn.example:8080/a", {"http": "http://127.0.0.1:3128"}, bypass=bypass)
        self.assertIn("_PublicHTTP", handlers(opener))
        self.assertNotIn("_PublicHTTP", handlers(art._opener("http://cdn.example/a", {"http": "http://127.0.0.1:3128"}, bypass=bypass)))

    def test_a_slow_cover_stops_at_the_deadline(self):
        class Slow:
            headers = art.http.client.HTTPMessage()
            def __init__(self):
                self.headers["Content-Type"] = "image/png"
            def __enter__(self):
                return self
            def __exit__(self, *exc):
                return False
            def read1(self, size):
                return b"x"
        clock = iter(range(0, 1000, 3))
        original = art._opener, art.public, art.time.monotonic
        art._opener, art.public, art.time.monotonic = (lambda url: type("O", (), {"open": lambda self, r, timeout: Slow()})()), (lambda url: None), (lambda: next(clock))
        try:
            with self.assertRaisesRegex(OSError, "too long"):
                art._fetch("https://i.scdn.co/a")
        finally:
            art._opener, art.public, art.time.monotonic = original

    def test_a_cover_pruned_meanwhile_is_fetched_again(self):
        path = Path(art.local("https://example.com/a", self.folder, self.fetch))
        path.unlink()
        self.assertEqual(art.local("https://example.com/a", self.folder, self.fetch), str(path))
        self.assertEqual(len(self.fetched), 2)

    def test_only_the_newest_covers_are_kept(self):
        paths = []
        for index in range(5):
            paths.append(art.local(f"https://example.com/{index}", self.folder, self.fetch, keep=3))
            os.utime(paths[-1], (index, index))
        self.assertEqual(sorted(p.name for p in self.folder.iterdir()), sorted(Path(p).name for p in paths[-3:]))


if __name__ == "__main__":
    unittest.main()
