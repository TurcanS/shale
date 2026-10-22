.pragma library

// The Day hub drawn as a field station: the drum's trace and marks and the station's readings, as plain functions
// so they can run outside QML. Kept out of DayHub.qml also because qmllint stopped analysing that file while the
// painting code was inline.

// How far the pen swings for each recorded state, as a share of the half-height; time with no record barely moves it.
const SWING = {active: 0.9, watching: 0.4, idle: 0.08};
const UNRECORDED = 0.02;

// Today's trace from midnight up to `upTo`: [x, y] points, a zigzag step every 2 px. The swing of each step is
// fixed by its position, so the trace does not shimmer when it is repainted.
function trace(segments, dayStart, dayEnd, upTo, width, height) {
    const span = dayEnd - dayStart;
    const mid = height / 2;
    const reach = height / 2 - 4;
    const last = Math.min(width, (upTo - dayStart) / span * width);
    const points = [[0, mid]];
    let index = 0;
    for (let x = 0; x <= last; x += 2) {
        const at = dayStart + x / width * span;
        while (index < segments.length && segments[index].end <= at)
            index++;
        const segment = index < segments.length && segments[index].start <= at ? segments[index] : null;
        const noise = Math.abs(Math.sin(x * 12.9898) * 43758.5453) % 1;
        const amplitude = (segment ? SWING[segment.state] || SWING.idle : UNRECORDED) * (0.45 + 0.55 * noise) * reach;
        points.push([x, mid + ((x / 2) % 2 ? amplitude : -amplitude)]);
    }
    return points;
}

// The events still to come today, where they fall on the drum, and how much room each label has before the next.
function marks(items, dayStart, dayEnd, now, width) {
    const ahead = items.filter(item => item.at > now && item.at < dayEnd).sort((a, b) => a.at - b.at);
    const xs = ahead.map(item => Math.round((item.at - dayStart) / (dayEnd - dayStart) * width) + 0.5);
    return ahead.map((item, i) => ({x: xs[i], text: item.text.toUpperCase(), room: (i + 1 < xs.length ? xs[i + 1] : width) - xs[i] - 10}));
}

// The time-blocked orders (a time and a duration) still running or ahead today, as spans on the drum: x and width in
// pixels (never thinner than 3), with the title and how much room it has.
function blocks(orders, dayStart, dayEnd, now, width) {
    const span = dayEnd - dayStart;
    return orders.filter(order => !order.doneAt && !order.allDay && order.dueAt >= dayStart && order.dueAt < dayEnd && order.durationMin > 0
                         && order.dueAt + order.durationMin * 60000 > now)
        .sort((a, b) => a.dueAt - b.dueAt)
        .map(order => {
            const x = Math.round((order.dueAt - dayStart) / span * width);
            const end = Math.min(width, Math.round((order.dueAt + order.durationMin * 60000 - dayStart) / span * width));
            return {x: x, width: Math.max(3, end - x), text: order.text, id: order.id};
        });
}

// "T−0:25" while an event is under a day away, "Now" once it is due; past a day, "" (the weekday says more).
function countdown(at, now) {
    const minutes = Math.ceil((at - now) / 60000);
    if (minutes <= 0)
        return "Now";
    if (minutes >= 24 * 60)
        return "";
    return "T−" + Math.floor(minutes / 60) + ":" + String(minutes % 60).padStart(2, "0");
}

// Recorded time as "7 h 18".
function duration(seconds) {
    const minutes = Math.floor(seconds / 60);
    return Math.floor(minutes / 60) + " h " + String(minutes % 60).padStart(2, "0");
}

