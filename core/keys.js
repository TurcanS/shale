.pragma library
// Key presses as Hyprland key strings ("SUPER + SHIFT + K"), for recording a shortcut, and how keys are shown.
// helpers/shortcuts.py checks the result and has the same names and labels.

// Qt key codes of keys with a name of their own.
const named = {
    0x20: "SPACE", 0x2c: "COMMA", 0x2e: "period", 0x2f: "slash", 0x3b: "semicolon", 0x27: "apostrophe", 0x5b: "bracketleft",
    0x5d: "bracketright", 0x5c: "backslash", 0x2d: "minus", 0x3d: "equal", 0x60: "grave",
    0x01000000: "Escape", 0x01000001: "TAB", 0x01000003: "BackSpace", 0x01000004: "Return", 0x01000005: "Return",
    0x01000006: "Insert", 0x01000007: "Delete", 0x01000008: "Pause", 0x01000009: "Print", 0x01000010: "Home", 0x01000011: "End",
    0x01000012: "left", 0x01000013: "up", 0x01000014: "right", 0x01000015: "down", 0x01000016: "Prior", 0x01000017: "Next",
    0x01000026: "Scroll_Lock",
    0x01000070: "XF86AudioLowerVolume", 0x01000071: "XF86AudioMute", 0x01000072: "XF86AudioRaiseVolume",
    0x01000080: "XF86AudioPlay", 0x01000081: "XF86AudioStop", 0x01000082: "XF86AudioPrev", 0x01000083: "XF86AudioNext",
    0x01000085: "XF86AudioPause", 0x01000086: "XF86AudioPlay"
};
// xkb keycodes of the main block, named as on a US layout: Shift+1 is still "1", and so are other layouts' letters.
const positions = {
    10: "1", 11: "2", 12: "3", 13: "4", 14: "5", 15: "6", 16: "7", 17: "8", 18: "9", 19: "0", 20: "minus", 21: "equal",
    24: "Q", 25: "W", 26: "E", 27: "R", 28: "T", 29: "Y", 30: "U", 31: "I", 32: "O", 33: "P", 34: "bracketleft", 35: "bracketright",
    38: "A", 39: "S", 40: "D", 41: "F", 42: "G", 43: "H", 44: "J", 45: "K", 46: "L", 47: "semicolon", 48: "apostrophe", 49: "grave",
    51: "backslash", 52: "Z", 53: "X", 54: "C", 55: "V", 56: "B", 57: "N", 58: "M", 59: "COMMA", 60: "period", 61: "slash"
};
const modifierKeys = [0x01000020, 0x01000021, 0x01000022, 0x01000023, 0x01000053, 0x01000054, 0x01000055, 0x01000056,
                      0x01001103, 0x01000024, 0x01000025];
const labels = {
    SUPER: "Super", CTRL: "Ctrl", ALT: "Alt", SHIFT: "Shift", SPACE: "Space", COMMA: ",", Return: "Enter", TAB: "Tab",
    Escape: "Esc", BackSpace: "Backspace", Prior: "Page Up", Next: "Page Down", left: "←", right: "→", up: "↑", down: "↓",
    period: ".", slash: "/", semicolon: ";", apostrophe: "'", bracketleft: "[", bracketright: "]", backslash: "\\", minus: "-",
    equal: "=", grave: "`", Scroll_Lock: "Scroll Lock"
};

function isModifier(key) {
    return modifierKeys.indexOf(key) >= 0;
}

// Held modifiers in Hyprland's order.
function modifiers(mask) {
    const held = [];
    if (mask & 0x10000000) held.push("SUPER");
    if (mask & 0x04000000) held.push("CTRL");
    if (mask & 0x08000000) held.push("ALT");
    if (mask & 0x02000000) held.push("SHIFT");
    return held;
}

// The key's Hyprland name, or "" for a key a shortcut can't use.
function keyName(key, scanCode) {
    if (named[key])
        return named[key];
    if (key >= 0x01000030 && key <= 0x01000047)
        return "F" + (key - 0x01000030 + 1);
    if ((key >= 0x41 && key <= 0x5a) || (key >= 0x30 && key <= 0x39))
        return String.fromCharCode(key);
    return positions[scanCode] || "";
}

// "SUPER + SHIFT + K" for a key event, or "" while only modifiers are down.
function fromEvent(event) {
    if (isModifier(event.key))
        return "";
    const name = keyName(event.key, event.nativeScanCode);
    return name ? modifiers(event.modifiers).concat([name]).join(" + ") : "";
}

// Keycap labels: "SUPER + COMMA" is ["Super", ","].
function caps(keys) {
    return keys ? keys.split(" + ").map(part => labels[part] || part) : [];
}

const modifierNames = {0x01000020: "SHIFT", 0x01000021: "CTRL", 0x01000022: "SUPER", 0x01000023: "ALT", 0x01000053: "SUPER", 0x01000054: "SUPER"};

// The modifiers held once this press (or release) is done, as "SUPER + SHIFT".
function held(event, pressed) {
    const mods = modifiers(event.modifiers);
    const own = modifierNames[event.key];
    const now = own ? (pressed ? mods.concat([own]) : mods.filter(mod => mod !== own)) : mods;
    return ["SUPER", "CTRL", "ALT", "SHIFT"].filter(mod => now.indexOf(mod) >= 0).join(" + ");
}
