"""The system monitor's sampler, run against a fake /proc and /sys."""
import asyncio
import os
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "helpers"))
import sysmon

PCI_IDS = """# pci.ids excerpt
10de  NVIDIA Corporation
# a comment inside the vendor block
\t25a5  GA107M [GeForce RTX 3050 Mobile]
\t\t1043 16ed  Some laptop
1002  Advanced Micro Devices, Inc. [AMD/ATI]
\t73bf  Navi 21 [Radeon RX 6800/6800 XT / 6900 XT]
8086  Intel Corporation
\t9a68  TigerLake-H GT1 [UHD Graphics]
"""


class Clock:
    def __init__(self):
        self.now = 100.0

    def __call__(self):
        return self.now


class SamplerTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.proc, self.sys = self.root / "proc", self.root / "sys"
        self.clock = Clock()
        self.calls = []
        self.write("proc/uptime", "3600.50 7000.00")
        self.write("proc/loadavg", "0.50 0.40 0.30 2/533 1234")
        self.write("proc/cpuinfo", "processor\t: 0\nmodel name\t: Test CPU  @ 2.70GHz\n")
        self.write("proc/meminfo", "MemTotal: 1000 kB\nMemFree: 100 kB\nMemAvailable: 600 kB\nBuffers: 10 kB\nCached: 200 kB\n"
                   "SReclaimable: 30 kB\nSwapTotal: 500 kB\nSwapFree: 400 kB\n")
        for pid in ("1", "42", "self"):
            (self.proc / pid).mkdir(parents=True, exist_ok=True)
        self.stat(cpu=(100, 0, 100, 800, 0), cores=[(50, 0, 50, 400, 0)] * 2 + [(0, 0, 0, 0, 0)] * 9)
        for index, khz in ((0, 1000000), (1, 3000000)):
            self.write(f"sys/devices/system/cpu/cpu{index}/cpufreq/scaling_cur_freq", str(khz))
        self.pci = self.root / "pci.ids"
        self.pci.write_text(PCI_IDS)

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, path, text):
        path = self.root / path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def link(self, path, target):
        path = self.root / path
        path.parent.mkdir(parents=True, exist_ok=True)
        (self.root / target).mkdir(parents=True, exist_ok=True)
        path.symlink_to(self.root / target)

    def stat(self, cpu, cores):
        lines = ["cpu  " + " ".join(map(str, cpu)) + " 0 0 0"]
        lines += [f"cpu{index} " + " ".join(map(str, values)) + " 0 0 0" for index, values in enumerate(cores)]
        self.write("proc/stat", "\n".join(lines + ["intr 1 2 3", "ctxt 5"]) + "\n")

    async def fake_run(self, *command, timeout=15):
        self.calls.append(command)
        return b"00000000:01:00.0, NVIDIA GeForce RTX 3050 Laptop GPU, 37, 512, 4096, 55\n"

    def sampler(self, **options):
        statvfs = lambda path: SimpleNamespace(f_blocks=1000, f_bfree=250, f_frsize=4096)
        return sysmon.Sampler(self.proc, self.sys, run=self.fake_run, clock=self.clock, statvfs=statvfs, pci_ids=self.pci, **options)

    async def test_cpu_usage_comes_from_the_change_since_the_last_sample(self):
        sampler = self.sampler()
        first = (await sampler.sample())["cpu"]
        self.assertEqual((first["usage"], first["cores"][0]), (0.0, 0.0))
        self.assertEqual(first["model"], "Test CPU @ 2.70GHz")
        self.assertEqual(first["frequency"], 2000)
        self.assertEqual((first["load"], first["threads"], first["processes"]), ([0.5, 0.4, 0.3], 533, 2))
        # Total +200 jiffies, idle +50: 75 % busy. Cores stay in numeric order (cpu10 after cpu2).
        self.stat(cpu=(200, 0, 150, 850, 0), cores=[(150, 0, 50, 400, 0), (50, 0, 50, 500, 0)] + [(0, 0, 0, 0, 0)] * 8 + [(10, 0, 0, 0, 0)])
        self.clock.now += 1
        second = (await sampler.sample())["cpu"]
        self.assertEqual(second["usage"], 75.0)
        self.assertEqual(second["cores"][:2], [100.0, 0.0])
        self.assertEqual(second["cores"][-1], 100.0)
        self.assertEqual(len(second["cores"]), 11)

    async def test_memory(self):
        memory = (await self.sampler().sample())["memory"]
        self.assertEqual(memory, {"available": True, "total": 1024000, "used": 409600, "free": 614400, "cached": 245760,
                                  "swapTotal": 512000, "swapUsed": 102400})

    def disk_tree(self):
        self.link("sys/block/nvme0n1/device", "sys/devices/pci/nvme0")
        self.write("sys/block/nvme0n1/device/model", "SAMSUNG MZALQ512HALU-000L2   \n")
        self.write("sys/block/nvme0n1/size", "1000215216")
        self.write("sys/block/nvme0n1/nvme0n1p2/partition", "2")
        self.link("sys/class/block/nvme0n1p2", "sys/block/nvme0n1/nvme0n1p2")
        self.write("sys/block/sda/size", "0")
        self.write("sys/block/zram0/size", "8388608")
        self.write("sys/block/dm-0/size", "100")
        self.link("sys/block/dm-0/slaves/nvme0n1p2", "sys/block/nvme0n1/nvme0n1p2")
        self.write("sys/class/hwmon/hwmon3/name", "nvme")
        self.write("sys/class/hwmon/hwmon3/temp1_input", "31850")
        self.write("sys/class/hwmon/hwmon3/temp1_label", "Composite")
        self.write("sys/class/hwmon/hwmon3/temp2_input", "40000")
        self.link("sys/class/hwmon/hwmon3/device", "sys/devices/pci/nvme0")
        self.write("proc/self/mounts", "/dev/nvme0n1p2 / ext4 rw 0 0\n/dev/dm-0 /home ext4 rw 0 0\n/dev/nvme0n1p2 /var/lib/docker ext4 rw 0 0\n"
                   "proc /proc proc rw 0 0\n/dev/zram0 /tmp ext4 rw 0 0\n")

    def diskstats(self, read_sectors, written_sectors, ticks):
        line = lambda name: f" 259 0 {name} 10 0 {read_sectors} 5 10 0 {written_sectors} 5 0 {ticks} 10"
        self.write("proc/diskstats", "\n".join(line(name) for name in ("nvme0n1", "nvme0n1p2", "zram0", "dm-0", "sda", "loop0")) + "\n")

    async def test_disks_are_whole_physical_drives_with_rates_and_mounts(self):
        self.disk_tree()
        self.diskstats(1000, 2000, 100)
        sampler = self.sampler()
        first = (await sampler.sample())["disks"]
        self.assertEqual([disk["name"] for disk in first], ["nvme0n1"])
        disk = first[0]
        self.assertEqual((disk["model"], disk["read"], disk["write"], disk["busy"], disk["temperature"]),
                         ("SAMSUNG MZALQ512HALU-000L2", 0, 0, 0.0, 31.9))
        # A partition and the encrypted volume on it both belong to the drive; the bind mount keeps the shorter path.
        self.assertEqual([mount["path"] for mount in disk["mounts"]], ["/", "/home"])
        self.assertEqual(disk["mounts"][0], {"path": "/", "total": 4096000, "used": 3072000})
        self.diskstats(1000 + 4096, 2000 + 2048, 100 + 500)
        self.clock.now += 2
        disk = (await sampler.sample())["disks"][0]
        self.assertEqual((disk["read"], disk["write"], disk["busy"]), (4096 * 512 // 2, 2048 * 512 // 2, 25.0))

    async def test_network_lists_real_adapters_only(self):
        self.write("proc/net/dev", "Inter-|   Receive\n face |bytes\n"
                   "    lo: 500 5 0 0 0 0 0 0 500 5 0 0 0 0 0 0\n"
                   " wlan0: 1000 10 0 0 0 0 0 0 2000 20 0 0 0 0 0 0\n"
                   "  eth0: 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0\n"
                   "virbr0: 9 1 0 0 0 0 0 0 9 1 0 0 0 0 0 0\n")
        for name in ("wlan0", "eth0"):
            self.link(f"sys/class/net/{name}/device", f"sys/devices/pci/{name}")
        self.write("sys/class/net/wlan0/wireless/.keep", "")
        self.write("sys/class/net/wlan0/operstate", "up")
        self.write("sys/class/net/eth0/operstate", "down")
        self.write("sys/class/net/virbr0/operstate", "up")
        sampler = self.sampler()
        first = (await sampler.sample())["network"]
        self.assertEqual([(link["name"], link["kind"], link["up"]) for link in first], [("eth0", "ethernet", False), ("wlan0", "wifi", True)])
        self.write("proc/net/dev", "a\nb\n wlan0: 5000 10 0 0 0 0 0 0 2500 20 0 0 0 0 0 0\n  eth0: 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0\n")
        self.clock.now += 2
        wlan = (await sampler.sample())["network"][1]
        self.assertEqual((wlan["rx"], wlan["tx"]), (2000, 250))

    async def test_cpu_temperature_and_fans(self):
        self.write("sys/class/hwmon/hwmon6/name", "coretemp")
        self.write("sys/class/hwmon/hwmon6/temp1_input", "42000")
        self.write("sys/class/hwmon/hwmon6/temp1_label", "Package id 0")
        self.write("sys/class/hwmon/hwmon6/temp2_input", "60000")
        self.write("sys/class/hwmon/hwmon6/temp2_label", "Core 0")
        self.write("sys/class/hwmon/hwmon5/name", "asus")
        self.write("sys/class/hwmon/hwmon5/fan1_input", "3100")
        self.write("sys/class/hwmon/hwmon5/fan1_label", "cpu_fan")
        self.write("sys/class/hwmon/hwmon5/fan2_input", "0")
        sample = await self.sampler().sample()
        self.assertEqual(sample["cpu"]["temperature"], 42.0)
        self.assertEqual(sample["fans"], [{"label": "CPU fan", "rpm": 3100}, {"label": "Asus 2", "rpm": 0}])

    async def test_cpu_temperature_falls_back_to_a_thermal_zone(self):
        self.write("sys/class/thermal/thermal_zone0/type", "acpitz")
        self.write("sys/class/thermal/thermal_zone0/temp", "27000")
        self.write("sys/class/thermal/thermal_zone1/type", "x86_pkg_temp")
        self.write("sys/class/thermal/thermal_zone1/temp", "44500")
        self.assertEqual((await self.sampler().sample())["cpu"]["temperature"], 44.5)

    def gpu(self, card, vendor, device, bus, status=None):
        self.link(f"sys/class/drm/{card}/device", f"sys/devices/pci0000:00/{bus}")
        self.write(f"sys/devices/pci0000:00/{bus}/vendor", vendor + "\n")
        self.write(f"sys/devices/pci0000:00/{bus}/device", device + "\n")
        if status:
            self.write(f"sys/devices/pci0000:00/{bus}/power/runtime_status", status + "\n")
        return self.root / f"sys/devices/pci0000:00/{bus}"

    async def test_a_sleeping_nvidia_gpu_is_never_queried(self):
        self.gpu("card0", "0x10de", "0x25a5", "0000:01:00.0", "suspended")
        self.link("sys/class/drm/card0-eDP-1/device", "sys/devices/pci0000:00/other")
        gpus = (await self.sampler().sample(nvidia=True))["gpus"]
        self.assertEqual(self.calls, [])
        self.assertEqual(gpus, [{"id": "card0", "vendor": "nvidia", "name": "NVIDIA GeForce RTX 3050 Mobile", "state": "asleep", "usage": None,
                                 "memoryUsed": None, "memoryTotal": None, "temperature": None, "frequency": None, "frequencyMax": None}])

    async def test_an_active_nvidia_gpu_is_queried_at_most_every_two_seconds(self):
        self.gpu("card0", "0x10de", "0x25a5", "0000:01:00.0", "active")
        sampler = self.sampler()
        self.assertIsNone((await sampler.sample())["gpus"][0]["usage"])
        self.assertEqual(self.calls, [], "only queried when the panel asks")
        gpu = (await sampler.sample(nvidia=True))["gpus"][0]
        self.assertEqual((gpu["name"], gpu["usage"], gpu["memoryUsed"], gpu["memoryTotal"], gpu["temperature"]),
                         ("NVIDIA GeForce RTX 3050 Laptop GPU", 37.0, 512 * 1048576, 4096 * 1048576, 55.0))
        self.clock.now += 1
        await sampler.sample(nvidia=True)
        self.assertEqual(len(self.calls), 1)
        self.clock.now += 1.5
        await sampler.sample(nvidia=True)
        self.assertEqual(len(self.calls), 2)
        self.assertEqual(self.calls[0][0], "nvidia-smi")

    async def test_a_sleeping_amd_gpu_and_its_sensors_are_not_read(self):
        amd = self.gpu("card0", "0x1002", "0x73bf", "0000:03:00.0", "suspended")
        self.write(f"{amd.relative_to(self.root)}/gpu_busy_percent", "12")
        self.write("sys/class/hwmon/hwmon9/name", "amdgpu")
        self.write("sys/class/hwmon/hwmon9/temp1_input", "48000")
        self.link("sys/class/hwmon/hwmon9/device", "sys/devices/pci0000:00/0000:03:00.0")
        gpu = (await self.sampler().sample())["gpus"][0]
        self.assertEqual((gpu["state"], gpu["usage"], gpu["temperature"]), ("asleep", None, None))

    async def test_a_suspended_nvidia_gpu_is_not_queried_even_when_asked(self):
        device = self.gpu("card0", "0x10de", "0x25a5", "0000:01:00.0", "active")
        sampler = self.sampler()
        original = sampler.collect
        def suspend_after_collect(now):
            result = original(now)
            (device / "power/runtime_status").write_text("suspended\n")
            return result
        sampler.collect = suspend_after_collect
        await sampler.sample(nvidia=True)
        self.assertEqual(self.calls, [])

    async def test_rates_start_over_after_a_pause(self):
        sampler = self.sampler()
        await sampler.sample()
        self.stat(cpu=(1100, 0, 100, 800, 0), cores=[(50, 0, 50, 400, 0)] * 2 + [(0, 0, 0, 0, 0)] * 9)
        self.clock.now += 600
        self.assertEqual((await sampler.sample())["cpu"]["usage"], 0.0)
        self.stat(cpu=(1200, 0, 100, 900, 0), cores=[(50, 0, 50, 400, 0)] * 2 + [(0, 0, 0, 0, 0)] * 9)
        self.clock.now += 1
        self.assertEqual((await sampler.sample())["cpu"]["usage"], 50.0)

    async def test_amd_and_intel_gpus_read_sysfs(self):
        amd = self.gpu("card0", "0x1002", "0x73bf", "0000:03:00.0")
        self.write(f"{amd.relative_to(self.root)}/gpu_busy_percent", "12")
        self.write(f"{amd.relative_to(self.root)}/mem_info_vram_used", "1048576")
        self.write(f"{amd.relative_to(self.root)}/mem_info_vram_total", "17163091968")
        self.write("sys/class/hwmon/hwmon9/name", "amdgpu")
        self.write("sys/class/hwmon/hwmon9/temp1_input", "48000")
        self.write("sys/class/hwmon/hwmon9/temp1_label", "edge")
        self.write("sys/class/hwmon/hwmon9/temp2_input", "70000")
        self.link("sys/class/hwmon/hwmon9/device", "sys/devices/pci0000:00/0000:03:00.0")
        self.gpu("card1", "0x8086", "0x9a68", "0000:00:02.0")
        self.write("sys/class/drm/card1/gt_act_freq_mhz", "633")
        self.write("sys/class/drm/card1/gt_RP0_freq_mhz", "1450")
        amd_gpu, intel_gpu = (await self.sampler().sample())["gpus"]
        self.assertEqual((amd_gpu["name"], amd_gpu["usage"], amd_gpu["memoryUsed"], amd_gpu["temperature"]),
                         ("AMD Radeon RX 6800/6800 XT / 6900 XT", 12.0, 1048576.0, 48.0))
        self.assertEqual((intel_gpu["name"], intel_gpu["frequency"], intel_gpu["frequencyMax"], intel_gpu["usage"]),
                         ("Intel UHD Graphics", 633.0, 1450.0, None))
        self.assertEqual(self.calls, [])

    async def test_a_bare_system_reports_nothing_instead_of_failing(self):
        sampler = sysmon.Sampler(self.root / "nothing", self.root / "nothing", clock=self.clock, pci_ids=self.root / "none")
        sample = await sampler.sample()
        self.assertFalse(sample["cpu"]["available"])
        self.assertFalse(sample["memory"]["available"])
        self.assertEqual((sample["disks"], sample["network"], sample["gpus"], sample["fans"]), ([], [], [], []))

    def test_unknown_devices_get_a_vendor_name(self):
        self.assertEqual(sysmon.gpu_name("0x10de", "0xffff", self.pci), "NVIDIA graphics")
        self.assertEqual(sysmon.gpu_name("0x10de", "0x25a5", self.root / "missing"), "NVIDIA graphics")


if __name__ == "__main__":
    unittest.main()
