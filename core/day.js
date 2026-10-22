.pragma library

// Capture text for the Day hub and the launcher, as plain functions so they can run outside QML. A time phrase at
// the start makes a reminder; anything else is a to-do. Text that starts like a time but is not one is refused with
// an explanation, never guessed.

const TEXT_LIMIT = 500;
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

// What a fired reminder says as a signal: the stamped header with the time it was due, and its text. One missed
// while the shell was off, asleep or locked says so, with the day when it was not today.
function arrival(item, now) {
    const due = new Date(item.at);
    const today = new Date(now);
    const sameDay = due.toDateString() === today.toDateString();
    const time = two(due.getHours()) + ":" + two(due.getMinutes());
    return {
        header: (item.away ? "WHILE YOU WERE AWAY · " : "EVENT ARRIVED · ") + (sameDay ? "" : NAMES[due.getDay()].slice(0, 3) + " ") + time,
        summary: item.text,
        body: item.away ? "Due " + (sameDay ? "at " : NAMES[due.getDay()] + " ") + time : ""
    };
}

// The keys on an arrived event, with the time each snooze moves it to. Tomorrow keeps the clock time it was due.
function choices(item, now) {
    const due = new Date(item.at);
    const tomorrow = new Date(now);
    tomorrow.setDate(tomorrow.getDate() + 1);
    tomorrow.setHours(due.getHours(), due.getMinutes(), 0, 0);
    return [
        {identifier: "snooze10", text: "Snooze 10 min", until: now + 600000},
        {identifier: "snooze60", text: "1 h", until: now + 3600000},
        {identifier: "tomorrow", text: "Tomorrow", until: tomorrow.getTime()},
        {identifier: "clear", text: "Clear", until: 0}
    ];
}

// Version 2 of the grammar, for work orders: tokens anywhere in the text, each kept as a span so the preview can
// highlight it; everything else is the title. Quotes keep text literal. One due, one deadline, one duration, one
// site, one magnitude and one repeat; a second one is refused with the reason.

const MONTH_WORDS = {jan: 1, january: 1, feb: 2, february: 2, mar: 3, march: 3, apr: 4, april: 4, may: 5, jun: 6,
                     june: 6, jul: 7, july: 7, aug: 8, august: 8, sep: 9, sept: 9, september: 9, oct: 10, october: 10,
                     nov: 11, november: 11, dec: 12, december: 12};
// Rule day codes by getDay().
const CODES = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"];
const PLACES = {first: 1, "1st": 1, second: 2, "2nd": 2, third: 3, "3rd": 3, fourth: 4, "4th": 4, last: -1};
const UNIT_FREQS = {day: "DAILY", days: "DAILY", week: "WEEKLY", weeks: "WEEKLY", month: "MONTHLY", months: "MONTHLY",
                    year: "YEARLY", years: "YEARLY"};
const SECOND = {due: "due date", deadline: "deadline", duration: "duration", site: "site", magnitude: "magnitude",
                repeat: "repeat"};

// Local midnight `days` calendar days after `now`'s date.
function startOf(now, days) {
    return dayAt(now, days, {hour: 0, minute: 0});
}

// Local midnight of a calendar date, or null when there is no such day (31 February).
function calendarDay(year, month, day) {
    const date = new Date(year, month - 1, day);
    return date.getFullYear() === year && date.getMonth() === month - 1 && date.getDate() === day ? date.getTime() : null;
}

// A date without a year is the next one from today on.
function nextDate(month, day, year, now, token) {
    const thisYear = new Date(now).getFullYear();
    let date = year ? calendarDay(year, month, day) : calendarDay(thisYear, month, day);
    if (!year && (date === null || date < startOf(now, 0)))
        date = calendarDay(thisYear + 1, month, day) || (date !== null ? null : calendarDay(thisYear + 4 - thisYear % 4, month, day));
    return date === null ? {error: "\"" + token + "\" is not a date."} : {day: date};
}

function ordinal(word) {
    const match = /^(\d{1,2})(st|nd|rd|th)?$/.exec(word || "");
    return match ? Number(match[1]) : null;
}

