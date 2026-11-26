"""Resolution, refresh rate and scale for Settings → Displays.

The backend reads outputs from `hyprctl monitors -j`, applies a choice with `hl.monitor` through `hyprctl eval`, and
keeps the ones the user confirmed in ~/.config/shale/displays.lua, which shale.lua applies when Hyprland starts.
"""
import re

from shortcuts import lua_string

# Scales offered when they give a whole-pixel desktop at least MIN_WIDTH wide; the current scale is always offered.
SCALES = (1, 1.25, 4 / 3, 1.5, 1.6, 1.75, 2, 2.5, 3)
MIN_WIDTH = 960
MODE = re.compile(r"(\d+)x(\d+)@([\d.]+)Hz")


def scale_ok(width, height, scale):
    """Whether Hyprland can use `scale` as given: a multiple of 1/120 (the fractional-scale step) that divides the
    output into whole logical pixels."""
    if scale <= 0 or abs(scale * 120 - round(scale * 120)) > 1e-3:
        return False
    return all(abs(size / scale - round(size / scale)) < 1e-3 for size in (width, height))


def scales(width, height, current=None):
    found = [round(scale, 6) for scale in SCALES if scale_ok(width, height, round(scale * 120) / 120) and width / scale >= MIN_WIDTH]
    if current and not any(abs(current - scale) < 1e-3 for scale in found):
        found.append(round(current, 6))
    return sorted(found)


def modes(available):
    """`availableModes` as [{width, height, rates}], largest first, each rate list highest first."""
    sizes = {}
    for mode in available or []:
        match = MODE.fullmatch(str(mode))
        if match:
            rate = round(float(match[3]), 2)
            rates = sizes.setdefault((int(match[1]), int(match[2])), [])
            if rate not in rates:
                rates.append(rate)
    return [{"width": width, "height": height, "rates": sorted(rates, reverse=True)}
            for (width, height), rates in sorted(sizes.items(), key=lambda item: (item[0][0] * item[0][1], item[0][0]), reverse=True)]


def describe(monitor):
    """One output as Settings shows it."""
    width, height = int(monitor["width"]), int(monitor["height"])
    scale = float(monitor.get("scale", 1))
    found = modes(monitor.get("availableModes"))
    rate = float(monitor.get("refreshRate", 60))
    rates = next((mode["rates"] for mode in found if (mode["width"], mode["height"]) == (width, height)), [])
    # The rate as listed, so the current one matches a choice exactly.
    rate = min(rates, key=lambda value: abs(value - rate)) if rates else round(rate, 2)
    title = " ".join(part for part in (str(monitor.get("make") or ""), str(monitor.get("model") or "")) if part.strip())
    return {"name": str(monitor["name"]), "title": title or str(monitor.get("description") or monitor["name"]),
            "width": width, "height": height, "rate": rate, "scale": round(scale, 6), "modes": found,
            "scales": {f"{mode['width']}x{mode['height']}": scales(mode["width"], mode["height"], scale if (mode["width"], mode["height"]) == (width, height) else None)
                       for mode in found}}


def rule(monitor, width, height, rate, scale):
    """The full output rule for `monitor` with a new mode and scale: hl.monitor replaces the whole rule, so its
    position, rotation and 10-bit colour carry over."""
    entry = {"output": str(monitor["name"]), "mode": f"{width}x{height}@{rate:.2f}",
             "position": f"{int(monitor['x'])}x{int(monitor['y'])}", "scale": f"{scale:.6f}".rstrip("0").rstrip("."),
             "transform": int(monitor.get("transform", 0))}
    if "2101010" in str(monitor.get("currentFormat", "")):
        entry["bitdepth"] = 10
    return entry


def rule_lua(entry):
    fields = []
    for key in ("output", "mode", "position", "scale", "transform", "bitdepth"):
        if key in entry:
            value = entry[key]
            fields.append(f"{key} = {value}" if isinstance(value, int) else f"{key} = {lua_string(str(value))}")
    return "hl.monitor({" + ", ".join(fields) + "})"


def saved_lua(entries):
    """~/.config/shale/displays.lua: the confirmed rules, one per output."""
    rows = "".join("    " + rule_lua(entry)[len("hl.monitor("):-1] + ",\n" for _, entry in sorted(entries.items()))
    return "-- Written by Shale from Settings → Displays; change displays there.\nreturn {\n" + rows + "}\n"


def check(monitor, width, height, rate, scale):
    """Raises ValueError unless the mode is one the output lists and the scale suits it."""
    if not isinstance(width, int) or not isinstance(height, int) or not isinstance(rate, (int, float)) or not isinstance(scale, (int, float)):
        raise ValueError("Choose a resolution, refresh rate and scale.")
    mode = next((mode for mode in modes(monitor.get("availableModes")) if (mode["width"], mode["height"]) == (width, height)), None)
    if not mode or not any(abs(rate - value) < 0.01 for value in mode["rates"]):
        raise ValueError("This display doesn't offer that resolution and refresh rate.")
    current = float(monitor.get("scale", 1)) if (int(monitor["width"]), int(monitor["height"])) == (width, height) else None
    if not any(abs(scale - value) < 1e-3 for value in scales(width, height, current)):
        raise ValueError("This scale doesn't fit that resolution.")