// Paints the drum. `drum` carries the size, the data, the colours (`accent`, `grid`, `ahead`, `event`, `stylus`),
// `glow` (false in power saver) and the label `font`.
function paint(ctx, drum) {
    const width = drum.width;
    const height = drum.height;
    const mid = Math.round(height / 2) + 0.5;
    ctx.reset();
    ctx.lineWidth = 1;
    ctx.strokeStyle = drum.grid;
    ctx.beginPath();
    for (let hour = 0; hour <= 24; hour++) {
        const x = Math.round(hour / 24 * width) + 0.5;
        ctx.moveTo(x, 0);
        ctx.lineTo(x, height);
    }
    for (let row = 0; row <= 4; row++) {
        const y = Math.round(row / 4 * height) + 0.5;
        ctx.moveTo(0, y);
        ctx.lineTo(width, y);
    }
    ctx.stroke();
    const stylus = Math.min(width, (drum.now - drum.dayStart) / (drum.dayEnd - drum.dayStart) * width);
    const points = trace(drum.segments, drum.dayStart, drum.dayEnd, drum.now, width, height);
    ctx.strokeStyle = drum.accent;
    ctx.lineWidth = 1.4;
    if (drum.glow) {
        ctx.shadowColor = drum.accent;
        ctx.shadowBlur = 6;
    }
    ctx.beginPath();
    ctx.moveTo(points[0][0], points[0][1]);
    for (let i = 1; i < points.length; i++)
        ctx.lineTo(points[i][0], points[i][1]);
    ctx.stroke();
    ctx.shadowBlur = 0;
    // What is still ahead: a faint dashed baseline, and a dashed mark with a label for each event due today.
    ctx.strokeStyle = drum.ahead;
    ctx.lineWidth = 1;
    ctx.beginPath();
    for (let x = stylus + 4; x < width; x += 9) {
        ctx.moveTo(x, mid);
        ctx.lineTo(Math.min(width, x + 4), mid);
    }
    ctx.stroke();
    ctx.font = drum.font;
    const events = marks(drum.items, drum.dayStart, drum.dayEnd, drum.now, width);
    for (let i = 0; i < events.length; i++) {
        const mark = events[i];
        ctx.strokeStyle = drum.event;
        ctx.beginPath();
        for (let y = 0; y < height; y += 7) {
            ctx.moveTo(mark.x, y);
            ctx.lineTo(mark.x, Math.min(height, y + 3));
        }
        ctx.stroke();
        // The label stops short of the next mark (or the edge) instead of running into it.
        let label = mark.text;
        while (label.length > 1 && ctx.measureText(label).width > mark.room)
            label = label.slice(0, -2) + "…";
        ctx.fillStyle = drum.event;
        ctx.fillText(label, mark.x + 4, 10);
    }
    // Blocks: hatched spans under the event marks, from the time to the end of the duration.
    const spans = blocks(drum.blocks || [], drum.dayStart, drum.dayEnd, drum.now, width);
    const top = Math.round(height * 0.55), bottom = Math.round(height * 0.9);
    for (let i = 0; i < spans.length; i++) {
        const block = spans[i];
        ctx.save();
        ctx.beginPath();
        ctx.rect(block.x, top, block.width, bottom - top);
        ctx.clip();
        ctx.fillStyle = drum.blockFill;
        ctx.fillRect(block.x, top, block.width, bottom - top);
        ctx.strokeStyle = drum.event;
        ctx.lineWidth = 1;
        ctx.beginPath();
        for (let x = block.x - (bottom - top); x < block.x + block.width; x += 5) {
            ctx.moveTo(x, bottom);
            ctx.lineTo(x + (bottom - top), top);
        }
        ctx.stroke();
        ctx.restore();
        ctx.strokeStyle = drum.event;
        ctx.strokeRect(block.x + 0.5, top + 0.5, Math.max(1, block.width - 1), bottom - top - 1);
    }
    // The stylus: a guide from the top and the pen on the line.
    ctx.strokeStyle = drum.stylus;
    ctx.beginPath();
    ctx.moveTo(Math.round(stylus) + 0.5, 0);
    ctx.lineTo(Math.round(stylus) + 0.5, mid - 5);
    ctx.stroke();
    ctx.fillStyle = drum.accent;
    ctx.beginPath();
    ctx.arc(stylus, mid, 3.5, 0, 2 * Math.PI);
    ctx.fill();
}

// How many of a gauge's `count` segments are lit for `percent` (0 to 100): any charge at all lights the first.
function lit(percent, count) {
    return Math.max(0, Math.min(count, Math.ceil(Math.max(0, percent) / 100 * count - 1e-9)));
}