// A date phrase at words[i]: {length, day (local midnight), today, weekday}, {length, error}, or null.
function datePart(words, i, now, options) {
    const word = words[i] || "", following = words[i + 1] || "";
    if (word === "today" || word === "tod")
        return {length: 1, day: startOf(now, 0), today: true};
    if (word === "tomorrow" || word === "tom")
        return {length: 1, day: startOf(now, 1)};
    if (DAYS.hasOwnProperty(word))
        return {length: 1, day: startOf(now, (DAYS[word] - new Date(now).getDay() + 7) % 7), weekday: DAYS[word]};
    if (word === "next" && following === "week")
        return {length: 2, day: startOf(now, (8 - new Date(now).getDay()) % 7 || 7)};
    if (word === "in" && /^\d+$/.test(following) && /^(days?|weeks?|months?)$/.test(words[i + 2] || "")) {
        const count = Number(following), unit = words[i + 2][0];
        if (count < 1 || count > 3650)
            return {length: 3, error: "Choose a day up to ten years ahead."};
        if (unit !== "m")
            return {length: 3, day: startOf(now, count * (unit === "w" ? 7 : 1))};
        const date = new Date(startOf(now, 0));
        const target = date.getDate();
        date.setMonth(date.getMonth() + count, 1);
        date.setDate(Math.min(target, new Date(date.getFullYear(), date.getMonth() + 1, 0).getDate()));
        return {length: 3, day: date.getTime()};
    }
    if (MONTH_WORDS.hasOwnProperty(word) && ordinal(following) !== null)
        return Object.assign({length: 2}, nextDate(MONTH_WORDS[word], ordinal(following), 0, now, word + " " + following));
    if (ordinal(word) !== null && MONTH_WORDS.hasOwnProperty(following))
        return Object.assign({length: 2}, nextDate(MONTH_WORDS[following], ordinal(word), 0, now, word + " " + following));
    // Dotted dates are always day first; slashed ones follow the locale.
    let match = /^(\d{1,2})\.(\d{1,2})\.(\d{4})?$/.exec(word);
    if (match)
        return Object.assign({length: 1}, nextDate(Number(match[2]), Number(match[1]), Number(match[3] || 0), now, word));
    match = /^(\d{1,2})\/(\d{1,2})(?:\/(\d{4}))?$/.exec(word);
    if (match) {
        const dayFirst = options && options.dayFirst === true;
        const found = nextDate(Number(match[dayFirst ? 2 : 1]), Number(match[dayFirst ? 1 : 2]), Number(match[3] || 0), now, word);
        if (found.error)
            found.error += dayFirst ? " Dates here are day first, as 28/10." : " Dates here are month first, as 10/28.";
        return Object.assign({length: 1}, found);
    }
    if (/^\d{1,2}\.\d{1,2}\.\d*$/.test(word) || /^\d+\/\d+(\/\d*)?$/.test(word))
        return {length: 1, error: "\"" + word + "\" is not a date."};
    return null;
}

// A clock time at words[i]: "18:00", "6pm", or "at" with a bare hour. {length, hour, minute}, {length, error} or null.
function timePart(words, i) {
    const at = words[i] === "at" ? 1 : 0;
    const time = clock(words[i + at] || "", at === 1);
    if (time === null)
        return null;
    return Object.assign({length: at + 1}, time);
}

function atTime(day, time) {
    const date = new Date(day);
    date.setHours(time.hour, time.minute, 0, 0);
    return date.getTime();
}

// A due phrase: a date, a time, both, or "in 20m". {length, dueAt, allDay, tomorrow}, {length, error} or null.
function duePart(words, i, now, options) {
    if (words[i] === "in" && /^\d/.test(words[i + 1] || "") && !/^(days?|weeks?|months?)$/.test(words[i + 2] || "")) {
        const length = duration(words[i + 1]);
        if (length === null || /[dw]/.test(words[i + 1]))
            return {length: 2, error: "\"" + words[i + 1] + "\" is not a duration. Try in 20m or in 1h30m."};
        if (length <= 0 || length > AHEAD_MS)
            return {length: 2, error: "Choose a time up to 30 days ahead."};
        return {length: 2, dueAt: now + length, allDay: false, tomorrow: false};
    }
    const date = datePart(words, i, now, options);
    if (date && date.error)
        return date;
    const used = date ? date.length : 0;
    const time = timePart(words, i + used);
    if (time && time.error)
        return {length: used + time.length, error: time.error};
    if (!time)
        return date ? {length: used, dueAt: date.day, allDay: true, tomorrow: false} : null;
    let dueAt = atTime(date ? date.day : startOf(now, 0), time);
    let moved = false;
    if (dueAt <= now && (!date || date.today || date.weekday !== undefined)) {
        moved = !date || date.today === true;
        dueAt = atTime(startOf(dueAt, moved ? 1 : 7), time);
    }
    return {length: used + time.length, dueAt: dueAt, allDay: false, tomorrow: moved};
}

