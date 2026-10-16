import asyncio
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "helpers"))
import bluetooth_keep as bk

ADAPTER = "/org/bluez/hci0"
HEADPHONES = ADAPTER + "/dev_A8_E6_E8_5A_B4_71"
KEYBOARD = ADAPTER + "/dev_11_22_33_44_55_66"


def device(address, connected, paired=True):
    return {bk.DEVICE: {"Address": address, "Connected": connected, "Paired": paired, "Adapter": ADAPTER}}


class Clock:
    def __init__(self):
        self.now = 0.0

    def __call__(self):
        return self.now


class KeeperTests(unittest.IsolatedAsyncioTestCase):
    def make(self, wanted=(), **options):
        self.calls = []
        self.clock = Clock()

        async def connect(path):
            self.calls.append(("connect", path))
            if self.connect_works:
                self.keeper.changed(path, bk.DEVICE, {"Connected": True})
            else:
                raise RuntimeError("Page timeout")

        async def disconnect(path):
            self.calls.append(("disconnect", path))
            self.keeper.changed(path, bk.DEVICE, {"Connected": False})

        self.connect_works = True
        self.keeper = bk.Keeper(connect, disconnect, lambda: list(wanted), clock=self.clock, log=lambda text: None, **options)
        self.keeper.load({ADAPTER: {bk.ADAPTER: {"Powered": True}},
                          HEADPHONES: device("A8:E6:E8:5A:B4:71", True),
                          HEADPHONES + "/sep1": {"org.bluez.MediaEndpoint1": {}},
                          HEADPHONES + "/sep2/fd0": {"org.bluez.MediaTransport1": {}},
                          KEYBOARD: device("11:22:33:44:55:66", False)})
        return self.keeper

    async def test_switched_off_headphones_are_disconnected_once_their_audio_is_gone(self):
        keeper = self.make(stale_after=0.01)
        keeper.removed(HEADPHONES + "/sep2/fd0", ["org.bluez.MediaTransport1"])
        keeper.removed(HEADPHONES + "/sep1", ["org.bluez.MediaEndpoint1"])
        await asyncio.sleep(0.05)
        self.assertEqual(self.calls, [("disconnect", HEADPHONES)])

    async def test_audio_coming_back_keeps_the_link(self):
        keeper = self.make(stale_after=0.05)
        keeper.removed(HEADPHONES + "/sep2/fd0", ["org.bluez.MediaTransport1"])
        keeper.removed(HEADPHONES + "/sep1", ["org.bluez.MediaEndpoint1"])
        keeper.added(HEADPHONES + "/sep1", {"org.bluez.MediaEndpoint1": {}})
        await asyncio.sleep(0.1)
        self.assertEqual(self.calls, [])

    async def test_a_device_without_audio_is_never_closed(self):
        keeper = self.make(stale_after=0.01)
        keeper.changed(KEYBOARD, bk.DEVICE, {"Connected": True})
        keeper.removed(KEYBOARD + "/something", ["org.bluez.MediaEndpoint1"])
        await asyncio.sleep(0.05)
        self.assertEqual(self.calls, [])

    async def test_auto_connect_tries_the_missing_devices_only(self):
        keeper = self.make(wanted=["11:22:33:44:55:66", "A8:E6:E8:5A:B4:71"])
        keeper.trigger("login", fresh=True)
        await asyncio.sleep(0.01)
        self.assertEqual(self.calls, [("connect", KEYBOARD)])

    async def test_auto_connect_keeps_trying_within_its_window(self):
        keeper = self.make(wanted=["11:22:33:44:55:66"], retry_every=0.01, window=1)
        self.connect_works = False
        keeper.trigger("login", fresh=True)
        await asyncio.sleep(0.05)
        tries = len(self.calls)
        self.assertGreater(tries, 2)
        self.clock.now = 2  # the window has passed
        await asyncio.sleep(0.05)
        self.assertLessEqual(len(self.calls), tries + 1)
        self.assertTrue(keeper.retrying.done())

    async def test_a_device_disconnected_by_hand_waits_for_the_next_wake(self):
        keeper = self.make(wanted=["11:22:33:44:55:66"])
        keeper.hold("11:22:33:44:55:66")
        keeper.trigger("unlocked")
        await asyncio.sleep(0.01)
        self.assertEqual(self.calls, [])
        keeper.trigger("woke from sleep", fresh=True)
        await asyncio.sleep(0.01)
        self.assertEqual(self.calls, [("connect", KEYBOARD)])

    async def test_bluetooth_turning_on_starts_auto_connect(self):
        keeper = self.make(wanted=["11:22:33:44:55:66"])
        keeper.changed(ADAPTER, bk.ADAPTER, {"Powered": False})
        keeper.changed(ADAPTER, bk.ADAPTER, {"Powered": True})
        await asyncio.sleep(0.01)
        self.assertEqual(self.calls, [("connect", KEYBOARD)])

    async def test_nothing_is_tried_while_bluetooth_is_off(self):
        keeper = self.make(wanted=["11:22:33:44:55:66"])
        keeper.changed(ADAPTER, bk.ADAPTER, {"Powered": False})
        keeper.trigger("unlocked")
        await asyncio.sleep(0.01)
        self.assertEqual(self.calls, [])


if __name__ == "__main__":
    unittest.main()
