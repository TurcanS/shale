import io
import json
from email.message import Message
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'helpers'))
import wallhaven
import wallpaperscom as source


class Response(io.BytesIO):
    def __init__(self, data, content_type='image/jpeg'):
        super().__init__(data)
        self.headers = Message()
        self.headers['Content-Type'] = content_type


class WallpaperSourceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        source._CACHE.clear()
        wallhaven._SEARCH_CACHE.clear()

    def test_download_reuse_never_requests_network(self):
        saved = self.folder / 'Wallpapers.com' / '123.jpg'
        saved.parent.mkdir()
        saved.write_bytes(b'previously-saved-image')
        with patch.object(source, '_open') as request:
            result = source.download('123', '', 'Saved', self.folder)
        request.assert_not_called()
        self.assertEqual(result['path'], str(saved))

    def test_failed_download_leaves_no_partial_image(self):
        with patch.object(source, '_open', return_value=Response(b'\xff\xd8\xff-too-large')), patch.object(source, '_MAX_IMAGE', 4):
            with self.assertRaises(ValueError):
                source.download('123', 'https://wallpapers.com/images/high/a.jpg', 'A', self.folder)
        self.assertEqual(list((self.folder / 'Wallpapers.com').iterdir()), [])

    def test_html_response_is_not_saved_as_wallpaper(self):
        with patch.object(source, '_open', return_value=Response(b'<html>error</html>', 'text/html')):
            with self.assertRaises(ValueError):
                source.download('123', 'https://wallpapers.com/images/high/a.jpg', 'A', self.folder)
        self.assertIsNone(source._saved(self.folder, '123'))

    def test_mislabelled_download_is_not_saved(self):
        with patch.object(source, '_open', return_value=Response(b'<html>error</html>', 'image/jpeg')):
            with self.assertRaises(ValueError):
                source.download('123', 'https://wallpapers.com/images/high/a.jpg', 'A', self.folder)
        self.assertEqual(list((self.folder / 'Wallpapers.com').iterdir()), [])

    def test_image_signatures(self):
        self.assertTrue(wallhaven.image_signature_ok(b'\xff\xd8\xff\xe0rest', '.jpg'))
        self.assertTrue(wallhaven.image_signature_ok(b'\x89PNG\r\n\x1a\nrest', '.png'))
        self.assertTrue(wallhaven.image_signature_ok(b'RIFF\0\0\0\0WEBPVP8 ', '.webp'))
        self.assertFalse(wallhaven.image_signature_ok(b'\x89PNG\r\n\x1a\n', '.jpg'))
        self.assertFalse(wallhaven.image_signature_ok(b'RIFF\0\0\0\0WAVE', '.webp'))

    def test_valid_download_is_saved(self):
        with patch.object(source, '_open', return_value=Response(b'\xff\xd8\xff\xe0image')):
            result = source.download('123', 'https://wallpapers.com/images/high/a.jpg', 'A', self.folder)
        self.assertEqual(Path(result['path']).read_bytes(), b'\xff\xd8\xff\xe0image')

    def test_redirect_cannot_leave_provider(self):
        with self.assertRaises(ValueError):
            source._Redirect().redirect_request(None, None, 302, '', {}, 'https://example.com/images/a.jpg')

    def test_search_caches_results_and_filters_untrusted_images(self):
        item = {'id': 123, 'type': 'wallpaper', 'title': 'A',
                'thumb': 'https://wallpapers.com/images/thumbnail/a.jpg',
                'high': 'https://wallpapers.com/images/high/a.jpg',
                'url': 'https://wallpapers.com/wallpapers/a.html'}
        payload = json.dumps({'items': [item, dict(item, id=124, high='http://localhost/image.jpg')]}).encode()
        with patch.object(source, '_open', return_value=Response(payload, 'application/json')) as request:
            first = source.search('Dark sky', 1, self.folder)
            second = source.search('Dark sky', 1, self.folder)
        request.assert_called_once()
        self.assertEqual(first, second)
        self.assertEqual([entry['id'] for entry in first['entries']], ['123'])

    def test_wallhaven_outage_keeps_stale_cache_without_refreshing_age(self):
        # Stale relative to now; a fixed 0 would still count as fresh in the first minutes after boot.
        stale = time.monotonic() - 3600
        wallhaven._SEARCH_CACHE[('', 1)] = (stale, {'data': [], 'meta': {'last_page': 1}})
        failure = HTTPError('https://wallhaven.cc/api/v1/search', 503, 'Unavailable', {}, None)
        with patch.object(wallhaven, '_json', side_effect=failure):
            result = wallhaven.search('', 1, self.folder)
        self.assertTrue(result['warning'])
        self.assertEqual(wallhaven._SEARCH_CACHE[('', 1)][0], stale)