// "mon, thu", "mon,thu" or "mon and thu": {length, codes} or null.
function weekdayList(words, i) {
    const codes = [];
    let j = i;
    while (j < words.length) {
        const names = words[j].split(",").filter(name => name);
        if (!names.length || !names.every(name => DAYS.hasOwnProperty(name)))
            break;
        for (const name of names)
            if (codes.indexOf(CODES[DAYS[name]]) < 0)
                codes.push(CODES[DAYS[name]]);
        j++;
        if (words[j] === "and" && DAYS.hasOwnProperty((words[j + 1] || "").split(",")[0]))
            j++;
    }
    return codes.length ? {length: j - i, codes: codes} : null;
}

// The monthly day after "on" or "every": "the 1st", "15th", "last day", "last fri". Fills the rule; the words used.
function monthDay(words, i, rule) {
    const skip = words[i] === "the" ? 1 : 0;
    const word = words[i + skip] || "", following = words[i + skip + 1] || "";
    if (PLACES.hasOwnProperty(word) && DAYS.hasOwnProperty(following)) {
        rule.days = [String(PLACES[word]) + CODES[DAYS[following]]];
        return skip + 2;
    }
    if (word === "last" && following === "day") {
        rule.monthday = -1;
        return skip + 2;
    }
    const day = /(st|nd|rd|th)$/.test(word) ? ordinal(word) : null;
    if (day !== null && day >= 1 && day <= 31) {
        rule.monthday = day;
        return skip + 1;
    }
    return 0;
}

// A repeat phrase starting at "every" or "every!": {length, rule (parts), time, end} or {length, error}, or null when
// the words after "every" are not a repeat ("every little thing" stays a title).
function repeatPart(words, i, now, options) {
    const rule = {freq: null, interval: 1, days: [], monthday: null, month: null, until: null, count: null,
                  fromDone: words[i] === "every!"};
    let j = i + 1;
    const word = () => words[j] || "";
    if ((word() === "other" || /^\d+$/.test(word())) && UNIT_FREQS.hasOwnProperty(words[j + 1] || "")) {
        rule.interval = word() === "other" ? 2 : Number(word());
        if (rule.interval < 1 || rule.interval > 99)
            return {length: 3, error: "Choose an interval from 1 to 99."};
        rule.freq = UNIT_FREQS[words[j + 1]];
        j += 2;
    } else if (word() === "weekday" || word() === "weekdays") {
        rule.freq = "WEEKLY";
        rule.days = ["MO", "TU", "WE", "TH", "FR"];
        j++;
    } else if (UNIT_FREQS.hasOwnProperty(word())) {
        rule.freq = UNIT_FREQS[word()];
        j++;
    } else if (weekdayList(words, j)) {
        const list = weekdayList(words, j);
        rule.freq = "WEEKLY";
        rule.days = list.codes;
        j += list.length;
    } else {
        const used = monthDay(words, j, rule);
        if (!used)
            return null;
        rule.freq = "MONTHLY";
        j += used;
    }
    if (word() === "on") {
        let used = 0;
        if (rule.freq === "WEEKLY" && weekdayList(words, j + 1)) {
            const list = weekdayList(words, j + 1);
            rule.days = list.codes;
            used = list.length;
        } else if (rule.freq === "MONTHLY") {
            used = monthDay(words, j + 1, rule);
        } else if (rule.freq === "YEARLY") {
            const date = datePart(words, j + 1, now, options);
            if (date && !date.error && date.length === 2) {
                const day = new Date(date.day);
                rule.month = day.getMonth() + 1;
                rule.monthday = day.getDate();
                used = 2;
            }
        }
        if (!used)
            return {length: j - i + 2, error: "Say which day the repeat falls on, for example every month on the 1st."};
        j += used + 1;
    }
    if (rule.fromDone && (rule.days.length || rule.monthday || rule.month))
        return {length: j - i, error: "Counting from the day it was cleared works with plain intervals, as every! 3 days."};
    const time = timePart(words, j);
    if (time && time.error)
        return {length: j - i + time.length, error: time.error};
    if (time)
        j += time.length;
    if (word() === "until") {
        const end = datePart(words, j + 1, now, options);
        if (!end || end.error)
            return {length: j - i + 1 + (end ? end.length : 0), error: end ? end.error : "Say when the repeat ends, as until dec 31."};
        const day = new Date(end.day);
        rule.until = String(day.getFullYear()) + two(day.getMonth() + 1) + two(day.getDate());
        j += 1 + end.length;
    } else if (/^\d+$/.test(word()) && words[j + 1] === "times") {
        rule.count = Number(word());
        if (rule.count < 1 || rule.count > 999)
            return {length: j - i + 2, error: "Choose from 1 to 999 times."};
        j += 2;
    }
    return {length: j - i, rule: rule, time: time};
}

