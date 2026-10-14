import importlib.util
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("build_icons", ROOT / "scripts" / "build-icons.py")
build_icons = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build_icons)


class IconTests(unittest.TestCase):
    def test_icons_js_matches_the_svgs(self):
        self.assertEqual((ROOT / "core" / "icons.js").read_text(), build_icons.build(), "run scripts/build-icons.py")

    def test_every_literal_icon_name_exists(self):
        shapes = {path.stem for path in (ROOT / "assets" / "icons").glob("*.svg")}
        for qml in list((ROOT / "features").glob("*.qml")) + list((ROOT / "components").glob("*.qml")):
            lines = qml.read_text().splitlines()
            names = set(re.findall(r'glyph: "([a-z0-9-]+)"', "\n".join(lines)))
            # An Icon's name is on its own line or the same one, within the next few lines of "Icon {".
            for index, line in enumerate(lines):
                if re.search(r"\bIcon \{", line):
                    for following in lines[index:index + 8]:
                        found = re.search(r'\bname: "([a-z0-9-]+)"', following)
                        if found:
                            names.add(found.group(1))
                            break
            for name in names:
                with self.subTest(file=qml.name, icon=name):
                    self.assertIn(name, shapes)


if __name__ == "__main__":
    unittest.main()
