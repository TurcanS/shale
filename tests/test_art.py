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

    def test_only_the_newest_covers_are_kept(self):
        paths = []
        for index in range(5):
            paths.append(art.local(f"https://example.com/{index}", self.folder, self.fetch, keep=3))
            os.utime(paths[-1], (index, index))
        self.assertEqual(sorted(p.name for p in self.folder.iterdir()), sorted(Path(p).name for p in paths[-3:]))


if __name__ == "__main__":
    unittest.main()