// The rule string the helper stores: a small subset of iCalendar's RRULE.
function ruleText(rule) {
    const parts = ["FREQ=" + rule.freq];
    if (rule.interval > 1)
        parts.push("INTERVAL=" + rule.interval);
    if (rule.days.length)
        parts.push("BYDAY=" + rule.days.join(","));
    if (rule.month)
        parts.push("BYMONTH=" + rule.month);
    if (rule.monthday)
        parts.push("BYMONTHDAY=" + rule.monthday);
    if (rule.until)
        parts.push("UNTIL=" + rule.until);
    if (rule.count)
        parts.push("COUNT=" + rule.count);
    return parts.join(";");
}

// Whether a day can start the series: its weekday, month day or month fit the rule (the interval counts from it).
function fits(day, rule) {
    const date = new Date(day);
    if (rule.freq === "WEEKLY")
        return !rule.days.length || rule.days.indexOf(CODES[date.getDay()]) >= 0;
    if (rule.month && date.getMonth() + 1 !== rule.month)
        return false;
    const last = new Date(date.getFullYear(), date.getMonth() + 1, 0).getDate();
    if (rule.days.length) {
        const place = Number(rule.days[0].slice(0, -2));
        return CODES[date.getDay()] === rule.days[0].slice(-2)
            && (place === -1 ? date.getDate() + 7 > last : Math.floor((date.getDate() - 1) / 7) + 1 === place);
    }
    return !rule.monthday || date.getDate() === (rule.monthday === -1 ? last : rule.monthday);
}

// The first occurrence from today on: at the repeat's time when it has one, else as an all-day date.
function firstOccurrence(rule, time, now) {
    for (let days = 0; days < 3000; days++) {
        const day = startOf(now, days);
        if (fits(day, rule) && (!time || atTime(day, time) > now))
            return time ? atTime(day, time) : day;
    }
    return null;
}

