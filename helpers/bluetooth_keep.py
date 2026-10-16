"""Keeps the shell's Bluetooth state honest and connected.

When headphones switch off, BlueZ drops their audio at once but keeps the radio link "Connected" until the
link supervision timeout, about 20 seconds later, so everything reading BlueZ shows a device that is gone.
A connected device that had audio endpoints and has lost all of them for a few seconds is disconnected here,
which ends the link straight away.

Devices marked for auto-connect are connected when Bluetooth turns on, at login, after waking from sleep and
after unlocking, then every 30 seconds for three minutes while any is still missing. A device disconnected by
hand is left alone until the next wake, login or Bluetooth start."""
import asyncio
import re
import sys
import time

ADDRESS = re.compile(r"^[0-9A-F]{2}(:[0-9A-F]{2}){5}$")
DEVICE = "org.bluez.Device1"
ADAPTER = "org.bluez.Adapter1"
# The objects BlueZ keeps under a device while its audio profiles are up.
MEDIA = ("org.bluez.MediaEndpoint1", "org.bluez.MediaTransport1")


def plain(value):
    """A D-Bus Variant's value, or the value itself."""
    return getattr(value, "value", value)


class Keeper:
    def __init__(self, connect, disconnect, wanted, stale_after=4, retry_every=30, window=180,
                 clock=time.monotonic, log=lambda text: print(text, file=sys.stderr, flush=True)):
        # connect(path) and disconnect(path) are coroutines; wanted() lists the auto-connect addresses.
        self.connect, self.disconnect, self.wanted = connect, disconnect, wanted
        self.stale_after, self.retry_every, self.window = stale_after, retry_every, window
        self.clock, self.log = clock, log
        self.devices = {}   # path: {"address", "connected", "paired", "adapter"}
        self.adapters = {}  # path: powered
        self.media = {}     # device path: the media objects under it
        self.had_media = set()
        self.held = set()
        self.until = 0
        self.stale_checks = {}
        self.retrying = None
        self.nudge = asyncio.Event()

    # What BlueZ reports.
    def load(self, objects):
        """Starts over from GetManagedObjects: {path: {interface: {property: value}}}."""
        self.devices.clear()
        self.adapters.clear()
        self.media.clear()
        self.had_media.clear()
        for path, interfaces in objects.items():
            self.added(path, interfaces)

    def added(self, path, interfaces):
        if ADAPTER in interfaces:
            self.adapters[path] = bool(plain(interfaces[ADAPTER].get("Powered", False)))
        if DEVICE in interfaces:
            props = interfaces[DEVICE]
            self.devices[path] = {"address": str(plain(props.get("Address", ""))).upper(), "connected": bool(plain(props.get("Connected", False))),
                                  "paired": bool(plain(props.get("Paired", False))), "adapter": str(plain(props.get("Adapter", "")))}
        if any(name in interfaces for name in MEDIA):
            device = self.owner(path)
            if device:
                self.media.setdefault(device, set()).add(path)
                self.had_media.add(device)
                self.cancel_stale(device)

    def removed(self, path, interfaces):
        if ADAPTER in interfaces:
            self.adapters.pop(path, None)
        if DEVICE in interfaces:
            self.devices.pop(path, None)
            self.media.pop(path, None)
            self.had_media.discard(path)
            self.cancel_stale(path)
            return
        if any(name in interfaces for name in MEDIA):
            device = self.owner(path)
            if device and device in self.media:
                self.media[device].discard(path)
                if not self.media[device] and self.devices.get(device, {}).get("connected") and device in self.had_media:
                    self.cancel_stale(device)
                    self.stale_checks[device] = asyncio.ensure_future(self.close_if_stale(device))

    def changed(self, path, interface, changes):
        changes = {key: plain(value) for key, value in changes.items()}
        if interface == ADAPTER and "Powered" in changes:
            was = self.adapters.get(path, False)
            self.adapters[path] = bool(changes["Powered"])
            if self.adapters[path] and not was:
                self.trigger("Bluetooth turned on", fresh=True)
        if interface == DEVICE and path in self.devices:
            device = self.devices[path]
            if "Paired" in changes:
                device["paired"] = bool(changes["Paired"])
            if "Connected" in changes:
                device["connected"] = bool(changes["Connected"])
                if not device["connected"]:
                    self.media.pop(path, None)
                    self.had_media.discard(path)
                    self.cancel_stale(path)

    def owner(self, path):
        """The device a child object (an endpoint or transport) belongs to."""
        return next((device for device in self.devices if path.startswith(device + "/")), None)

    # Links left open after a device switched off.
    def cancel_stale(self, device):
        check = self.stale_checks.pop(device, None)
        if check and not check.done():
            check.cancel()

    async def close_if_stale(self, device):
        await asyncio.sleep(self.stale_after)
        self.stale_checks.pop(device, None)
        if self.devices.get(device, {}).get("connected") and not self.media.get(device):
            self.log("Bluetooth: closing the link to " + self.devices[device]["address"] + ", whose audio stopped")
            try:
                await self.disconnect(device)
            except Exception:
                pass  # already gone

    # Auto-connect.
    def path_of(self, address):
        return next((path for path, device in self.devices.items() if device["address"] == address), None)

    def hold(self, address):
        """A device disconnected by hand: auto-connect leaves it until the next wake, login or Bluetooth start."""
        self.held.add(address.upper())

    def release(self, addresses):
        self.held.difference_update(address.upper() for address in addresses)

    def missing(self):
        """Paths of the auto-connect devices to try now."""
        paths = []
        for address in self.wanted():
            path = self.path_of(address)
            device = self.devices.get(path)
            if (device and device["paired"] and not device["connected"] and address not in self.held
                    and self.adapters.get(device["adapter"], False)):
                paths.append(path)
        return paths

    def trigger(self, reason, fresh=False):
        """Opens a three-minute window of attempts. `fresh` (login, wake, Bluetooth start) also forgets holds."""
        if fresh:
            self.held.clear()
        self.until = self.clock() + self.window
        if self.retrying is None or self.retrying.done():
            self.retrying = asyncio.ensure_future(self.retry(reason))
        else:
            self.nudge.set()

    async def retry(self, reason):
        first = True
        while self.clock() < self.until:
            for path in self.missing():
                if first:
                    self.log("Bluetooth: auto-connecting " + self.devices[path]["address"] + " (" + reason + ")")
                try:
                    await self.connect(path)
                except Exception:
                    pass  # switched off or out of range; the next attempt may find it
            first = False
            if not self.missing():
                return
            self.nudge.clear()
            try:
                await asyncio.wait_for(self.nudge.wait(), min(self.retry_every, max(0.1, self.until - self.clock())))
            except asyncio.TimeoutError:
                pass

    def stop(self):
        for check in list(self.stale_checks.values()):
            check.cancel()
        self.stale_checks.clear()
        if self.retrying and not self.retrying.done():
            self.retrying.cancel()
