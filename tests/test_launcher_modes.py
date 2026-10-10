import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "helpers"))
import backend as b
import units


class UnitTests(unittest.TestCase):
    def test_common_conversions(self):
        cases = {"10 km to mi": "6.21371 mi", "72 f in c": "22.2222 °C", "0 c to f": "32 °F", "300 K to C": "26.85 °C",
                 "1 GiB to MB": "1073.74 MB", "5 ft in cm": "152.4 cm", "100 km/h to mph": "62.1371 mph",
                 "10 fl oz to ml": "295.735 ml", "1,5 kg to lb": "3.30693 lb", "2 hours to min": "120 min",
                 "1 kWh in kcal": "860.421 kcal", "1 acre to m2": "4046.86 m2", "-40 c to f": "-40 °F"}
        for query, expected in cases.items():
            with self.subTest(query=query):
                self.assertEqual(units.convert(query)["text"], expected)

    def test_case_distinguishes_bits_and_bytes_only_when_needed(self):
        self.assertEqual(units.convert("1000 kb to MB")["text"], "1 MB")
        self.assertEqual(units.convert("8 bit to B")["text"], "1 B")

    def test_bits_and_bit_rates(self):
        cases = {"100 Mb to MB": "12.5 MB", "100 mb to MB": "100 MB", "1 Gb to MB": "125 MB", "8 Kb to B": "1000 B",
                 "100 Mbps to MB/s": "12.5 MB/s", "1 Gb/s to Mbit/s": "1000 Mbit/s", "50 MB/s to Mbps": "400 Mbit/s",
                 "10 MBps to Mbps": "80 Mbit/s", "1 GBps to MB/s": "1000 MB/s", "1 KBps to kbps": "8 kbit/s", "1000 KB to MB": "1 MB",
                 "1 mbps to kbps": "1000 kbit/s", "1 TBps to GB/s": "1000 GB/s", "1 Tbps to Gbps": "1000 Gbit/s",
                 "1 TB/s to Tb/s": "8 Tbit/s", "1 tbps to gbps": "1000 Gbit/s"}
        for query, expected in cases.items():
            with self.subTest(query=query):
                self.assertEqual(units.convert(query)["text"], expected)

    def test_rejects_unknown_or_mismatched_units(self):
        for query, message in {"7 days to die": "Unknown unit", "10 km to kg": "Cannot convert length to mass",
                               "hello": "Type a conversion", "x" * 101: "Type a conversion"}.items():
            with self.subTest(query=query), self.assertRaisesRegex(ValueError, message):
                units.convert(query)
        with self.assertRaises(ValueError):
            units.convert(None)


class FileSearchTests(unittest.TestCase):
    def test_words_become_an_ordered_case_insensitive_pattern(self):
        args = b.file_search_args("tax  report.pdf", Path("/home/me"))
        self.assertEqual(args[0], "fd")
        self.assertIn("--ignore-case", args)
        self.assertEqual(args[-2:], ["tax.*report\\.pdf", "/home/me"])
        self.assertEqual(args[-3], "--")
        for query in ("", "   ", None, "x" * 201):
            with self.subTest(query=query), self.assertRaises(b.BackendError):
                b.file_search_args(query, Path("/home/me"))

    def test_typed_paths_match_the_full_path(self):
        args = b.file_search_args("Documents/notes", Path("/home/me"))
        self.assertIn("--full-path", args)
        self.assertEqual(args[-2], "Documents/notes")
        self.assertNotIn("--full-path", b.file_search_args("notes", Path("/home/me")))
        output = b"/home/me/Documents/old/notes-archive/\n/home/me/Documents/notes/\n"
        self.assertEqual(b.file_results(output, "Documents/notes", Path("/home/me"))[0]["path"], "/home/me/Documents/notes")

    def test_results_prefer_exact_and_shallow_names(self):
        output = b"/home/me/src/deep/notes/\n/home/me/old-notes.txt\n/home/me/notes/\n/srv/notes.md\n"
        results = b.file_results(output, "notes", Path("/home/me"))
        self.assertEqual([r["path"] for r in results], ["/home/me/notes", "/home/me/src/deep/notes", "/srv/notes.md", "/home/me/old-notes.txt"])
        self.assertEqual(results[0], {"path": "/home/me/notes", "name": "notes", "folder": "~", "directory": True})
        self.assertEqual(results[1]["folder"], "~/src/deep")
        self.assertEqual(results[2]["folder"], "/srv")


class EmojiDataTests(unittest.TestCase):
    def test_bundled_emoji_are_searchable_and_skin_tone_free(self):
        data = json.loads((ROOT / "assets/emoji.json").read_text(encoding="utf-8"))
        self.assertGreater(len(data), 1500)
        self.assertTrue(all(set(item) == {"e", "n", "k"} and item["e"] and item["n"] for item in data))
        self.assertFalse(any("skin tone" in item["n"] for item in data))
        self.assertIn("grinning face", [item["n"] for item in data[:5]])


class BackendDispatchTests(unittest.IsolatedAsyncioTestCase):
    async def test_units_convert_dispatch(self):
        backend = b.Backend()
        self.assertEqual((await backend.dispatch("units.convert", {"query": "1 m to cm"}))["text"], "100 cm")
        with self.assertRaises(b.BackendError):
            await backend.dispatch("units.convert", {"query": "1 m to kg"})


if __name__ == "__main__":
    unittest.main()
