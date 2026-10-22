.pragma library

// The Dig: the layers of a week, a month or a year, and the marks inside them. Plain functions so they run outside QML.

const LEVELS = ["week", "month", "year"];

// Local midnight of an ISO day, as milliseconds.
function midnight(day) {
    const parts = day.split("-").map(Number);
    return new Date(parts[0], parts[1] - 1, parts[2]).getTime();
}

function isoDay(date) {
    return date.getFullYear() + "-" + String(date.getMonth() + 1).padStart(2, "0") + "-" + String(date.getDate()).padStart(2, "0");
}

// The day to anchor on after moving `step` periods: a week by 7 days, a month or a year by calendar. A month never
// lands past its end (31 January + 1 month is 28 February).
function shiftAnchor(level, day, step) {
    const parts = day.split("-").map(Number);
    if (level === "week")
        return isoDay(new Date(parts[0], parts[1] - 1, parts[2] + 7 * step));
    const months = level === "month" ? step : 12 * step;
    const target = new Date(parts[0], parts[1] - 1 + months, 1);
    const last = new Date(target.getFullYear(), target.getMonth() + 1, 0).getDate();
    return isoDay(new Date(target.getFullYear(), target.getMonth(), Math.min(parts[2], last)));
}

// One level deeper (`step` 1: week, month, year) or back up (-1); it stops at either end.
function shiftLevel(level, step) {
    return LEVELS[Math.max(0, Math.min(LEVELS.length - 1, LEVELS.indexOf(level) + step))];
}

// 0 to 1 across the local day of `day`, so a day with a clock change still fills the row.
function fraction(at, day) {
    const start = midnight(day);
    const parts = day.split("-").map(Number);
    const end = new Date(parts[0], parts[1] - 1, parts[2] + 1).getTime();
    return Math.max(0, Math.min(1, (at - start) / (end - start)));
}

// A day's marks placed across a row `width` wide. Shapes are chosen by the view, so nothing here depends on colour.
function layout(entry, width) {
    const at = value => fraction(value, entry.date) * width;
    return {
        bands: (entry.bands || []).map(band => ({x: at(band.start), width: Math.max(1, at(band.end) - at(band.start)),
                                                 state: band.state, app: band.app, start: band.start, end: band.end})),
        grains: (entry.grains || []).map(grain => ({x: at(grain.at), at: grain.at, app: grain.app, urgent: grain.urgency === 2})),
        veins: (entry.veins || []).map(vein => ({x: at(vein.start), width: Math.max(2, at(vein.end) - at(vein.start)),
                                                 start: vein.start, end: vein.end, orderId: vein.orderId})),
        flecks: (entry.flecks || []).map(fleck => ({x: at(fleck.at), at: fleck.at})),
        glints: (entry.glints || []).map(glint => ({x: at(glint.at), at: glint.at, kind: glint.kind}))
    };
}

// Rows from newest to oldest. A week's rows are all as tall as `rowHeight`; a month's are as thick as the day's active
// time, between `thin` and `rowHeight`, and shrink together when the month would not fit in `available`.
function rows(days, level, rowHeight, thin, available) {
    const newest = days.slice().reverse();
    let heights;
    if (level === "week") {
        heights = newest.map(() => rowHeight);
    } else {
        const longest = Math.max(1, ...newest.map(entry => entry.active + entry.watching));
        heights = newest.map(entry => Math.max(thin, (entry.active + entry.watching) / longest * rowHeight));
        // Only the thickness above the thin floor shrinks, so every day stays visible.
        const gaps = newest.length - 1;
        const floor = newest.length * thin + gaps;
        const extra = heights.reduce((sum, value) => sum + value - thin, 0);
        if (floor + extra > available && extra > 0) {
            const scale = Math.max(0, (available - floor) / extra);
            heights = heights.map(value => thin + (value - thin) * scale);
        }
    }
    let y = 0;
    return newest.map((entry, index) => {
        const row = {date: entry.date, y: y, height: heights[index], entry: entry};
        y += heights[index] + 1;
        return row;
    });
}

// A year as one column per day, left to right, each `width / days` wide. `level` 0 to 4 is how much of the day was
// recorded, so a quiet day is dimmer than a full one.
function columns(days, width) {
    const unit = width / Math.max(1, days.length);
    const longest = Math.max(1, ...days.map(entry => entry.active + entry.watching));
    return days.map((entry, index) => {
        const seconds = entry.active + entry.watching;
        return {date: entry.date, x: index * unit, width: Math.max(1, unit - (unit > 3 ? 1 : 0)), app: entry.dominant, seconds: seconds,
                level: seconds <= 0 ? 0 : Math.max(1, Math.ceil(seconds / longest * 4)), vein: entry.veinsCount > 0,
                noted: !!entry.note, entry: entry};
    });
}

// The column or row under a pointer: the column whose span holds `x`, or the nearest.
function columnAt(list, x) {
    let best = null;
    for (const column of list) {
        if (x >= column.x && x < column.x + column.width + 1)
            return column;
        if (!best || Math.abs(x - column.x) < Math.abs(x - best.x))
            best = column;
    }
    return best;
}

function rowAt(list, y) {
    for (const row of list) {
        if (y >= row.y && y < row.y + row.height + 1)
            return row;
    }
    return list.length ? list[list.length - 1] : null;
}

// One line about a day, for the tooltip and the caption: "Tue 20 Oct · 5 h 30 min · kitty · 2 veins".
function describe(entry) {
    const parts = [];
    const seconds = entry.active + entry.watching;
    const minutes = Math.round(seconds / 60);
    parts.push(seconds <= 0 ? "nothing recorded" : minutes < 60 ? minutes + " min" : Math.floor(minutes / 60) + " h " + String(minutes % 60).padStart(2, "0"));
    if (entry.dominant)
        parts.push(entry.dominant);
    const counts = [["grains", "grain"], ["veins", "vein"], ["flecks", "fleck"], ["glints", "glint"]];
    for (const pair of counts) {
        const count = entry[pair[0] + "Count"] || 0;
        if (count)
            parts.push(count + " " + pair[1] + (count === 1 ? "" : "s"));
    }
    return parts.join("  ·  ");
}

// The first day of each month among a year's columns, for the labels under it.
function monthMarks(list) {
    return list.filter(column => column.date.endsWith("-01")).map(column => ({x: column.x, date: column.date}));
}
