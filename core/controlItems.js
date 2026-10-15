.pragma library
// What the control center's main page can show, in default order. helpers/backend.py (CONTROL_TILES,
// CONTROL_SECTIONS, CONTROL_FOOTER) checks saved layouts against these IDs.
const tiles = [
    {id: "wifi", title: "Wi-Fi", icon: "wifi", description: "Opens networks from its arrow"},
    {id: "bluetooth", title: "Bluetooth", icon: "bluetooth", description: "Opens devices from its arrow"},
    {id: "dnd", title: "Do not disturb", icon: "bell-off"},
    {id: "awake", title: "Stay awake", icon: "moon"},
    {id: "grayscale", title: "Grayscale", icon: "palette"},
    {id: "lid", title: "Lid closed", icon: "laptop", description: "On laptops"}
];
const sections = [
    {id: "focus", title: "Focus", icon: "focus", description: "Start a focus session"},
    {id: "levels", title: "Volume and brightness", icon: "volume"},
    {id: "media", title: "Now playing", icon: "music"}
];
// Settings stays: it is the way back to this page.
const footer = [
    {id: "capture", title: "Capture", icon: "camera"},
    {id: "settings", title: "Settings", icon: "settings", required: true},
    {id: "lock", title: "Lock", icon: "lock"},
    {id: "session", title: "Session", icon: "power"}
];

function find(list, id) {
    return list.find(item => item.id === id) || null;
}

// Saved IDs in their saved order, then the rest in default order; `hidden` lists the ones turned off.
function ordered(list, saved, hidden) {
    const known = list.map(item => item.id);
    const order = [];
    for (const id of (Array.isArray(saved) ? saved : []).concat(Array.isArray(hidden) ? hidden : []))
        if (known.indexOf(id) >= 0 && order.indexOf(id) < 0)
            order.push(id);
    // One added in a later release goes after the items it follows by default.
    known.forEach((id, index) => {
        if (order.indexOf(id) >= 0)
            return;
        let at = 0;
        order.forEach((other, position) => {
            if (known.indexOf(other) < index)
                at = position + 1;
        });
        order.splice(at, 0, id);
    });
    const off = (Array.isArray(hidden) ? hidden : []).filter(id => known.indexOf(id) >= 0 && !(find(list, id).required));
    // Shown ones first: hidden ones are saved apart and keep no place of their own.
    const entries = order.map(id => ({id: id, shown: off.indexOf(id) < 0}));
    return entries.filter(entry => entry.shown).concat(entries.filter(entry => !entry.shown));
}

// {tiles, footer: [{id, shown}], sections: {focus, levels, media}} for a saved controlLayout.
function layout(saved) {
    saved = saved || {};
    const shownSections = {};
    for (const section of sections)
        shownSections[section.id] = !saved.sections || saved.sections[section.id] !== false;
    return {
        tiles: ordered(tiles, saved.tiles, saved.hiddenTiles),
        footer: ordered(footer, saved.footer, saved.hiddenFooter),
        sections: shownSections
    };
}

// The controlLayout setting for a layout() result.
function saved(current) {
    return {
        tiles: current.tiles.filter(item => item.shown).map(item => item.id),
        hiddenTiles: current.tiles.filter(item => !item.shown).map(item => item.id),
        sections: current.sections,
        footer: current.footer.filter(item => item.shown).map(item => item.id),
        hiddenFooter: current.footer.filter(item => !item.shown).map(item => item.id)
    };
}

// `setting` with an item of `part` ("tiles" or "footer") moved by `step` places, or shown or hidden.
function changed(setting, part, id, step, shown) {
    const current = layout(setting);
    const list = current[part];
    const index = list.findIndex(item => item.id === id);
    if (index < 0)
        return saved(current);
    if (step) {
        const entry = list.splice(index, 1)[0];
        list.splice(Math.max(0, Math.min(list.length, index + step)), 0, entry);
    }
    if (shown !== undefined) {
        const items = part === "tiles" ? tiles : footer;
        list[list.findIndex(item => item.id === id)].shown = shown || !!find(items, id).required;
    }
    return saved(current);
}

function section(setting, id, shown) {
    const current = layout(setting);
    current.sections[id] = shown;
    return saved(current);
}
