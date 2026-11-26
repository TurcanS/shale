.pragma library
// Parts: the cards the desktop can show, in their default order. One entry each: what Settings → Desktop lists,
// the card file features/Widgets.qml loads and its width, and the bar item (core/barItems.js) that shows the same
// thing on the bar, if any. helpers/backend.py (WIDGET_CARDS) checks saved lists against these IDs; add a new part
// there too. Every card is 214 px tall.
const parts = [
    {id: "clock", title: "Clock", icon: "clock", width: 250, source: "WidgetsClock.qml", bar: "clock",
     description: "The date, the time and how much of the day has gone"},
    {id: "sky", title: "Sky", icon: "cloud-sun", width: 290, source: "WidgetsSky.qml", bar: "",
     description: "The weather and the sun's path for the city in Clock and sky"},
    {id: "note", title: "Note", icon: "note", width: 260, source: "WidgetsNote.qml", bar: "",
     description: "One running note; type note and a line in Find to add to it"},
    {id: "system", title: "System", icon: "gauge", width: 200, source: "WidgetsSystem.qml", bar: "",
     description: "Processor, memory and temperature, every few seconds"},
    {id: "player", title: "Player", icon: "music", width: 300, source: "WidgetsPlayer.qml", bar: "media",
     description: "What is playing, with its cover and the play keys"},
    {id: "timers", title: "Timers", icon: "timer", width: 220, source: "WidgetsTimers.qml", bar: "timer",
     description: "Running timers and the focus session; type timer 10m in Find to start one"}
];
const defaults = ["clock", "sky", "note", "system"];
const maximum = 6;
// Ready-made sets. A set is chosen when the shown cards are exactly its cards; "Mine" is the set saved in
// Settings → Desktop (the widgetSaved setting).
const layouts = [
    {id: "work", title: "Work", cards: ["clock", "note", "timers", "system"], description: "Clock, note, timers"},
    {id: "play", title: "Play", cards: ["system", "player", "clock"], description: "System, player, clock"},
    {id: "evening", title: "Evening", cards: ["clock", "sky", "player"], description: "Sky and music"}
];

function find(id) {
    return parts.find(part => part.id === id) || null;
}

// A saved list with unknown or repeated IDs dropped, at most `maximum` long.
function clean(list) {
    const seen = {};
    return (Array.isArray(list) ? list : []).filter(id => {
        if (!find(id) || seen[id])
            return false;
        seen[id] = true;
        return true;
    }).slice(0, maximum);
}

function same(a, b) {
    return a.length === b.length && a.every((id, i) => id === b[i]);
}

// The layout whose cards are exactly `cards`, "mine" when they match the saved set, or "".
function layoutOf(cards, saved) {
    const shown = clean(cards);
    const preset = layouts.find(layout => same(layout.cards, shown));
    if (preset)
        return preset.id;
    return saved && saved.length && same(clean(saved), shown) ? "mine" : "";
}

// "work", "Evening" or a unique start of a name ("eve") → the layout's id; "mine" for the saved set; "" otherwise.
function layoutNamed(name) {
    const wanted = String(name || "").trim().toLowerCase();
    if (!wanted)
        return "";
    if ("mine".startsWith(wanted))
        return "mine";
    const matches = layouts.filter(layout => layout.id.startsWith(wanted) || layout.title.toLowerCase().startsWith(wanted));
    return matches.length === 1 ? matches[0].id : "";
}
