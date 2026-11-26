.pragma library
// How amounts and times are written, in one place so every panel writes them the same way.

function known(value) {
    return value !== null && value !== undefined;
}

// 1536 → "1.5 KB": whole bytes, one decimal up to 100 of a unit, none above.
function bytes(value) {
    const units = ["B", "KB", "MB", "GB", "TB"];
    let amount = Math.max(0, value || 0), unit = 0;
    while (amount >= 1024 && unit < units.length - 1) {
        amount /= 1024;
        unit++;
    }
    return (unit === 0 ? Math.round(amount) : amount.toFixed(amount >= 100 ? 0 : 1)) + " " + units[unit];
}

// A position in a track: 75 → "1:15".
function clock(seconds) {
    if (!isFinite(seconds) || seconds < 0)
        return "0:00";
    return Math.floor(seconds / 60) + ":" + String(Math.floor(seconds % 60)).padStart(2, "0");
}

// A stretch of time in its two largest units: "3 d 4 h", "2 h 5 min", "12 min".
function span(seconds) {
    const days = Math.floor(seconds / 86400), hours = Math.floor(seconds % 86400 / 3600), minutes = Math.floor(seconds % 3600 / 60);
    return days > 0 ? days + " d " + hours + " h" : hours > 0 ? hours + " h " + minutes + " min" : minutes + " min";
}

// Battery time left, short enough for a chip: "2 h 15", "40 min"; "" while it isn't known.
function shortSpan(seconds) {
    if (!(seconds > 0))
        return "";
    return seconds >= 3600 ? Math.floor(seconds / 3600) + " h " + Math.floor(seconds % 3600 / 60) : Math.max(1, Math.floor(seconds / 60)) + " min";
}
