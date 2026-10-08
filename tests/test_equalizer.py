import json
from pathlib import Path
import re
import sys
import tempfile
import unittest
from unittest.mock import AsyncMock, MagicMock, patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "helpers"))
import equalizer


def dump(node_id):
    return json.dumps([{"id": 5, "type": "PipeWire:Interface:Node", "info": {"props": {"node.name": "other"}}},
                       {"id": node_id, "type": "PipeWire:Interface:Node", "info": {"props": {"node.name": equalizer.NODE}}}]).encode()


class ConfigTests(unittest.TestCase):
    def test_validate_rounds_to_half_decibels_and_rejects_bad_input(self):
        self.assertEqual(equalizer.validate([0.26, -0.24, 12, -12, 1, 2, 3, 4, 5, 6]), [0.5, 0.0, 12.0, -12.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0])
        for bands in ([0] * 9, [0] * 11, [13] + [0] * 9, [True] + [0] * 9, [float("nan")] + [0] * 9, ["1"] + [0] * 9, None, {}):
            with self.subTest(bands=bands), self.assertRaises(ValueError):
                equalizer.validate(bands)

    def test_presets_are_valid(self):
        for name, bands in equalizer.PRESETS.items():
            with self.subTest(name=name):
                self.assertEqual(equalizer.validate(bands), bands)

    def test_qml_presets_mirror_backend(self):
        source = (ROOT / "features/Equalizer.qml").read_text()
        for name, bands in equalizer.PRESETS.items():
            match = re.search(rf"\b{name}: \[([^\]]*)\]", source)
            self.assertIsNotNone(match, name)
            self.assertEqual([float(x) for x in match[1].split(",")], [float(x) for x in bands], name)

    def test_preamp_removes_the_largest_boost(self):
        self.assertEqual(equalizer.preamp([0] * 10), 1)
        self.assertEqual(equalizer.preamp([-6] * 10), 1)
        self.assertAlmostEqual(equalizer.preamp([6] + [0] * 9), 10 ** (-6 / 20))

    def test_config_chains_ten_bands_as_a_smart_filter(self):
        config = equalizer.render_config(equalizer.PRESETS["bass"])
        self.assertEqual(config.count("label = bq_peaking"), 10)
        self.assertIn('"Freq" = 16000.0', config)
        self.assertIn('{ output = "band_9:Out" input = "band_10:In" }', config)
        self.assertIn('outputs = [ "band_10:Out" ]', config)
        self.assertIn("filter.smart = true", config)
        self.assertIn('"Gain 1" = %.4f' % equalizer.preamp(equalizer.PRESETS["bass"]), config)

    def test_param_string_sets_every_band_and_the_preamp(self):
        params = equalizer.param_string([1.5] + [0] * 9)
        self.assertTrue(params.startswith("{ params = [ ") and params.endswith(" ] }"))
        self.assertIn('"band_1:Gain" 1.5', params)
        self.assertIn('"band_10:Gain" 0.0', params)
        self.assertIn('"preamp:Gain 1" %.4f' % equalizer.preamp([1.5]), params)


class LifecycleTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.runtime = Path(self.tmp.name)
        self.eq = equalizer.Equalizer(self.runtime)

    async def asyncTearDown(self):
        self.tmp.cleanup()

    def process(self, alive=True):
        process = MagicMock(pid=4242)
        process.poll.return_value = None if alive else 1
        return process

    async def test_start_writes_private_config_and_waits_for_node(self):
        process = self.process()
        run = AsyncMock(return_value=dump(77))
        with patch.object(equalizer.shutil, "which", return_value="/usr/bin/pipewire"), \
                patch.object(equalizer.subprocess, "Popen", return_value=process) as popen:
            await self.eq.start(run, equalizer.PRESETS["vocal"])
        self.assertEqual(popen.call_args.args[0], ["pipewire", "-c", str(self.eq.conf)])
        self.assertEqual(self.eq.conf.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.eq.pidfile.read_text(), "4242")
        self.assertEqual(self.eq.node, 77)
        self.assertEqual(self.eq.status(), {"enabled": True, "bands": equalizer.PRESETS["vocal"]})
        self.eq.stop()
        process.terminate.assert_called_once()
        self.assertFalse(self.eq.pidfile.exists())
        self.assertEqual(self.eq.status(), {"enabled": False, "bands": None})

    async def test_start_reports_a_filter_that_exits(self):
        with patch.object(equalizer.shutil, "which", return_value="/usr/bin/pipewire"), \
                patch.object(equalizer.subprocess, "Popen", return_value=self.process(alive=False)):
            with self.assertRaises(RuntimeError):
                await self.eq.start(AsyncMock(return_value=b"[]"), [0] * 10)
        self.assertFalse(self.eq.running)

    async def test_a_failing_lookup_stops_the_filter(self):
        process = self.process()
        with patch.object(equalizer.shutil, "which", return_value="/usr/bin/pipewire"), \
                patch.object(equalizer.subprocess, "Popen", return_value=process):
            with self.assertRaises(ValueError):
                await self.eq.start(AsyncMock(side_effect=ValueError("pw-dump returned garbage")), [0] * 10)
        process.terminate.assert_called_once()
        self.assertFalse(self.eq.running)
        self.assertEqual(self.eq.status(), {"enabled": False, "bands": None})

    async def test_update_refinds_node_after_a_failed_set_param(self):
        self.eq.process = self.process()
        self.eq.node = 12
        run = AsyncMock(side_effect=[RuntimeError("gone"), dump(90), b""])
        await self.eq.update(run, [2] + [0] * 9)
        self.assertEqual(self.eq.node, 90)
        self.assertEqual(run.call_args.args[:4], ("pw-cli", "set-param", "90", "Props"))
        self.assertEqual(self.eq.bands, [2] + [0] * 9)

    def test_reap_stale_only_kills_our_filter(self):
        self.runtime.mkdir(exist_ok=True)
        self.eq.pidfile.write_text("4242")
        with patch.object(equalizer.Path, "read_bytes", return_value=b"pipewire\0-c\0" + str(self.eq.conf).encode()), \
                patch.object(equalizer.os, "kill") as kill:
            self.eq.reap_stale()
        kill.assert_called_once_with(4242, equalizer.signal.SIGTERM)
        self.eq.pidfile.write_text("4242")
        with patch.object(equalizer.Path, "read_bytes", return_value=b"firefox"), patch.object(equalizer.os, "kill") as kill:
            self.eq.reap_stale()
        kill.assert_not_called()
        self.assertFalse(self.eq.pidfile.exists())


if __name__ == "__main__":
    unittest.main()
