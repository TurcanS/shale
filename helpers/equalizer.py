"""Ten-band PipeWire filter-chain equalizer, inserted before the default sink as a WirePlumber smart filter."""
import asyncio
import json
import math
import os
from pathlib import Path
import shutil
import signal
import subprocess

BANDS = (31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000)
LIMIT = 12
# One-octave peaking filters for octave-spaced centre frequencies.
Q = 1.41
NODE = "shale_eq"
PRESETS = {
    "flat": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    "bass": [6, 5.5, 4.5, 3, 1, 0, 0, 0, 0, 0],
    "vocal": [-2, -2, -1, 0.5, 2.5, 3.5, 3, 2, 0.5, -1],
    "treble": [0, 0, 0, 0, 0, 0.5, 2, 3.5, 5, 6],
    "loudness": [5, 4, 2, 0, -1, -1, 0, 1.5, 3.5, 4.5],
}


def validate(bands):
    if not isinstance(bands, list) or len(bands) != len(BANDS) or any(
            type(value) not in (int, float) or not math.isfinite(value) or abs(value) > LIMIT for value in bands):
        raise ValueError("Equalizer bands must be ten values between -12 and 12 dB.")
    return [round(float(value) * 2) / 2 for value in bands]


def preamp(bands):
    """Linear gain that removes the largest boost so the chain cannot clip."""
    return 10 ** (-max(0.0, *bands) / 20)


def render_config(bands):
    nodes = ['{ type = builtin name = preamp label = mixer control = { "Gain 1" = %.4f } }' % preamp(bands)]
    nodes += ['{ type = builtin name = band_%d label = bq_peaking control = { "Freq" = %.1f "Q" = %.2f "Gain" = %.1f } }'
              % (index + 1, frequency, Q, gain) for index, (frequency, gain) in enumerate(zip(BANDS, bands))]
    links = ['{ output = "preamp:Out" input = "band_1:In" }']
    links += ['{ output = "band_%d:Out" input = "band_%d:In" }' % (index, index + 1) for index in range(1, len(BANDS))]
    return """context.properties = { log.level = 0 }
context.spa-libs = {
    audio.convert.* = audioconvert/libspa-audioconvert
    support.*       = support/libspa-support
}
context.modules = [
    { name = libpipewire-module-rt args = { } flags = [ ifexists nofail ] }
    { name = libpipewire-module-protocol-native }
    { name = libpipewire-module-client-node }
    { name = libpipewire-module-adapter }
    { name = libpipewire-module-filter-chain
        args = {
            node.description = "Shale equalizer"
            media.name = "Shale equalizer"
            filter.graph = {
                nodes = [
                    %s
                ]
                links = [
                    %s
                ]
                inputs = [ "preamp:In 1" ]
                outputs = [ "band_%d:Out" ]
            }
            audio.channels = 2
            audio.position = [ FL FR ]
            capture.props = {
                node.name = "%s"
                media.class = Audio/Sink
                filter.smart = true
                filter.smart.name = "shale-eq"
            }
            playback.props = {
                node.name = "%s.output"
                node.passive = true
                node.dont-remix = true
            }
        }
    }
]
""" % ("\n                    ".join(nodes), "\n                    ".join(links), len(BANDS), NODE, NODE)


def param_string(bands):
    params = ['"preamp:Gain 1" %.4f' % preamp(bands)]
    params += ['"band_%d:Gain" %.1f' % (index + 1, gain) for index, gain in enumerate(bands)]
    return "{ params = [ " + " ".join(params) + " ] }"


class Equalizer:
    def __init__(self, runtime):
        self.runtime = Path(runtime)
        self.process = None
        self.node = None
        self.bands = None

    @property
    def conf(self):
        return self.runtime / "equalizer.conf"

    @property
    def pidfile(self):
        return self.runtime / "equalizer.pid"

    @property
    def running(self):
        return self.process is not None and self.process.poll() is None

    def status(self):
        return {"enabled": self.running, "bands": self.bands if self.running else None}

    def reap_stale(self):
        """Stop a filter left behind by a helper that did not exit cleanly."""
        try:
            pid = int(self.pidfile.read_text())
            if str(self.conf).encode() in Path(f"/proc/{pid}/cmdline").read_bytes():
                os.kill(pid, signal.SIGTERM)
        except (OSError, ValueError):
            pass
        self.pidfile.unlink(missing_ok=True)

    async def start(self, run, bands):
        await asyncio.to_thread(self.stop)
        self.reap_stale()
        if not shutil.which("pipewire"):
            raise RuntimeError("Install PipeWire to use the equalizer.")
        self.runtime.mkdir(parents=True, exist_ok=True, mode=0o700)
        descriptor = os.open(self.conf, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(descriptor, "w") as stream:
            stream.write(render_config(bands))
        self.process = subprocess.Popen(["pipewire", "-c", str(self.conf)], stdin=subprocess.DEVNULL,
                                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.pidfile.write_text(str(self.process.pid))
        self.bands = bands
        try:
            for _ in range(30):
                await asyncio.sleep(0.1)
                if not self.running:
                    raise RuntimeError("PipeWire could not start the equalizer.")
                if await self.find(run) is not None:
                    return
            raise RuntimeError("The equalizer did not appear in PipeWire.")
        except BaseException:
            # Any failure (pw-dump timing out, bad output, cancellation) must not leave the filter
            # running while the shell reports the equalizer as off.
            await asyncio.to_thread(self.stop)
            raise

    def stop(self):
        # Waits up to two seconds; async callers run it in a thread.
        if self.process is not None:
            if self.process.poll() is None:
                self.process.terminate()
                try:
                    self.process.wait(2)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait()
            self.process = None
            self.pidfile.unlink(missing_ok=True)
        self.node = None
        self.bands = None

    async def find(self, run):
        objects = json.loads((await run("pw-dump", timeout=5)).decode())
        self.node = next((item["id"] for item in objects if item.get("type") == "PipeWire:Interface:Node"
                          and ((item.get("info") or {}).get("props") or {}).get("node.name") == NODE), None)
        return self.node

    async def update(self, run, bands):
        for _ in range(2):
            if self.node is None and await self.find(run) is None:
                continue
            try:
                await run("pw-cli", "set-param", str(self.node), "Props", param_string(bands), timeout=5)
                self.bands = bands
                return
            except Exception:
                self.node = None
        raise RuntimeError("Could not update the equalizer.")
