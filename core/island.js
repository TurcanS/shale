.pragma library

// The island's queue of live activities, as plain functions so they can run outside QML. An entry is
// {kind, until, live}: `until` is when its expansion ends, `live` whether the thing is still going on (Quiet running,
// media playing) and so shows as a small bubble while another activity has the capsule.

// Lower comes first: an arrived event, then the gauges, then the rest ([16](16-station-shell.md) section 3a).
const PRIORITY = {event: 0, gauge: 1, quiet: 2, timer: 3, media: 4, cleared: 5};

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
// `hovered` keeps a live activity that opens on hover (Quiet) expanded while the pointer is on the capsule.
function pick(queue, now, blocked, hovered) {
    if (blocked)
        return {current: null, bubble: null};
    const expanded = queue.filter(item => item.until > now || (hovered && item.live && item.hover))
        .sort((a, b) => rank(a.kind) - rank(b.kind));
    const current = expanded.length ? expanded[0] : null;
    const others = queue.filter(item => item.live && (!current || item.kind !== current.kind))
        .sort((a, b) => rank(a.kind) - rank(b.kind));
    return {current: current, bubble: others.length ? others[0] : null};
}
