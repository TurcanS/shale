"""Unit conversion for the launcher, such as "10 km to mi" or "72 f in c"."""
import math
import re

# Each unit maps to (category, factor to the category's base unit). Aliases share an entry.
_UNITS = {}

def _define(category, factor, name, *aliases):
    for alias in (name,) + aliases:
        _UNITS[alias.lower()] = (category, factor, name)

for args in [
    ("length", 1e-3, "mm", "millimeter", "millimeters", "millimetre", "millimetres"),
    ("length", 1e-2, "cm", "centimeter", "centimeters", "centimetre", "centimetres"),
    ("length", 1, "m", "meter", "meters", "metre", "metres"),
    ("length", 1e3, "km", "kilometer", "kilometers", "kilometre", "kilometres"),
    ("length", 0.0254, "in", "inch", "inches", '"'),
    ("length", 0.3048, "ft", "foot", "feet", "'"),
    ("length", 0.9144, "yd", "yard", "yards"),
    ("length", 1609.344, "mi", "mile", "miles"),
    ("length", 1852, "nmi", "nautical mile", "nautical miles"),
    ("mass", 1e-6, "mg", "milligram", "milligrams"),
    ("mass", 1e-3, "g", "gram", "grams"),
    ("mass", 1, "kg", "kilogram", "kilograms", "kilo", "kilos"),
    ("mass", 1e3, "t", "tonne", "tonnes", "ton", "tons"),
    ("mass", 0.028349523125, "oz", "ounce", "ounces"),
    ("mass", 0.45359237, "lb", "lbs", "pound", "pounds"),
    ("mass", 6.35029318, "st", "stone", "stones"),
    ("volume", 1e-3, "ml", "milliliter", "milliliters", "millilitre", "millilitres"),
    ("volume", 1e-2, "cl", "centiliter", "centiliters"),
    ("volume", 1e-1, "dl", "deciliter", "deciliters"),
    ("volume", 1, "l", "liter", "liters", "litre", "litres"),
    ("volume", 1e3, "m3", "m³", "cubic meter", "cubic meters"),
    ("volume", 3.785411784, "gal", "gallon", "gallons"),
    ("volume", 0.946352946, "qt", "quart", "quarts"),
    ("volume", 0.473176473, "pt", "pint", "pints"),
    ("volume", 0.2365882365, "cup", "cups"),
    ("volume", 0.0295735295625, "fl oz", "floz", "fluid ounce", "fluid ounces"),
    ("volume", 0.01478676478125, "tbsp", "tablespoon", "tablespoons"),
    ("volume", 0.00492892159375, "tsp", "teaspoon", "teaspoons"),
    ("speed", 1, "m/s", "mps"),
    ("speed", 1 / 3.6, "km/h", "kmh", "kph"),
    ("speed", 0.44704, "mph"),
    ("speed", 1852 / 3600, "kn", "knot", "knots"),
    ("area", 1, "m2", "m²", "square meter", "square meters", "sqm"),
    ("area", 1e6, "km2", "km²", "square kilometer", "square kilometers"),
    ("area", 0.09290304, "ft2", "ft²", "sqft", "square foot", "square feet"),
    ("area", 1e4, "ha", "hectare", "hectares"),
    ("area", 4046.8564224, "ac", "acre", "acres"),
    ("time", 1e-3, "ms", "millisecond", "milliseconds"),
    ("time", 1, "s", "sec", "secs", "second", "seconds"),
    ("time", 60, "min", "mins", "minute", "minutes"),
    ("time", 3600, "h", "hr", "hrs", "hour", "hours"),
    ("time", 86400, "d", "day", "days"),
    ("time", 604800, "wk", "week", "weeks"),
    ("data", 1 / 8, "bit", "bits"),
    ("data", 1, "B", "byte", "bytes"),
    ("data", 1e3, "kB", "kb", "kilobyte", "kilobytes"),
    ("data", 1e6, "MB", "mb", "megabyte", "megabytes"),
    ("data", 1e9, "GB", "gb", "gigabyte", "gigabytes"),
    ("data", 1e12, "TB", "tb", "terabyte", "terabytes"),
    ("data", 1024, "KiB", "kib"),
    ("data", 1024 ** 2, "MiB", "mib"),
    ("data", 1024 ** 3, "GiB", "gib"),
    ("data", 1024 ** 4, "TiB", "tib"),
    ("data rate", 1 / 8, "bit/s", "bps"),
    ("data rate", 1e3 / 8, "kbit/s", "kbps"),
    ("data rate", 1e6 / 8, "Mbit/s", "mbps", "mbit/s"),
    ("data rate", 1e9 / 8, "Gbit/s", "gbps", "gbit/s"),
    ("data rate", 1e12 / 8, "Tbit/s", "tbps", "tbit/s"),
    ("data rate", 1, "B/s", "bytes/s"),
    ("data rate", 1e3, "kB/s", "kb/s"),
    ("data rate", 1e6, "MB/s", "mb/s"),
    ("data rate", 1e9, "GB/s", "gb/s"),
    ("data rate", 1e12, "TB/s", "tb/s"),
    ("energy", 1, "J", "joule", "joules"),
    ("energy", 1e3, "kJ", "kilojoule", "kilojoules"),
    ("energy", 4.184, "cal", "calorie", "calories"),
    ("energy", 4184, "kcal", "kilocalorie", "kilocalories"),
    ("energy", 3.6e6, "kWh", "kwh"),
]:
    _define(*args)
