.pragma library

// The Line along the bar's bottom edge: today's recorded time as bands on a fixed 24-hour scale, and the marks for
// what is planned or done. Plain functions so they can run outside QML.

// Local midnight to local midnight, so a day with a clock change is still 0 to 1 across the Line.
function dayBounds(now) {
    const date = new Date(now);
    const start = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
    const end = new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1).getTime();
    return {start: start, end: end};
}

function position(at, dayStart, dayEnd, width) {
    return Math.max(0, Math.min(width, (at - dayStart) / (dayEnd - dayStart) * width));
}

// One band per stretch of time up to `upTo`, as {x, width, state, app, start, end}. Stretches closer than a pixel
// keep a 1 px width so a short burst still shows.
function bands(segments, dayStart, dayEnd, upTo, width) {
    const result = [];
    for (const segment of segments) {
        if (segment.start >= upTo)
            break;
        const x = position(segment.start, dayStart, dayEnd, width);
        const right = position(Math.min(segment.end, upTo), dayStart, dayEnd, width);
        result.push({x: x, width: Math.max(1, right - x), state: segment.state, app: segment.app,
                     start: segment.start, end: Math.min(segment.end, upTo)});
    }
    return result;
}

// The band under `x`, or null. A gap of a pixel or two is forgiven so the pointer need not be exact.
function bandAt(list, x) {
    let best = null;
    let bestGap = 3;
    for (const band of list) {
        const gap = x < band.x ? band.x - x : x > band.x + band.width ? x - band.x - band.width : 0;
        if (gap < bestGap) {
            best = band;
            bestGap = gap;
        }
    }
    return best;
}

// What the Front shows: the state of the latest record when it is recent, idle otherwise.
function frontState(segments, now) {
    const last = segments.length ? segments[segments.length - 1] : null;
    return last && now - last.end < 150000 ? last.state : "idle";
}

// Marks for today's items, as {x, kind, text, at}. A fleck is a completed order, a tick a to-do with a time, a stone
// a reminder; `fired` stones are filled.
function marks(items, todos, dayStart, dayEnd, width) {
    const result = [];
    const seen = {};
    for (const item of items.concat(todos)) {
        if (seen[item.id])
            continue;
        seen[item.id] = true;
        let kind = "";
        let at = 0;
        if (item.doneAt && item.kind === "todo") {
            kind = "fleck";
            at = item.doneAt;
        } else if (item.kind === "reminder" && item.at) {
            kind = "stone";
            at = item.at;
        } else if (item.kind === "todo" && item.dueAt) {
            kind = "tick";
            at = item.dueAt;
        }
        if (!kind || at < dayStart || at >= dayEnd)
            continue;
        result.push({x: position(at, dayStart, dayEnd, width), kind: kind, text: item.text, at: at, fired: !!item.firedAt});
    }
    return result;
}

function markAt(list, x) {
    let best = null;
    let bestGap = 6;
    for (const mark of list) {
        const gap = Math.abs(mark.x - x);
        if (gap < bestGap) {
            best = mark;
            bestGap = gap;
        }
    }
    return best;
}

// "1 h 05", "12 min", "40 s".
function span(milliseconds) {
    const seconds = Math.round(milliseconds / 1000);
    if (seconds < 60)
        return seconds + " s";
    const minutes = Math.round(seconds / 60);
    return minutes < 60 ? minutes + " min" : Math.floor(minutes / 60) + " h " + String(minutes % 60).padStart(2, "0");
}

// The six apps with most time, in order, so the Line and Activity's day view colour them alike; the rest share the
// last colour.
function ranking(apps) {
    return apps.slice(0, 6).map(entry => entry.app);
}
