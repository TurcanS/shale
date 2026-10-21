.pragma library

// Routines: reading "3 times a week" out of what was typed, and the words for a schedule. The `every ...` forms are read
// by capture() in core/day.js; this file only adds what that grammar does not have.

// {text, times}: the typed text without "3 times a week" (also "3x a week", "3×/week"), and the count; times is null
// when the text has none or the count is outside 1 to 7 (`error` says so).
function split(text) {
    const source = String(text || "");
    const match = /\b(\d+)\s*(?:times|x|×)\s*(?:a|per|\/)\s*week\b/i.exec(source) || /\b(\d+)\s*(?:times|x|×)\s*\/\s*week\b/i.exec(source);
    if (!match)
        return {text: source.trim(), times: null, error: null};
    const times = Number(match[1]);
    const rest = (source.slice(0, match.index) + " " + source.slice(match.index + match[0].length)).replace(/\s+/g, " ").trim();
    if (times < 1 || times > 7)
        return {text: rest, times: null, error: "A routine can be due one to seven times a week."};
    return {text: rest, times: times, error: null};
}

const DAYS = {MO: "mon", TU: "tue", WE: "wed", TH: "thu", FR: "fri", SA: "sat", SU: "sun"};

// How a stored schedule reads: "every day", "every mon, wed, fri", "3 times a week".
function label(rule) {
    const times = /^TIMES=(\d+)$/.exec(rule || "");
    if (times)
        return times[1] + (times[1] === "1" ? " time" : " times") + " a week";
    const parts = {};
    String(rule || "").split(";").forEach(part => {
        const pair = part.split("=");
        parts[pair[0]] = pair[1];
    });
    const interval = Number(parts.INTERVAL || 1);
    if (parts.FREQ === "DAILY")
        return interval === 1 ? "every day" : "every " + interval + " days";
    if (parts.FREQ === "WEEKLY") {
        const days = parts.BYDAY ? parts.BYDAY.split(",").map(code => DAYS[code]).join(", ") : "week";
        return (interval === 1 ? "every " : "every " + interval + " weeks, ") + days;
    }
    return String(rule || "");
}

// The streak as shown: "7 d" or "2 wk"; nothing for none.
function streakText(routine) {
    return routine.streak > 0 ? routine.streak + (routine.unit === "weeks" ? " wk" : " d") : "—";
}

// The heat map: `weeks` columns of seven days ending with the week of `today` (a Date-parsable ISO day), each cell
// {date, lit, future}. Weeks start on `first` (0 Monday).
function heat(history, today, weeks, first) {
    const lit = {};
    history.forEach(day => lit[day] = true);
    const end = new Date(today + "T12:00:00");
    const lastStart = new Date(end);
    lastStart.setDate(end.getDate() - ((end.getDay() + 6 - first) % 7));
    const columns = [];
    for (let week = weeks - 1; week >= 0; week--) {
        const column = [];
        for (let row = 0; row < 7; row++) {
            const day = new Date(lastStart);
            day.setDate(lastStart.getDate() - week * 7 + row);
            const iso = day.getFullYear() + "-" + String(day.getMonth() + 1).padStart(2, "0") + "-" + String(day.getDate()).padStart(2, "0");
            column.push({date: iso, lit: Boolean(lit[iso]), future: day > end});
        }
        columns.push(column);
    }
    return columns;
}
