#!/usr/bin/env python3
"""Build assets/emoji.json for the launcher's emoji picker from Unicode's emoji-test.txt.

Keeps fully-qualified emoji without skin-tone variants (they are chosen per emoji in most apps),
in Unicode's recommended order. Run again when a new Unicode emoji version is released.
"""
import argparse
import json
from pathlib import Path
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
SOURCE = "https://unicode.org/Public/emoji/latest/emoji-test.txt"


def parse(text):
    entries, group, subgroup = [], "", ""
    for line in text.splitlines():
        if line.startswith("# group:"):
            group = line.split(":", 1)[1].strip()
        elif line.startswith("# subgroup:"):
            subgroup = line.split(":", 1)[1].strip()
        elif line and not line.startswith("#") and "; fully-qualified" in line:
            codes, comment = line.split("#", 1)
            if any(tone in codes for tone in ("1F3FB", "1F3FC", "1F3FD", "1F3FE", "1F3FF")):
                continue
            emoji = "".join(chr(int(code, 16)) for code in codes.split(";")[0].split())
            # The comment is "<emoji> E<version> <name>".
            name = comment.strip().split(" ", 2)[2]
            if group == "Component":
                continue
            # Search words: the name plus the subgroup ("face-smiling" -> "face smiling").
            entries.append({"e": emoji, "n": name, "k": subgroup.replace("-", " ").replace("&", "and")})
    return entries


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", help="Local emoji-test.txt instead of downloading it")
    args = parser.parse_args()
    if args.source:
        text = Path(args.source).read_text(encoding="utf-8")
    else:
        with urlopen(Request(SOURCE, headers={"User-Agent": "ShaleShell/1.0"}), timeout=30) as response:
            text = response.read().decode("utf-8")
    entries = parse(text)
    output = ROOT / "assets/emoji.json"
    output.write_text(json.dumps(entries, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"Wrote {len(entries)} emoji to {output.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
