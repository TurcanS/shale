.pragma library

// The island's queue of live activities, as plain functions so they can run outside QML. An entry is
// {kind, until, live}: `until` is when its expansion ends, `live` whether the thing is still going on (Quiet running,
// media playing) and so shows as a small bubble while another activity has the capsule.

// Lower comes first: an arrived event, then the gauges, then the rest ([16](16-station-shell.md) section 3a).
const PRIORITY = {event: 0, gauge: 1, saved: 2, quiet: 3, timer: 4, media: 5, cleared: 6};

function rank(kind) {
    return kind in PRIORITY ? PRIORITY[kind] : 99;
}

// A new entry replaces an older one of its kind.
function push(queue, entry) {
    return queue.filter(item => item.kind !== entry.kind).concat([entry]);
}

function drop(queue, kind) {
    return queue.filter(item => item.kind !== kind);
}

// What has ended its expansion and is no longer live is forgotten.
function prune(queue, now) {
    return queue.filter(item => item.until > now || item.live);
}

// `current` is the activity that has the capsule (the most important one still expanded), `bubble` the live one
// beside it, if any. While `blocked` (typing in the hub, fullscreen, presentation) nothing expands; the queue waits.
// `hovered` keeps a live activity that opens on hover (Quiet) expanded while the pointer is on the capsule. `resting`
// (the pointer has stayed a moment) opens the summary card when nothing else has the capsule.
function pick(queue, now, blocked, hovered, resting) {
    if (blocked)
        return {current: null, bubble: null};
    const expanded = queue.filter(item => item.until > now || (hovered && item.live && item.hover))
        .sort((a, b) => rank(a.kind) - rank(b.kind));
    const current = expanded.length ? expanded[0] : resting ? {kind: "summary", until: 0, live: false, hover: true} : null;
    const others = queue.filter(item => item.live && (!current || item.kind !== current.kind))
        .sort((a, b) => rank(a.kind) - rank(b.kind));
    return {current: current, bubble: others.length ? others[0] : null};
}

// The summary card's readings (16 section 3, Hover): the next three events still to come, the open count, the target
// and the time recorded today. `events` are {at, text}; `momentum` is Day.momentum or null; `recorded` in seconds.
function summary(events, open, momentum, recorded, recording, now, station) {
    const next = events.filter(event => event.at > now).sort((a, b) => a.at - b.at).slice(0, 3).map(event => {
        const minutes = Math.ceil((event.at - now) / 60000);
        return {at: event.at, text: event.text, soon: minutes <= 60 ? "T−" + Math.floor(minutes / 60) + ":" + String(minutes % 60).padStart(2, "0") : ""};
    });
    const noun = station ? (open === 1 ? " order" : " orders") : (open === 1 ? " to-do" : " to-dos");
    const minutes = Math.floor(recorded / 60);
    return {
        events: next,
        open: open + noun + " open",
        target: momentum && momentum.enabled && !momentum.dayOff && momentum.target > 0 ? "Target " + momentum.cleared + " of " + momentum.target : "",
        recorded: !recording ? (station ? "Recorder off" : "Tracking off")
                             : "Recorded " + Math.floor(minutes / 60) + " h " + String(minutes % 60).padStart(2, "0")
    };
}