for args in [("data", 1e3 / 8, "kbit"), ("data", 1e6 / 8, "Mbit"), ("data", 1e9 / 8, "Gbit"), ("data", 1e12 / 8, "Tbit")]:
    _define(*args)

# Prefix + b/B (+ ps or /s), written with some capital: the case of the b decides, as in
# networking: Mb and Mbps are bits, MB and MBps are bytes. All-lowercase spellings stay
# as most people mean them (kb, mb are bytes; mbps is bits) through the aliases above.
_PREFIXED = re.compile(r"([kKMGT])([bB])(ps|/s)?")
_BYTES = {"k": "kB", "M": "MB", "G": "GB", "T": "TB"}
_BITS = {"k": "kbit", "M": "Mbit", "G": "Gbit", "T": "Tbit"}

# Temperatures are offsets, not factors: (to kelvin, from kelvin).
_TEMPERATURES = {
    "°C": (lambda v: v + 273.15, lambda k: k - 273.15),
    "°F": (lambda v: (v - 32) * 5 / 9 + 273.15, lambda k: (k - 273.15) * 9 / 5 + 32),
    "K": (lambda v: v, lambda k: k),
}
for name, aliases in {"°C": ("c", "°c", "celsius", "degc"), "°F": ("f", "°f", "fahrenheit", "degf"), "K": ("k", "kelvin", "kelvins")}.items():
    for alias in aliases:
        _UNITS[alias] = ("temperature", None, name)

PATTERN = re.compile(r"^\s*((?:-?\d+(?:[.,]\d+)?|-?[.,]\d+)(?:e[+-]?\d+)?)\s*(.+?)\s+(?:to|in|as|->|=)\s+(.+?)\s*$", re.IGNORECASE)

def _unit(text):
    text = text.strip()
    match = _PREFIXED.fullmatch(text)
    if match and text != text.lower():
        prefix = "k" if match[1] in "kK" else match[1]
        name = (_BYTES if match[2] == "B" else _BITS)[prefix] + ("/s" if match[3] else "")
        if name.lower() in _UNITS:
            return _UNITS[name.lower()]
    for key in (text.lower(), text.lower().rstrip(".")):
        if key in _UNITS:
            return _UNITS[key]
    raise ValueError(f"Unknown unit “{text}”.")

def _format(value):
    if value == 0:
        return "0"
    if abs(value) >= 1e15 or abs(value) < 1e-6:
        return f"{value:.6g}"
    digits = max(0, 6 - int(math.floor(math.log10(abs(value)))) - 1)
    text = f"{value:.{min(digits, 10)}f}"
    return text.rstrip("0").rstrip(".") if "." in text else text

def convert(query):
    if not isinstance(query, str) or len(query) > 100:
        raise ValueError("Type a conversion such as “10 km to mi”.")
    match = PATTERN.match(query)
    if not match:
        raise ValueError("Type a conversion such as “10 km to mi”.")
    amount = float(match[1].replace(",", "."))
    source, target = _unit(match[2]), _unit(match[3])
    if source[0] != target[0]:
        raise ValueError(f"Cannot convert {source[0]} to {target[0]}.")
    if source[0] == "temperature":
        value = _TEMPERATURES[target[2]][1](_TEMPERATURES[source[2]][0](amount))
    else:
        value = amount * source[1] / target[1]
    if not math.isfinite(amount) or not math.isfinite(value):
        raise ValueError("That number is too large to convert.")
    return {"value": value, "text": _format(value) + " " + target[2], "from": _format(amount) + " " + source[2]}
