.pragma library
// What the bar can show, in its default places and order. helpers/backend.py (BAR_ITEMS) checks saved layouts
// against these IDs. Required items can move but never hide: what is recording or listening stays visible, and the
// control center button always leads back to Settings.
const items = [
    {id: "launcher", title: "Applications", icon: "grid", zone: "left", description: "Opens the launcher"},
    {id: "workspaces", title: "Workspaces", icon: "window", zone: "left", description: "The workspaces on this screen"},
    {id: "windowTitle", title: "Window title", icon: "window", zone: "left", description: "On screens wider than 1400 px"},
    {id: "clock", title: "Clock", icon: "calendar", zone: "center", description: "Opens the calendar"},
    {id: "media", title: "Now playing", icon: "music", zone: "right", description: "While something plays"},
    {id: "tray", title: "Tray icons", icon: "more", zone: "right", description: "Apps in the system tray"},
    {id: "recording", title: "Recording", icon: "record", zone: "right", required: true, description: "While recording the screen"},
    {id: "privacy", title: "Microphone and screen sharing", icon: "mic", zone: "right", required: true, description: "While an app listens or watches"},
    {id: "focus", title: "Focus", icon: "focus", zone: "right", description: "During a focus session"},
    {id: "timer", title: "Timers", icon: "timer", zone: "right", description: "While a timer runs"},
    {id: "stayAwake", title: "Stay awake", icon: "moon", zone: "right", description: "While the screen is kept on"},
    {id: "keyboard", title: "Keyboard layout", icon: "region", zone: "right", description: "With two or more layouts"},
    {id: "vpn", title: "VPN", icon: "shield", zone: "right", description: "While a VPN is connected"},
    {id: "wifi", title: "Wi-Fi", icon: "wifi", zone: "right"},
    {id: "audio", title: "Volume", icon: "volume", zone: "right", description: "Scroll to change, middle-click to mute"},
    {id: "battery", title: "Battery", icon: "battery", zone: "right", description: "On laptops"},
    {id: "notifications", title: "Notifications", icon: "bell", zone: "right"},
    {id: "control", title: "Control center", icon: "settings", zone: "right", required: true}
];
const zones = ["left", "center", "right", "hidden"];

function find(id) {
    return items.find(item => item.id === id) || null;
}

// A saved layout ({left, center, right, hidden}, any part missing) with every item placed once. An item the saved
// layout doesn't mention (one added in a later release) goes to its default zone, after the items it follows there.
function layout(saved) {
    const result = {left: [], center: [], right: [], hidden: []};
    const placed = {};
    for (const zone of zones)
        for (const id of (saved && Array.isArray(saved[zone]) ? saved[zone] : [])) {
            const item = find(id);
            if (!item || placed[id])
                continue;
            const target = zone === "hidden" && item.required ? item.zone : zone;
            result[target].push(id);
            placed[id] = true;
        }
    items.forEach((item, index) => {
        if (placed[item.id])
            return;
        const list = result[item.zone];
        const before = items.slice(0, index).map(other => other.id);
        let at = 0;
        list.forEach((id, position) => {
            if (before.indexOf(id) >= 0)
                at = position + 1;
        });
        list.splice(at, 0, item.id);
        placed[item.id] = true;
    });
    return result;
}

// `saved` with `id` moved to `zone` (at its end), or by `step` places within its zone.
function moved(saved, id, zone, step) {
    const current = layout(saved);
    const from = zones.find(name => current[name].indexOf(id) >= 0);
    const index = current[from].indexOf(id);
    if (zone && zone !== from) {
        current[from].splice(index, 1);
        current[zone].push(id);
    } else if (step) {
        const to = Math.max(0, Math.min(current[from].length - 1, index + step));
        current[from].splice(index, 1);
        current[from].splice(to, 0, id);
    }
    return current;
}
