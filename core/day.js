.pragma library

// Capture text for the Day hub and the launcher, as plain functions so they can run outside QML. A time phrase at
// the start makes a reminder; anything else is a to-do. Text that starts like a time but is not one is refused with
// an explanation, never guessed.

const TEXT_LIMIT = 200;
const AHEAD_MS = 30 * 86400000;
const UNITS = {m: 60000, h: 3600000, d: 86400000, w: 604800000};
// Day numbers count from Sunday (0), as getDay() does.
const DAYS = {sun: 0, sunday: 0, mon: 1, monday: 1, tue: 2, tues: 2, tuesday: 2, wed: 3, weds: 3, wednesday: 3,
              thu: 4, thur: 4, thurs: 4, thursday: 4, fri: 5, friday: 5, sat: 6, saturday: 6};
const NAMES = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

// Milliseconds for "20m" or "1h30m"; null when the token is not a duration.
function duration(token) {
    if (!/^(\d+[mhdw])+$/i.test(token))
        return null;
    let total = 0;
    for (const part of token.toLowerCase().match(/\d+[mhdw]/g))
        total += Number(part.slice(0, -1)) * UNITS[part.slice(-1)];
    return total;
}

// {hour, minute} for "18:00", "9:30", "6pm" or "6:30pm"; a bare hour ("9") only where a time is expected.
// null when the token is not a time at all, {error} when it looks like one but is not valid.
function clock(token, bare) {
    const match = /^(\d{1,2})(?::(\d{2}))?(am|pm)?$/i.exec(token);
    if (!match)
        return /^\d+:/.test(token) || /^\d+(:\d+)?(am|pm)$/i.test(token) ? {error: "\"" + token + "\" is not a time."} : null;
    if (match[2] === undefined && match[3] === undefined && !bare)
        return null;
    let hour = Number(match[1]);
    const minute = match[2] === undefined ? 0 : Number(match[2]);
    if (match[3]) {
        if (hour < 1 || hour > 12)
            return {error: "\"" + token + "\" is not a time."};
        hour = hour % 12 + (match[3].toLowerCase() === "pm" ? 12 : 0);
    }
    if (hour > 23 || minute > 59)
        return {error: "\"" + token + "\" is not a time."};
    return {hour: hour, minute: minute};
}

// The local time `days` calendar days after `now`'s date; setDate and setHours keep daylight-saving days right.
function dayAt(now, days, time) {
    const date = new Date(now);
    date.setHours(0, 0, 0, 0);
    date.setDate(date.getDate() + days);
    date.setHours(time.hour, time.minute, 0, 0);
    return date.getTime();
}

function matches(day, repeat) {
    return repeat === "daily" || (repeat === "weekdays" ? day >= 1 && day <= 5 : day === Number(repeat.slice(7)));
}

function todo(text) {
    return text.length > TEXT_LIMIT ? {error: "Keep it under " + TEXT_LIMIT + " characters."} : {kind: "todo", text: text};
}

function reminder(rest, dueAt, repeat, moved) {
    const text = rest.join(" ");
    if (!text)
        return {error: "Add what to remind you of."};
    if (text.length > TEXT_LIMIT)
        return {error: "Keep it under " + TEXT_LIMIT + " characters."};
    return {kind: "reminder", text: text, dueAt: dueAt, repeat: repeat, tomorrow: moved};
}

// What the text means at `now` (epoch ms): {kind: "todo", text}, {kind: "reminder", text, dueAt, repeat, tomorrow}
// (tomorrow: a time already past today was moved to tomorrow), {error}, or null for empty text.
function parse(text, now) {
    const clean = String(text || "").trim().replace(/\s+/g, " ");
    if (!clean)
        return null;
    const tokens = clean.split(" ");
    const word = index => (tokens[index] || "").toLowerCase();
    if (word(0) === "in" && /^\d/.test(word(1))) {
        const length = duration(word(1));
        if (length === null)
            return {error: "\"" + tokens[1] + "\" is not a duration. Try in 20m or in 1h30m."};
        if (length <= 0 || length > AHEAD_MS)
            return {error: "Choose a time up to 30 days ahead."};
        return reminder(tokens.slice(2), now + length, null, false);
    }
    if (word(0) === "every") {
        const what = word(1);
        const repeat = what === "day" ? "daily" : what === "weekday" || what === "weekdays" ? "weekdays"
                     : DAYS.hasOwnProperty(what) ? "weekly:" + DAYS[what] : null;
        if (repeat === null)
            return todo(clean);
        const index = word(2) === "at" ? 3 : 2;
        const time = clock(tokens[index] || "", true);
        if (!time || time.error)
            return {error: time ? time.error : "Add a time, for example every day 8 vitamins."};
        let days = 0;
        while (!matches(new Date(dayAt(now, days, {hour: 12, minute: 0})).getDay(), repeat) || dayAt(now, days, time) <= now)
            days++;
        return reminder(tokens.slice(index + 1), dayAt(now, days, time), repeat, false);
    }
    const day = word(0) === "today" || word(0) === "tomorrow" || DAYS.hasOwnProperty(word(0)) ? word(0) : "";
    let index = day ? 1 : 0;
    const at = word(index) === "at";
    if (at)
        index++;
    const time = clock(tokens[index] || "", day !== "" || at);
    if (time === null)
        return todo(clean);
    if (time.error)
        return {error: time.error};
    let days = day === "tomorrow" ? 1 : DAYS.hasOwnProperty(day) ? (DAYS[day] - new Date(now).getDay() + 7) % 7 : 0;
    let moved = false;
    if (dayAt(now, days, time) <= now) {
        moved = days === 0 && !DAYS.hasOwnProperty(day);
        days += DAYS.hasOwnProperty(day) ? 7 : 1;
    }
    return reminder(tokens.slice(index + 1), dayAt(now, days, time), null, moved);
}

function two(value) {
    return String(value).padStart(2, "0");
}

// The live preview line: how the text was understood, for example "Reminder · today 18:00 · call mom".
function describe(parsed, now) {
    if (!parsed)
        return "";
    if (parsed.error)
        return parsed.error;
    if (parsed.kind === "todo")
        return "To-do · " + parsed.text;
    const due = new Date(parsed.dueAt);
    const time = two(due.getHours()) + ":" + two(due.getMinutes());
    if (parsed.repeat)
        return (parsed.repeat === "daily" ? "Every day" : parsed.repeat === "weekdays" ? "Every weekday"
                : "Every " + NAMES[Number(parsed.repeat.slice(7))]) + " · " + time + " · " + parsed.text;
    const today = new Date(now);
    today.setHours(0, 0, 0, 0);
    const start = new Date(parsed.dueAt);
    start.setHours(0, 0, 0, 0);
    const days = Math.round((start - today) / 86400000);
    const when = days === 0 ? "today" : days === 1 ? "tomorrow" : days < 7 ? NAMES[due.getDay()].slice(0, 3)
               : NAMES[due.getDay()].slice(0, 3) + " " + due.getDate() + " " + MONTHS[due.getMonth()];
    return "Reminder · " + when + " " + time + " · " + parsed.text;
}
