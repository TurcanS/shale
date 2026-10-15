"""Shale's keyboard shortcuts: the catalog, the key grammar, and what Hyprland binds.

The installer writes the default keys into ~/.config/hypr/shale.lua. Keys changed in Settings are saved as the
`shortcuts` setting and written to ~/.config/shale/shortcuts.lua, which shale.lua reads on every config load."""
import json
from pathlib import Path
import re

CATALOG = json.loads(Path(__file__).with_name("shortcuts.json").read_text())
ACTIONS = {item["action"]: item for item in CATALOG}
MODIFIERS = ("SUPER", "CTRL", "ALT", "SHIFT")
# Hyprland's modmask bits; Caps Lock and Num Lock (2, 16) don't change which shortcut a key press is.
MODMASK = {"SHIFT": 1, "CTRL": 4, "ALT": 8, "SUPER": 64}
MODIFIER_ALIASES = {"CONTROL": "CTRL", "MOD4": "SUPER", "WIN": "SUPER", "META": "SUPER", "LOGO": "SUPER", "MOD1": "ALT"}
NAMED = ("SPACE", "Return", "TAB", "Escape", "BackSpace", "Delete", "Insert", "Home", "End", "Prior", "Next", "left", "right",
         "up", "down", "Print", "Pause", "Scroll_Lock", "COMMA", "period", "slash", "semicolon", "apostrophe", "bracketleft",
         "bracketright", "backslash", "minus", "equal", "grave")
KEYS = {name.lower(): name for name in (*NAMED, *map(chr, range(65, 91)), *map(str, range(10)), *(f"F{n}" for n in range(1, 25)))}
KEYS.update({"enter": "Return", "esc": "Escape", "pageup": "Prior", "page_up": "Prior", "pagedown": "Next", "page_down": "Next",
             "comma": "COMMA", "space": "SPACE", "tab": "TAB", "sys_req": "Print"})
# Keys that type nothing, so they can be a shortcut on their own (or with Shift alone).
SOLO = re.compile(r"F\d+|Print|Pause|Scroll_Lock|Insert|XF86\w+")
LABELS = {"SUPER": "Super", "CTRL": "Ctrl", "ALT": "Alt", "SHIFT": "Shift", "SPACE": "Space", "COMMA": ",", "Return": "Enter",
          "TAB": "Tab", "Escape": "Esc", "BackSpace": "Backspace", "Prior": "Page Up", "Next": "Page Down", "left": "←",
          "right": "→", "up": "↑", "down": "↓", "period": ".", "slash": "/", "semicolon": ";", "apostrophe": "'",
          "bracketleft": "[", "bracketright": "]", "backslash": "\\", "minus": "-", "equal": "=", "grave": "`",
          "Scroll_Lock": "Scroll Lock"}
RECORD_SUBMAP = "shale-record"


def canonical(keys):
    """'shift + super + k' as 'SUPER + SHIFT + K'. Raises ValueError with a message for the user."""
    parts = [part.strip() for part in str(keys).split("+")]
    if not any(parts) or not all(parts):
        raise ValueError("Press a key with Super, Ctrl or Alt.")
    *mods, key = parts
    mods = [MODIFIER_ALIASES.get(mod.upper(), mod.upper()) for mod in mods]
    if not set(mods) <= set(MODIFIERS) or len(set(mods)) != len(mods):
        raise ValueError("Only Super, Ctrl, Alt and Shift can be held with the key.")
    name = KEYS.get(key.lower()) or (key if re.fullmatch(r"XF86[A-Za-z0-9]+", key) else None)
    if not name:
        raise ValueError(f"{key} can't be used in a shortcut.")
    if not set(mods) & {"SUPER", "CTRL", "ALT"} and not SOLO.fullmatch(name):
        raise ValueError("Add Super, Ctrl or Alt: without one, this key is needed for typing.")
    return " + ".join([mod for mod in MODIFIERS if mod in mods] + [name])


def label(keys):
    """'SUPER + COMMA' as 'Super + ,' for messages."""
    return " + ".join(LABELS.get(part, part) for part in keys.split(" + "))


def combo(keys):
    """A comparable form of a key string: (modmask, lowercase key)."""
    *mods, key = keys.split(" + ")
    return sum(MODMASK[mod] for mod in mods), (KEYS.get(key.lower()) or key).lower()


