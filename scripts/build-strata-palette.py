#!/usr/bin/env python3
"""Generates and checks the Strata palette.

Colors are chosen in OKLCH so lightness stays even across hues, then converted to sRGB hex.
The script fails if a color leaves the sRGB gamut, if text or accent colors miss their contrast target
against the panel, or if two app "minerals" are too close to tell apart.

    python3 scripts/build-strata-palette.py          # print the table
    python3 scripts/build-strata-palette.py --check  # exit 1 when a rule fails
"""
import math
import sys

# Rules: WCAG contrast on the panel color, and the smallest OKLab distance allowed between two minerals.
TEXT_CONTRAST = 7.0
MUTED_CONTRAST = 4.5
ACCENT_CONTRAST = 4.5
MINERAL_CONTRAST = 3.0
MIN_MINERAL_DISTANCE = 0.075
# Shale refuses accents below this relative luminance (features/ColorSettings.qml validAccent).
MIN_ACCENT_LUMINANCE = 0.28


def to_linear(value):
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


def to_gamma(value):
    return 12.92 * value if value <= 0.0031308 else 1.055 * value ** (1 / 2.4) - 0.055


def oklch_to_linear(lightness, chroma, hue_degrees):
    hue = math.radians(hue_degrees)
    a, b = chroma * math.cos(hue), chroma * math.sin(hue)
    l = (lightness + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m = (lightness - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s = (lightness - 0.0894841775 * a - 1.2914855480 * b) ** 3
    return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)


def in_gamut(rgb):
    return all(-0.0001 <= channel <= 1.0001 for channel in rgb)


def hex_of(rgb):
    return "#" + "".join("%02x" % round(max(0, min(1, to_gamma(max(0, min(1, c))))) * 255) for c in rgb)


def luminance(rgb):
    r, g, b = (max(0, min(1, c)) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(first, second):
    a, b = luminance(first), luminance(second)
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)


def oklab(lightness, chroma, hue_degrees):
    hue = math.radians(hue_degrees)
    return lightness, chroma * math.cos(hue), chroma * math.sin(hue)


def distance(first, second):
    return math.dist(oklab(*first), oklab(*second))


# name: (lightness, chroma, hue in degrees). Surfaces are "basalt": cool and nearly neutral.
SURFACES = {
    "background": (0.125, 0.006, 255),
    "panel": (0.165, 0.008, 255),
    "surface": (0.210, 0.009, 255),
    "raised": (0.255, 0.010, 255),
    "hover": (0.305, 0.011, 255),
    "border": (0.320, 0.010, 255),
    "text": (0.945, 0.010, 85),
    "muted": (0.740, 0.010, 255),
    "disabled": (0.560, 0.010, 255),
}
# The Front: a hot edge against cool rock. accent follows the wallpaper when asked; these are the defaults.
LIGHT = {
    "accent": (0.800, 0.140, 62),
    "accent2": (0.730, 0.160, 28),
}
SEMANTIC = {
    "danger": (0.740, 0.100, 22),
    "success": (0.760, 0.100, 150),
    "warning": (0.800, 0.100, 88),
}
# One stable color per app, picked by hashing the app id. Hues are spread evenly around the wheel; lightness
# alternates between neighbours (light, dark, light...) so close hues stay apart without getting louder.
MINERALS = {
    "ember": (0.770, 0.100, 40),
    "ochre": (0.690, 0.100, 85),
    "lichen": (0.790, 0.100, 128),
    "malachite": (0.690, 0.095, 172),
    "azurite": (0.790, 0.095, 225),
    "lapis": (0.690, 0.100, 268),
    "amethyst": (0.790, 0.100, 312),
    "rose": (0.690, 0.100, 354),
}
OTHER = ("granite", (0.600, 0.012, 255))


def resolve(table):
    result = {}
    for name, (lightness, chroma, hue) in table.items():
        rgb = oklch_to_linear(lightness, chroma, hue)
        result[name] = {"lch": (lightness, chroma, hue), "rgb": rgb, "hex": hex_of(rgb)}
    return result


def check(surfaces, light, semantic, minerals):
    problems = []
    for group in (surfaces, light, semantic, minerals):
        for name, entry in group.items():
            if not in_gamut(entry["rgb"]):
                problems.append(f"{name} {entry['hex']} is outside sRGB")
    panel = surfaces["panel"]["rgb"]
    for name, target in (("text", TEXT_CONTRAST), ("muted", MUTED_CONTRAST)):
        ratio = contrast(surfaces[name]["rgb"], panel)
        if ratio < target:
            problems.append(f"{name} contrast {ratio:.2f} < {target}")
    for name in light:
        ratio = contrast(light[name]["rgb"], panel)
        if ratio < ACCENT_CONTRAST:
            problems.append(f"{name} contrast {ratio:.2f} < {ACCENT_CONTRAST}")
    if luminance(light["accent"]["rgb"]) < MIN_ACCENT_LUMINANCE:
        problems.append("accent is darker than Shale accepts")
    for name, entry in {**semantic, **minerals}.items():
        ratio = contrast(entry["rgb"], panel)
        if ratio < MINERAL_CONTRAST:
            problems.append(f"{name} contrast {ratio:.2f} < {MINERAL_CONTRAST}")
    names = list(minerals)
    for i, first in enumerate(names):
        for second in names[i + 1:]:
            gap = distance(minerals[first]["lch"], minerals[second]["lch"])
            if gap < MIN_MINERAL_DISTANCE:
                problems.append(f"{first} and {second} are too close ({gap:.3f})")
    return problems


def main():
    surfaces, light, semantic, minerals = resolve(SURFACES), resolve(LIGHT), resolve(SEMANTIC), resolve(MINERALS)
    other = resolve({OTHER[0]: OTHER[1]})
    panel = surfaces["panel"]["rgb"]
    problems = check(surfaces, light, semantic, minerals)
    for title, group in (("Surfaces", surfaces), ("Light", light), ("Semantic", semantic), ("Minerals", minerals), ("Other", other)):
        print(f"\n{title}")
        for name, entry in group.items():
            lightness, chroma, hue = entry["lch"]
            print(f"  {name:<11} {entry['hex']}  L{lightness:.3f} C{chroma:.3f} h{hue:>3}  contrast on panel {contrast(entry['rgb'], panel):5.2f}")
    names = list(minerals)
    closest = min((distance(minerals[a]["lch"], minerals[b]["lch"]), a, b) for i, a in enumerate(names) for b in names[i + 1:])
    print(f"\nClosest minerals: {closest[1]} / {closest[2]} at {closest[0]:.3f} (minimum {MIN_MINERAL_DISTANCE})")
    print("Problems: " + ("none" if not problems else "\n  " + "\n  ".join(problems)))
    if "--check" in sys.argv and problems:
        sys.exit(1)


if __name__ == "__main__":
    main()