// Where the Front (now) falls across `width`, the line the station lock splits along.
function front(now, dayStart, dayEnd, width) {
    return Math.round(Math.max(0, Math.min(1, (now - dayStart) / (dayEnd - dayStart))) * width);
}

// The station lock's readings. Anyone at the screen can read them, so an event's title is shown only with `titles`
// on, and the drum's events come back with nothing but their time and that same title or "".
// `items` are events {at, text}; `open` the count of open orders.
function lockReadings(items, open, now, titles, station) {
    const next = items.filter(item => item.at > now).sort((a, b) => a.at - b.at)[0];
    let nextText = "";
    if (next) {
        const when = countdown(next.at, now);
        const label = station ? "Next event" : "Next reminder";
        nextText = (when === "Now" ? label + " due now" : when === "" ? label + " in over a day" : label + " " + when)
            + (titles && next.text ? " · " + next.text : "");
    }
    const noun = station ? (open === 1 ? "order" : "orders") : (open === 1 ? "to-do" : "to-dos");
    return {
        next: nextText,
        open: open > 0 ? open + " " + noun + " open" : "No " + (station ? "orders" : "to-dos") + " open",
        items: items.map(item => ({at: item.at, text: titles ? item.text : ""}))
    };
}

// Station words, or the plain ones when they are off. The plain word is also what a screen reader and a tooltip say.
const WORDS = {
    quiet: ["QUIET", "Focus"], cleared: ["CLEARED", "Done"], onTarget: ["ON TARGET", "Target reached"],
    signals: ["Signals", "Notifications"], signalLog: ["Signal log", "Notifications"], console: ["Console", "Control center"],
    atmos: ["Atmos", "Weather"], recorder: ["Recorder", "Activity"], recorderOff: ["Recorder off", "Tracking off"],
    unattended: ["Station unattended", "Locked"], powerDown: ["Power down", "Shut down"], restart: ["Restart", "Restart"],
    signOff: ["Sign off", "Log out"], standBy: ["Stand by", "Suspend"], eventArrived: ["EVENT ARRIVED", "Reminder"],
    gauge: ["Gauge", "Level"], muted: ["MUTED", "Muted"]
};

function word(key, station) {
    const pair = WORDS[key];
    return pair ? pair[station ? 0 : 1] : key;
}

// The console's status sentence, from real state only: "All quiet. 3 work orders open, next event in 25 min, recorder on."
// `state` is {quiet, open, nextMinutes (null when none), recorder, station}.
function status(state) {
    const station = state.station !== false;
    const parts = [];
    parts.push(state.open + (state.open === 1 ? (station ? " work order" : " to-do") : (station ? " work orders" : " to-dos")) + " open");
    if (state.nextMinutes !== null && state.nextMinutes !== undefined) {
        const m = Math.max(0, Math.round(state.nextMinutes));
        const span = m >= 90 ? Math.round(m / 60) + " h" : m + " min";
        parts.push((station ? "next event in " : "next reminder in ") + span);
    }
    parts.push(state.recorder ? (station ? "recorder on" : "tracking on") : (station ? "recorder off" : "tracking off"));
    const lead = state.quiet ? (station ? "Quiet." : "Focus on.") : (station ? "All quiet." : "");
    return (lead ? lead + " " : "").concat(parts.join(", ").replace(/^./, c => lead ? c : c.toUpperCase()), ".");
}

// The power menu's report line: nothing when nothing is open; never blocks.
function powerReport(open, targets, station) {
    if (open <= 0)
        return "";
    const noun = open === 1 ? "order" : "orders";
    return (targets ? (station ? "Shift report not done. " : "Day report not done. ") : "") + open + " " + noun + " uncleared.";
}

// Ticks for the signal log's drum: one per notification today, x across the width, tall when urgent.
function ticks(items, dayStart, dayEnd, width) {
    const span = dayEnd - dayStart;
    return items.filter(item => item.at >= dayStart && item.at < dayEnd)
        .map(item => ({x: Math.round((item.at - dayStart) / span * width) + 0.5, urgent: !!item.urgent, id: item.id}))
        .sort((a, b) => a.x - b.x);
}