// What one token at pieces[i] is: {length, kind, ...} or null for a title word.
function token(pieces, words, i, now, options) {
    const raw = pieces[i].quoted ? "" : pieces[i].text;
    let match = /^#([^\s#@/]+)(?:\/([^\s#@/]+))?$/.exec(raw);
    if (match)
        return {length: 1, kind: "site", site: match[1], section: match[2] || null};
    match = /^@([^\s#@]+)$/.exec(raw);
    if (match)
        return {length: 1, kind: "tag", tag: match[1]};
    if (/^[p!][1-4]$/i.test(raw))
        return {length: 1, kind: "magnitude", priority: 5 - Number(raw[1])};
    if (words[i] === "every" || words[i] === "every!") {
        const repeat = repeatPart(words, i, now, options);
        return repeat && Object.assign(repeat, {kind: "repeat"});
    }
    if ((words[i] === "by" || words[i] === "deadline") && datePart(words, i + 1, now, options)) {
        const date = datePart(words, i + 1, now, options);
        return {length: date.length + 1, kind: "deadline", error: date.error, deadlineAt: date.day};
    }
    if (words[i] === "for" && /^\d/.test(words[i + 1] || "")) {
        const length = /^(\d+[mh])+$/.test(words[i + 1]) ? duration(words[i + 1]) / 60000 : null;
        if (length === null)
            return {length: 2, kind: "duration", error: "\"" + words[i + 1] + "\" is not a duration. Try for 45m or for 1h30m."};
        if (length < 1 || length > 1440)
            return {length: 2, kind: "duration", error: "Choose a duration up to 24 hours."};
        return {length: 2, kind: "duration", durationMin: length};
    }
    if (words[i] === "remind") {
        const before = duration(words[i + 1] || "");
        if (before !== null && words[i + 2] === "before" && !/[dw]/.test(words[i + 1]))
            return before > 10080 * 60000 ? {length: 3, kind: "alert", error: "Choose an alert up to a week before."}
                                          : {length: 3, kind: "alert", beforeMin: before / 60000};
        const time = timePart(words, i + 1);
        return time && Object.assign({length: time.length + 1, kind: "alert"}, time.error ? {error: time.error} : {time: time});
    }
    const due = duePart(words, i, now, options);
    return due && Object.assign(due, {kind: "due"});
}

// What the text means at `now` (epoch ms): the fields of a work order for the helper's day.add (kind "todo"), plus
// `spans` (each recognised token, for the highlighted preview), `errors` (each with the reason) and `error` (the
// first reason, or null). `tomorrow`: a time already past today was moved to tomorrow. `newSite`: #name is not one of
// options.sites, so the preview asks before it is created. options.dayFirst: the locale writes 28/10, not 10/28.
// null for empty text.
function capture(text, now, options) {
    const source = String(text || "");
    const pieces = [];
    const pattern = /"[^"]*(?:"|$)|\S+/g;
    let found;
    while ((found = pattern.exec(source)) !== null)
        pieces.push({text: found[0], start: found.index, end: found.index + found[0].length, quoted: found[0][0] === "\""});
    if (!pieces.length)
        return null;
    const words = pieces.map(piece => piece.quoted ? "" : piece.text.toLowerCase());
    const order = {kind: "todo", text: "", site: null, section: null, newSite: false, tags: [], priority: 1, dueAt: null,
                   allDay: false, deadlineAt: null, durationMin: null, rule: null, ruleFromDone: false, alerts: [],
                   tomorrow: false, spans: [], errors: [], error: null};
    const title = [], reminds = [], seen = {};
    let repeat = null;
    for (let i = 0; i < pieces.length;) {
        const part = token(pieces, words, i, now, options || {});
        if (!part) {
            title.push(pieces[i].quoted ? pieces[i].text.replace(/^"|"$/g, "") : pieces[i].text);
            i++;
            continue;
        }
        const end = pieces[Math.min(i + part.length, pieces.length) - 1].end;
        const span = {start: pieces[i].start, end: end, kind: part.kind, text: source.slice(pieces[i].start, end)};
        i += part.length;
        if (!part.error && SECOND.hasOwnProperty(part.kind) && seen[part.kind])
            part.error = "One " + SECOND[part.kind] + " per order: \"" + span.text + "\" would be a second.";
        if (part.error) {
            order.errors.push(Object.assign(span, {note: part.error}));
            continue;
        }
        seen[part.kind] = true;
        order.spans.push(span);
        if (part.kind === "site") {
            order.site = part.site;
            order.section = part.section;
            order.newSite = !((options && options.sites) || []).some(name => name.toLowerCase() === part.site.toLowerCase());
        } else if (part.kind === "tag") {
            if (!order.tags.some(tag => tag.toLowerCase() === part.tag.toLowerCase()))
                order.tags.push(part.tag);
        } else if (part.kind === "magnitude") {
            order.priority = part.priority;
        } else if (part.kind === "deadline") {
            order.deadlineAt = part.deadlineAt;
        } else if (part.kind === "duration") {
            order.durationMin = part.durationMin;
        } else if (part.kind === "alert") {
            reminds.push(Object.assign(part, {span: span}));
        } else if (part.kind === "repeat") {
            repeat = part;
        } else {
            order.dueAt = part.dueAt;
            order.allDay = part.allDay;
            order.tomorrow = part.tomorrow;
        }
    }
    order.text = title.join(" ").trim();
    if (repeat) {
        order.rule = ruleText(repeat.rule);
        order.ruleFromDone = repeat.rule.fromDone;
        if (order.dueAt === null) {
            order.dueAt = firstOccurrence(repeat.rule, repeat.time, now);
            order.allDay = !repeat.time;
        } else if (repeat.time && order.allDay) {
            order.dueAt = atTime(order.dueAt, repeat.time);
            order.allDay = false;
        }
    }
    for (const remind of reminds) {
        if (remind.beforeMin !== undefined) {
            if (order.dueAt === null || order.allDay)
                order.errors.push(Object.assign(remind.span, {note: "An alert before the due time needs a due time."}));
            else
                order.alerts.push({beforeMin: remind.beforeMin});
            continue;
        }
        // At that time on the due day, or the next time it comes.
        let at = atTime(order.dueAt !== null ? order.dueAt : startOf(now, 0), remind.time);
        if (at <= now && order.dueAt === null)
            at = atTime(startOf(now, 1), remind.time);
        order.alerts.push({at: at});
    }
    if (!order.text)
        order.errors.push({start: null, end: null, kind: "title", text: "", note: "Add what the order is."});
    else if (order.text.length > TEXT_LIMIT)
        order.errors.push({start: null, end: null, kind: "title", text: "", note: "Keep it under " + TEXT_LIMIT + " characters."});
    order.error = order.errors.length ? order.errors[0].note : null;
    return order;
}

// The text cut into runs for the highlighted preview: {text, kind}, where kind is "title", a token's kind, or
// "error" (shown in amber, with its note).
function highlight(text, order) {
    const source = String(text || "");
    const marks = (order ? order.spans.concat(order.errors.filter(error => error.start !== null)) : [])
        .sort((a, b) => a.start - b.start);
    const runs = [];
    let at = 0;
    for (const mark of marks) {
        if (mark.start > at)
            runs.push({text: source.slice(at, mark.start), kind: "title"});
        runs.push(mark.note ? {text: mark.text, kind: "error", note: mark.note} : {text: mark.text, kind: mark.kind});
        at = mark.end;
    }
    if (at < source.length)
        runs.push({text: source.slice(at), kind: "title"});
    return runs;
}

// "Fri 23 Oct", with the year when it is not this one: the weekday is always shown, so a misread date shows.
function dayLabel(ms, now) {
    const date = new Date(ms);
    return NAMES[date.getDay()].slice(0, 3) + " " + date.getDate() + " " + MONTHS[date.getMonth()]
        + (date.getFullYear() === new Date(now).getFullYear() ? "" : " " + date.getFullYear());
}

// The preview line under the capture field: "Order · call mom · Due Fri 23 Oct 10:30 · #Home · M3", or the reason.
function summary(order, now) {
    if (!order)
        return "";
    if (order.error)
        return order.error;
    const parts = ["Order · " + order.text];
    if (order.dueAt !== null) {
        const due = new Date(order.dueAt);
        parts.push("Due " + dayLabel(order.dueAt, now) + (order.allDay ? "" : " " + two(due.getHours()) + ":" + two(due.getMinutes()))
                   + (order.tomorrow ? " (passed today, so tomorrow)" : ""));
    }
    if (order.rule)
        parts.push((order.ruleFromDone ? "Repeats from clearing · " : "Repeats · ") + order.rule);
    if (order.deadlineAt !== null)
        parts.push("By " + dayLabel(order.deadlineAt, now));
    if (order.durationMin !== null)
        parts.push(order.durationMin + " min");
    if (order.site)
        parts.push("#" + order.site + (order.section ? "/" + order.section : "") + (order.newSite ? " (new site)" : ""));
    for (const tag of order.tags)
        parts.push("@" + tag);
    if (order.priority > 1)
        parts.push("M" + order.priority);
    for (const alert of order.alerts)
        parts.push(alert.at !== undefined ? "Alert " + two(new Date(alert.at).getHours()) + ":" + two(new Date(alert.at).getMinutes())
                                          : "Alert " + alert.beforeMin + " min before");
    return parts.join(" · ");
}

// The fields day.add takes, from a parsed capture (capture() above).
function orderFields(order) {
    const fields = {kind: "todo", text: order.text, site: order.site, section: order.section, tags: order.tags, priority: order.priority,
                    dueAt: order.dueAt, allDay: order.allDay, deadlineAt: order.deadlineAt, durationMin: order.durationMin,
                    rule: order.rule, ruleFromDone: order.ruleFromDone};
    if (order.alerts.length)
        fields.alerts = order.alerts;
    return fields;
}

// A plain list, one order per line in the capture grammar: {orders: [fields], skipped: [{line, reason}]}.
function importLines(lines, now, options) {
    const result = {orders: [], skipped: []};
    for (const line of lines) {
        const order = capture(line, now, options);
        const reason = !order ? "empty" : order.error || (order.errors.length ? order.errors[0].note : "");
        if (reason)
            result.skipped.push({line: line, reason: reason});
        else
            result.orders.push(orderFields(order));
    }
    return result;
}
