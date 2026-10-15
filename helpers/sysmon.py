"""System monitor samples from /proc and /sys: CPU, memory, disks, network, GPUs, temperatures and fans.

The sampler keeps the previous counters, so each sample reports rates since the last one (zero the first time, and
after a pause). It also keeps the last few minutes of what the graphs show, filled by a cheap background tick while
the panel is closed, so the panel opens on recent history. Nothing here wakes a device that is runtime-suspended.
Everything is read from the paths it is given, so tests run it against a fake tree."""
import asyncio
import collections
import os
from pathlib import Path
import time

# Block devices that are not disks of their own: loop files, RAM disks, zram swap, optical and floppy drives,
# and device-mapper/RAID layers, whose I/O is already counted on the disks underneath.
VIRTUAL_DISKS = ("loop", "ram", "zram", "sr", "fd", "dm-", "md", "nbd")
CPU_SENSORS = ("coretemp", "k10temp", "zenpower", "cpu_thermal", "soc_thermal")
CPU_PACKAGE = ("package id 0", "tctl", "tdie", "cpu")
VENDORS = {"0x10de": "nvidia", "0x1002": "amd", "0x8086": "intel"}
NVIDIA_QUERY = ["nvidia-smi", "--query-gpu=pci.bus_id,name,utilization.gpu,memory.used,memory.total,temperature.gpu",
                "--format=csv,noheader,nounits"]


def read(path, default=""):
    try:
        return Path(path).read_text().strip()
    except (OSError, UnicodeDecodeError):
        return default


def number(path, default=None):
    try:
        return float(read(path))
    except ValueError:
        return default


def label(text):
    """cpu_fan → CPU fan"""
    words = [word.upper() if word.lower() in ("cpu", "gpu", "pch", "soc") else word for word in text.replace("_", " ").split()]
    if words and words[0].islower():
        words[0] = words[0].capitalize()
    return " ".join(words)


def gpu_level(gpu):
    """What a GPU's graph shows: its usage, else Intel's clock as a share of its maximum. 0 asleep, None when unknown
    (an NVIDIA card that isn't being queried)."""
    if gpu["state"] == "asleep":
        return 0
    if gpu["usage"] is not None:
        return gpu["usage"]
    if gpu["frequency"] is not None and gpu["frequencyMax"]:
        return round(100 * gpu["frequency"] / gpu["frequencyMax"], 1)
    return None


def gpu_name(vendor_id, device_id, pci_ids):
    """'GeForce RTX 3050 Mobile' for 10de:25a5, from hwdata's pci.ids; a plain vendor name otherwise."""
    vendor = {"nvidia": "NVIDIA", "amd": "AMD", "intel": "Intel"}.get(VENDORS.get(vendor_id, ""), "")
    fallback = vendor + " graphics" if vendor else "Graphics"
    want_vendor, want_device = vendor_id.removeprefix("0x").lower(), device_id.removeprefix("0x").lower()
    try:
        with open(pci_ids, encoding="utf-8", errors="replace") as ids:
            inside = False
            for line in ids:
                if line.startswith("#") or not line.strip():
                    continue
                if not line.startswith("\t"):
                    inside = line[:4].lower() == want_vendor
                elif inside and not line.startswith("\t\t") and line[1:5].lower() == want_device:
                    name = line[5:].strip()
                    if "[" in name and "]" in name:
                        name = name[name.index("[") + 1:name.rindex("]")]
                    return name if name.lower().startswith(vendor.lower()) or not vendor else vendor + " " + name
    except OSError:
        pass
    return fallback