def check(value):
    """Raises ValueError unless `value` is a usable `shortcuts` setting: {action: canonical keys or ""}."""
    if not isinstance(value, dict):
        raise ValueError("Incorrect shortcuts.")
    for action, keys in value.items():
        if action not in ACTIONS or not isinstance(keys, str):
            raise ValueError("Incorrect shortcuts.")
        if keys and canonical(keys) != keys:
            raise ValueError(f"Incorrect keys for {ACTIONS[action]['title']}.")
    taken = [combo(keys) for keys in value.values() if keys]
    if len(taken) != len(set(taken)):
        raise ValueError("Two shortcuts use the same keys.")


def installed(hypr):
    """{action: keys} as the installed fragments bind them, and whether they can apply changes from Settings
    (fragments from before shortcuts could change don't read shortcuts.lua)."""
    bound = {}
    try:
        text = (hypr / "shale.lua").read_text()
    except OSError:
        return bound, False
    table = re.search(r"local shortcuts = \{\n(.*?)\n\}", text, re.S)
    for keys, action in re.findall(r'\["([^"\n]+)"\] = "([^"\n]+)"', table[1] if table else ""):
        bound.setdefault(action, keys)
    try:
        wallpaper = (hypr / "shale-wallpaper.lua").read_text()
    except OSError:
        wallpaper = ""
    if match := re.search(r'hl\.bind\("([^"\n]+)"', wallpaper):
        bound["wallpaper"] = match[1]
    return bound, "shortcuts.lua" in text and RECORD_SUBMAP in text


def effective(bound, changed):
    """{action: keys or ""}: changes from Settings over what the installer bound."""
    return {action: changed.get(action, bound.get(action, "")) for action in ACTIONS}


def listing(bound, changed, ready):
    return {"ready": ready, "shortcuts": [{"action": item["action"], "title": item["title"], "default": item["keys"],
                                           "keys": changed.get(item["action"], bound.get(item["action"], "")),
                                           "changed": item["action"] in changed} for item in CATALOG]}


def clash(keys, action, current, binds, planned=None):
    """Why `keys` can't be given to `action`, or None. `current` is every action's keys as bound now, `planned`
    the keys after this change (default: `current`) and `binds` is `hyprctl binds -j`. A live bind described as a
    Shale action, or on keys an action has now, belongs to that action."""
    wanted = combo(keys)
    for other, other_keys in (planned or current).items():
        if other != action and other_keys and combo(other_keys) == wanted:
            return f"{label(keys)} is already the {ACTIONS[other]['title']} shortcut."
    for bind in binds if isinstance(binds, list) else []:
        if not isinstance(bind, dict) or bind.get("submap") or bind.get("mouse") or not isinstance(bind.get("key"), str):
            continue
        mask = int(bind.get("modmask") or 0) & sum(MODMASK.values())
        if (mask, (KEYS.get(bind["key"].lower()) or bind["key"]).lower()) != wanted:
            continue
        description = str(bind.get("description") or "")
        owner = description.removeprefix("Shale: ") if description.startswith("Shale: ") else None
        if owner is None and any(other_keys and combo(other_keys) == wanted for other_keys in current.values()):
            owner = next(other for other, other_keys in current.items() if other_keys and combo(other_keys) == wanted)
        if owner == action or (owner in ACTIONS and (planned or current).get(owner) != keys):
            continue  # this action's own bind, or a Shale bind about to move away
        if owner in ACTIONS:
            return f"{label(keys)} is already the {ACTIONS[owner]['title']} shortcut."
        return f"{label(keys)} is already used by your Hyprland config" + (f" ({description})." if description else ".")
    return None


def lua_string(text):
    """A Lua string literal; every byte outside a safe ASCII set (so every byte of a non-ASCII character too) is a
    decimal escape."""
    return '"' + "".join(chr(byte) if byte < 128 and (chr(byte).isalnum() or chr(byte) in " +_-./:") else f"\\{byte:03d}"
                         for byte in text.encode()) + '"'


def overrides_lua(changed):
    """~/.config/shale/shortcuts.lua for the `shortcuts` setting."""
    rows = "".join(f"    [{lua_string(action)}] = {lua_string(keys) if keys else 'false'},\n" for action, keys in sorted(changed.items()))
    return "-- Written by Shale from Settings → Shortcuts; change shortcuts there.\nreturn {\n" + rows + "}\n"


def rebind_lua(action, old, new, command):
    """Code for `hyprctl eval` that moves `action` from the keys `old` to `new` ("" for none) right away."""
    code = "".join(f"pcall(hl.unbind, {lua_string(keys)}) " for keys in old if keys)
    if new:
        code += (f"hl.bind({lua_string(new)}, hl.dsp.exec_cmd({lua_string(command + ' ' + action)}), "
                 f"{{description = {lua_string('Shale: ' + action)}}})")
    return code
