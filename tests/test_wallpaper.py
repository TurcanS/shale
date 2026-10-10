import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import AsyncMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'helpers'))
import backend as b
import wallpaper as w

class WallpaperTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        # Never look for (or start) a real wallpaper daemon from the tests.
        self.daemon = patch.object(w, 'ensure', AsyncMock(return_value='hyprpaper'))
        self.daemon.start()
        self.addCleanup(self.daemon.stop)
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name)
        self.image = self.path / 'soft sky.png'
        self.image.write_bytes(b'test-image')
    async def asyncTearDown(self):
        self.temp.cleanup()
    def test_catalog_filters_and_file_urls(self):
        (self.path / 'notes.txt').write_text('not an image')
        result = w.catalog(self.path)
        self.assertEqual(len(result['entries']), 1)
        self.assertEqual(result['entries'][0]['name'], 'soft sky')
        self.assertIn('soft%20sky.png', result['entries'][0]['url'])
        self.assertEqual(w.catalog(self.path / 'missing')['entries'], [])
        self.assertFalse(result['limited'])
    def test_catalog_says_when_it_stopped_at_the_limit(self):
        for name in ('b.png', 'c.png'):
            (self.path / name).write_bytes(b'image')
        with patch.object(w, 'CATALOG_LIMIT', 2):
            result = w.catalog(self.path)
        self.assertEqual((len(result['entries']), result['limited']), (2, True))
    async def test_apply_argument_boundaries_and_monitor(self):
        run = AsyncMock(side_effect=[b'[{"name":"eDP-1"}]', b'', f'eDP-1: {self.image}\n'.encode()])
        result = await w.apply(run, str(self.image), 'eDP-1', b.BackendError)
        self.assertEqual(result['monitor'], 'eDP-1')
        self.assertEqual(run.await_args_list[1].args, ('hyprctl', 'hyprpaper', 'wallpaper', f'eDP-1,{self.image},cover'))
        with self.assertRaises(b.BackendError):
            await w.apply(AsyncMock(return_value=b'[]'), str(self.image), 'gone', b.BackendError)
    async def test_rejects_missing_paths_and_ambiguous_ipc(self):
        run = AsyncMock()
        with self.assertRaises(b.BackendError):
            await w.apply(run, '/missing.jpg', 'eDP-1', b.BackendError)
        bad = self.path / 'a,b.png'; bad.write_bytes(b'image')
        with self.assertRaises(b.BackendError):
            await w.apply(run, str(bad), 'eDP-1', b.BackendError)
        run.assert_not_awaited()
    async def test_failure_does_not_persist_and_success_does(self):
        state = self.path / 'state'
        instance = b.Backend()
        with patch.object(b, 'STATE', state), patch.object(b, 'run', AsyncMock(side_effect=[b'[{"name":"eDP-1"}]', b'error loading image'])):
            with self.assertRaises(b.BackendError):
                await instance.dispatch('wallpaper.apply', {'path':str(self.image), 'monitor':'eDP-1'})
            self.assertFalse((state / 'wallpapers.json').exists())
        with patch.object(b, 'STATE', state), patch.object(b, 'run', AsyncMock(side_effect=[b'[{"name":"eDP-1"}]', b'ok', f'eDP-1: {self.image}\n'.encode()])):
            await instance.dispatch('wallpaper.apply', {'path':str(self.image), 'monitor':'eDP-1'})
            self.assertEqual(json.loads((state / 'wallpapers.json').read_text()), {'eDP-1':str(self.image)})
    async def test_success_response_requires_actual_wallpaper_change(self):
        run = AsyncMock(side_effect=[b'[{"name":"eDP-1"}]', b'', b'eDP-1: /different.png'])
        with self.assertRaises(b.BackendError):
            await w.apply(run, str(self.image), 'eDP-1', b.BackendError)

    async def test_restore_skips_disconnected_outputs(self):
        state = self.path / 'state'; state.mkdir()
        (state / 'wallpapers.json').write_text(json.dumps({'gone':str(self.image)}))
        run = AsyncMock(return_value=b'[{"name":"eDP-1"}]')
        with patch.object(b, 'STATE', state), patch.object(b, 'run', run):
            self.assertEqual(await b.Backend().dispatch('wallpaper.restore', {}), {'restored': [], 'failed': {}})
        self.assertEqual(run.await_count, 1)
        w.ensure.assert_not_awaited()  # nothing to restore: no daemon is started

    async def test_restore_continues_past_a_failing_output_and_skips_shown_ones(self):
        state = self.path / 'state'; state.mkdir()
        other = self.path / 'dunes.png'; other.write_bytes(b'image')
        (state / 'wallpapers.json').write_text(json.dumps({'eDP-1': str(self.image), 'HDMI-A-1': str(other), 'DP-2': str(self.image)}))
        monitors = b'[{"name":"eDP-1"},{"name":"HDMI-A-1"},{"name":"DP-2"}]'
        apply = AsyncMock(side_effect=[b.BackendError('failed', 'The wallpaper daemon did not confirm the selected wallpaper.'), {}])
        with patch.object(b, 'STATE', state), patch.object(b, 'run', AsyncMock(return_value=monitors)), patch.object(w, 'apply', apply), \
                patch.object(w, 'active', AsyncMock(return_value={'DP-2': str(self.image)})):
            result = await b.Backend().dispatch('wallpaper.restore', {})
        self.assertEqual(result, {'restored': ['HDMI-A-1'], 'failed': {'eDP-1': 'The wallpaper daemon did not confirm the selected wallpaper.'}})
        self.assertEqual([call.args[2] for call in apply.await_args_list], ['eDP-1', 'HDMI-A-1'])


class DaemonTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.proc = Path(self.temp.name)

    def process(self, pid, name):
        (self.proc / str(pid)).mkdir()
        (self.proc / str(pid) / 'comm').write_text(name + '\n')

    def test_current_daemon(self):
        self.assertIsNone(w.current(self.proc))
        self.process(10, 'swaybg')
        self.assertEqual(w.current(self.proc), 'foreign')
        self.process(11, 'awww-daemon')
        self.assertEqual(w.current(self.proc), 'awww')
        self.process(12, 'hyprpaper')
        self.assertEqual(w.current(self.proc), 'hyprpaper')

    async def test_starts_the_first_installed_daemon_only_when_nothing_runs(self):
        started = []
        def spawn(command, **options):
            started.append(command)
            self.process(20, 'awww-daemon')
        which = lambda name: name in ('awww', 'awww-daemon')
        self.assertEqual(await w.ensure(self.proc, which, spawn, AsyncMock()), 'awww')
        self.assertEqual(started, [['awww-daemon']])
        self.assertEqual(await w.ensure(self.proc, which, spawn, AsyncMock()), 'awww')
        self.assertEqual(len(started), 1)

    async def test_no_daemon_and_another_tool(self):
        self.assertIsNone(await w.ensure(self.proc, lambda name: False, None, AsyncMock()))
        self.assertIn('Install hyprpaper or awww', w.unavailable(None, b.BackendError).message)
        self.process(30, 'swaybg')
        self.assertEqual(await w.ensure(self.proc, lambda name: True, None, AsyncMock()), 'foreign')
        self.assertIn('Another wallpaper tool', w.unavailable('foreign', b.BackendError).message)

    async def test_awww_apply_and_query(self):
        image = self.proc / 'sky,blue.png'
        image.write_bytes(b'image')
        query = f': eDP-1: 1920x1080, scale: 1, currently displaying: image: {image}\nHDMI-A-1: 2560x1440, scale: 1, currently displaying: color: 000000\n'
        run = AsyncMock(side_effect=[b'[{"name":"eDP-1"}]', b'', query.encode()])
        result = await w.apply(run, str(image), 'eDP-1', b.BackendError, 'awww')
        self.assertEqual(result['monitor'], 'eDP-1')
        self.assertEqual(run.await_args_list[1].args, ('awww', 'img', '--outputs', 'eDP-1', '--transition-type', 'none', str(image)))
        self.assertEqual(await w.active(AsyncMock(return_value=query.encode()), 'swww'), {'eDP-1': str(image)})