class Sampler:
    def __init__(self, proc=Path("/proc"), sys=Path("/sys"), run=None, clock=time.monotonic, statvfs=os.statvfs,
                 pci_ids=Path("/usr/share/hwdata/pci.ids"), nvidia_interval=2.0, sensor_interval=3.0, max_gap=10.0, window=300.0):
        self.proc, self.sys, self.run, self.clock, self.statvfs = Path(proc), Path(sys), run, clock, statvfs
        self.pci_ids, self.nvidia_interval, self.sensor_interval, self.max_gap = pci_ids, nvidia_interval, sensor_interval, max_gap
        self.window = window
        # Graph series ("cpu", "disk:nvme0n1", "net-rx:wlan0"…) → (time, value), oldest first. None breaks the line.
        self.history = {}
        self.sampled = None
        self.previous = None
        self.names = {}
        self.nvidia = (None, {})
        self.cached_sensors = (None, None)
        self.lock = asyncio.Lock()

    async def sample(self, nvidia=False, history=False):
        """One sample, with the graph values it added as `recorded`, and every kept graph point as `history` when
        asked. `nvidia` asks nvidia-smi for usage too: every query resets the card's idle timer, so the panel only
        asks while that GPU is the one on screen."""
        async with self.lock:
            now = self.sampled = self.clock()
            # Plain file reads, but an NVMe temperature takes a drive command (~25 ms): off the event loop.
            result = await asyncio.to_thread(self.collect, now)
            for gpu in result["gpus"]:
                bus, device = gpu.pop("bus"), gpu.pop("device")
                # Checked again right before the query: nvidia-smi would wake a card that has just gone to sleep.
                if nvidia and gpu["vendor"] == "nvidia" and gpu["state"] == "active" \
                        and read(Path(device) / "power/runtime_status", "active") != "suspended":
                    gpu.update((await self.nvidia_values(now)).get(bus, {}))
            result["time"], result["recorded"] = self.record(now, result)
            if history:
                result["history"] = {key: list(points) for key, points in self.history.items()}
            return result

    async def tick(self):
        """Background sampling while the panel is closed: only the cheap counters the graphs need, never sensors,
        mounts or nvidia-smi. Skipped while the panel is sampling on its own (every second or two)."""
        async with self.lock:
            now = self.clock()
            if self.sampled is not None and 0 <= now - self.sampled < 3:
                return False
            self.record(now, self.collect(now, full=False))
            return True

    def record(self, now, result):
        """Adds this sample's graph values to the history and drops what has scrolled out of the window."""
        values = {"cpu": result["cpu"]["usage"],
                  "memory": round(100 * result["memory"]["used"] / result["memory"]["total"], 1) if result["memory"]["total"] else None}
        for disk in result["disks"]:
            values["disk:" + disk["name"]] = disk["busy"]
        for link in result["network"]:
            values["net-rx:" + link["name"]], values["net-tx:" + link["name"]] = link["rx"], link["tx"]
        for gpu in result["gpus"]:
            values["gpu:" + gpu["id"]] = gpu_level(gpu)
        # Rates restarted (first sample, or after the lock screen or suspend): break every line instead of drawing
        # a dip to zero or a straight line across the gap.
        if not result.pop("fresh"):
            values = dict.fromkeys(values)
        time, cutoff = round(now, 2), now - self.window
        for key, value in values.items():
            self.history.setdefault(key, collections.deque(maxlen=512)).append((time, value))
        for key in list(self.history):
            points = self.history[key]
            while points and points[0][0] < cutoff:
                points.popleft()
            if not points:
                del self.history[key]
        return time, values

    def collect(self, now, full=True):
        counters = {"cpu": self.cpu_times(), "disks": self.disk_counters(), "network": self.net_counters()}
        previous, elapsed = self.previous, 0.0
        # After a pause the counters span the whole gap; start over instead of reporting its average.
        if previous and (now - previous[0] > self.max_gap or now < previous[0]):
            previous = None
        if previous:
            elapsed = max(0.0, now - previous[0])
        # Rates over a fraction of a second are mostly noise (a tick just before the panel's sample): measure
        # those against the older counters, and keep them for the next sample too.
        if not previous or elapsed >= 0.5:
            self.previous = (now, counters)
        before = previous[1] if previous else None
        if not full:
            nothing = {"cpu": None, "devices": {}, "fans": {}}
            return {"fresh": before is not None, "cpu": {"usage": self.usage(counters["cpu"], before and before["cpu"], "cpu")},
                    "memory": self.memory(), "disks": self.disks(counters["disks"], before and before["disks"], elapsed, nothing, full=False),
                    "network": self.network(counters["network"], before and before["network"], elapsed), "gpus": self.gpus(nothing)}
        checked, sensors = self.cached_sensors
        if checked is None or now - checked >= self.sensor_interval:
            sensors = self.sensors()
            self.cached_sensors = (now, sensors)
        return {
            "time": now,
            "fresh": before is not None,
            "uptime": self.uptime(),
            "cpu": self.cpu(counters["cpu"], before and before["cpu"], sensors),
            "memory": self.memory(),
            "disks": self.disks(counters["disks"], before and before["disks"], elapsed, sensors),
            "network": self.network(counters["network"], before and before["network"], elapsed),
            "gpus": self.gpus(sensors),
            "fans": [fan for fans in sensors["fans"].values() for fan in fans],
        }

    def uptime(self):
        try:
            return float(read(self.proc / "uptime").split()[0])
        except (IndexError, ValueError):
            return 0.0

    # CPU
    def cpu_times(self):
        times = {}
        for line in read(self.proc / "stat").splitlines():
            if line.startswith("cpu"):
                name, *values = line.split()
                values = [int(v) for v in values[:8]] + [0] * (8 - len(values[:8]))
                # idle + iowait count as idle time.
                times[name] = (sum(values), values[3] + values[4])
        return times

    def usage(self, times, before, name):
        if not before or name not in before or name not in times:
            return 0.0
        total, idle = times[name][0] - before[name][0], times[name][1] - before[name][1]
        return round(max(0.0, min(100.0, 100.0 * (total - idle) / total)), 1) if total > 0 else 0.0

    def cpu(self, times, before, sensors):
        usage = lambda name: self.usage(times, before, name)
        cores = sorted((name for name in times if name != "cpu"), key=lambda name: int(name[3:]) if name[3:].isdigit() else 0)
        if "model" not in self.names:
            model = ""
            for line in read(self.proc / "cpuinfo").splitlines():
                key, _, value = line.partition(":")
                if key.strip() in ("model name", "Model", "Hardware") and value.strip():
                    model = " ".join(value.split())
                    break
            self.names["model"] = model or "Processor"
        frequencies = [number(path) for path in sorted((self.sys / "devices/system/cpu").glob("cpu[0-9]*/cpufreq/scaling_cur_freq"))]
        frequencies = [f for f in frequencies if f]
        load = read(self.proc / "loadavg").split()
        try:
            averages = [float(value) for value in load[:3]]
            threads = int(load[3].split("/")[1])
        except (IndexError, ValueError):
            averages, threads = [0.0, 0.0, 0.0], 0
        try:
            processes = sum(1 for entry in os.scandir(self.proc) if entry.name.isdigit())
        except OSError:
            processes = 0
        return {"available": bool(times), "model": self.names["model"], "usage": usage("cpu"), "cores": [usage(name) for name in cores],
                "frequency": round(sum(frequencies) / len(frequencies) / 1000) if frequencies else None,
                "load": averages, "processes": processes, "threads": threads, "temperature": sensors["cpu"]}

    # Memory
    def memory(self):
        info = {}
        for line in read(self.proc / "meminfo").splitlines():
            key, _, value = line.partition(":")
            try:
                info[key] = int(value.split()[0]) * 1024
            except (IndexError, ValueError):
                continue
        total = info.get("MemTotal", 0)
        available = info.get("MemAvailable", info.get("MemFree", 0))
        return {"available": total > 0, "total": total, "used": max(0, total - available), "free": available,
                "cached": info.get("Cached", 0) + info.get("Buffers", 0) + info.get("SReclaimable", 0),
                "swapTotal": info.get("SwapTotal", 0), "swapUsed": max(0, info.get("SwapTotal", 0) - info.get("SwapFree", 0))}

    # Disks
    def disk_counters(self):
        counters = {}
        for line in read(self.proc / "diskstats").splitlines():
            fields = line.split()
            if len(fields) < 13:
                continue
            name = fields[2]
            if name.startswith(VIRTUAL_DISKS) or not (self.sys / "block" / name).is_dir():
                continue
            if number(self.sys / "block" / name / "size", 0) == 0:
                continue
            # Sectors are always 512 bytes here, whatever the device's own sector size.
            counters[name] = (int(fields[5]) * 512, int(fields[9]) * 512, int(fields[12]))
        return counters

    def disk_of(self, device, depth=0):
        """The whole disk a block device (partition, or a device-mapper/RAID layer) lives on."""
        name = os.path.basename(os.path.realpath(device)) if device.startswith("/") else device
        node = self.sys / "class/block" / name
        if (self.sys / "block" / name).is_dir():
            slaves = sorted(p.name for p in (self.sys / "block" / name / "slaves").glob("*"))
            if slaves and depth < 4:
                return self.disk_of(slaves[0], depth + 1)
            return name
        if (node / "partition").exists():
            return Path(os.path.realpath(node)).parent.name
        return None

    def mounts(self):
        found = {}
        for line in read(self.proc / "self/mounts").splitlines():
            fields = line.split()
            if len(fields) < 3 or not fields[0].startswith("/dev/"):
                continue
            device, path = fields[0], fields[1].replace("\\040", " ")
            disk = self.disk_of(device)
            # Bind mounts and btrfs subvolumes show one filesystem several times; keep the shortest path.
            if disk and (device not in found or len(path) < len(found[device][1])):
                found[device] = (disk, path)
        result = {}
        for disk, path in sorted(found.values(), key=lambda item: item[1]):
            try:
                stat = self.statvfs(path)
            except OSError:
                continue
            total = stat.f_blocks * stat.f_frsize
            if total > 0:
                result.setdefault(disk, []).append({"path": path, "total": total, "used": (stat.f_blocks - stat.f_bfree) * stat.f_frsize})
        return result

    def disks(self, counters, before, elapsed, sensors, full=True):
        mounts = self.mounts() if full else {}
        disks = []
        for name, (_, _, ticks) in sorted(counters.items()):
            rate = lambda index: round((counters[name][index] - before[name][index]) / elapsed) if before and name in before and elapsed > 0 else 0
            busy = min(100.0, round(100.0 * (ticks - before[name][2]) / (elapsed * 1000), 1)) if before and name in before and elapsed > 0 else 0.0
            if name not in self.names:
                self.names[name] = " ".join(read(self.sys / "block" / name / "device/model").split()) or name
            device = os.path.realpath(self.sys / "block" / name / "device")
            disks.append({"name": name, "model": self.names[name], "read": max(0, rate(0)), "write": max(0, rate(1)), "busy": max(0.0, busy),
                          "temperature": sensors["devices"].get(device), "mounts": mounts.get(name, [])})
        return disks

    # Network
    def net_counters(self):
        counters = {}
        for line in read(self.proc / "net/dev").splitlines()[2:]:
            name, _, values = line.partition(":")
            name, values = name.strip(), values.split()
            # Only real adapters: lo, bridges, veth, tun and other virtual links have no device.
            if len(values) < 9 or not (self.sys / "class/net" / name / "device").exists():
                continue
            counters[name] = (int(values[0]), int(values[8]))
        return counters

    def network(self, counters, before, elapsed):
        links = []
        for name in sorted(counters):
            rate = lambda index: max(0, round((counters[name][index] - before[name][index]) / elapsed)) if before and name in before and elapsed > 0 else 0
            base = self.sys / "class/net" / name
            links.append({"name": name, "kind": "wifi" if (base / "wireless").exists() or (base / "phy80211").exists() else "ethernet",
                          "up": read(base / "operstate") == "up", "rx": rate(0), "tx": rate(1)})
        return links

    # Temperatures and fans
    def sensors(self):
        cpu, devices, fans = None, {}, {}
        for hwmon in sorted((self.sys / "class/hwmon").glob("hwmon*")):
            # Reading a sleeping device's sensors (a laptop dGPU) would wake it.
            if read(hwmon / "device/power/runtime_status") == "suspended":
                continue
            name = read(hwmon / "name")
            temperatures = []
            for path in sorted(hwmon.glob("temp*_input")):
                value = number(path)
                if value is not None:
                    temperatures.append((read(path.with_name(path.name.replace("_input", "_label"))).lower(), value / 1000))
            for path in sorted(hwmon.glob("fan*_input")):
                value = number(path)
                if value is not None:
                    text = read(path.with_name(path.name.replace("_input", "_label"))) or name + " " + path.name[3:-6]
                    fans.setdefault(name, []).append({"label": label(text), "rpm": round(value)})
            if not temperatures:
                continue
            preferred = next((value for text, value in temperatures if text in CPU_PACKAGE), None)
            hottest = max(value for _, value in temperatures)
            if name in CPU_SENSORS and cpu is None:
                cpu = round(preferred if preferred is not None else hottest, 1)
            elif (hwmon / "device").exists():
                devices[os.path.realpath(hwmon / "device")] = round(next((v for t, v in temperatures if t in ("composite", "edge")), hottest), 1)
        if cpu is None:
            for zone in sorted((self.sys / "class/thermal").glob("thermal_zone*")):
                if read(zone / "type") in ("x86_pkg_temp", "TCPU", "cpu-thermal"):
                    value = number(zone / "temp")
                    if value is not None:
                        cpu = round(value / 1000, 1)
                        break
        return {"cpu": cpu, "devices": devices, "fans": fans}

    # GPUs
    def gpus(self, sensors):
        gpus = []
        for card in sorted((self.sys / "class/drm").glob("card[0-9]*")):
            if not card.name[4:].isdigit():
                continue
            device = card / "device"
            vendor = VENDORS.get(read(device / "vendor"))
            if not vendor:
                continue
            key = (read(device / "vendor"), read(device / "device"))
            if key not in self.names:
                self.names[key] = gpu_name(*key, self.pci_ids)
            status = read(device / "power/runtime_status", "active")
            gpu = {"id": card.name, "vendor": vendor, "name": self.names[key], "state": "asleep" if status == "suspended" else "active",
                   "usage": None, "memoryUsed": None, "memoryTotal": None, "temperature": sensors["devices"].get(os.path.realpath(device)),
                   "frequency": None, "frequencyMax": None, "bus": os.path.basename(os.path.realpath(device)).lower(), "device": str(device)}
            # A sleeping card is left alone: even reading its sysfs counters can wake it.
            if gpu["state"] == "asleep":
                gpus.append(gpu)
                continue
            if vendor == "amd":
                gpu.update(usage=number(device / "gpu_busy_percent"), memoryUsed=number(device / "mem_info_vram_used"),
                           memoryTotal=number(device / "mem_info_vram_total"))
            elif vendor == "intel":
                gpu.update(frequency=number(card / "gt_act_freq_mhz"), frequencyMax=number(card / "gt_RP0_freq_mhz"))
            gpus.append(gpu)
        return gpus

    async def nvidia_values(self, now):
        checked, values = self.nvidia
        if checked is not None and now - checked < self.nvidia_interval:
            return values
        values = {}
        if self.run:
            try:
                output = (await self.run(*NVIDIA_QUERY, timeout=3)).decode()
            except Exception:
                output = ""
            for line in output.splitlines():
                fields = [field.strip() for field in line.split(",")]
                if len(fields) < 6:
                    continue
                as_number = lambda text: float(text) if text.replace(".", "", 1).isdigit() else None
                # nvidia-smi prints 00000000:01:00.0; sysfs names the device 0000:01:00.0.
                bus = fields[0].lower()[-12:]
                memory = [as_number(fields[3]), as_number(fields[4])]
                values[bus] = {"name": fields[1] or None, "usage": as_number(fields[2]),
                               "memoryUsed": memory[0] * 1048576 if memory[0] is not None else None,
                               "memoryTotal": memory[1] * 1048576 if memory[1] is not None else None,
                               "temperature": as_number(fields[5])}
                values[bus] = {key: value for key, value in values[bus].items() if value is not None}
        self.nvidia = (now, values)
        return values
