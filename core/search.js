.pragma library

// Launcher matching as plain functions, so they can run outside QML.

// Case- and accent-insensitive form: "Paramètres" and "parametres" compare equal.
function fold(text) {
    return String(text || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
}

function words(text) {
    // Plain separators rather than Unicode property classes, which Qt's JS engine may not support.
    return text.split(/[\s\-_.,;:()\/+&'"!?]+/).filter(word => word !== "");
}

// True when a word of the field starts with the term. `split` is words(field), passed in by prepared apps
// so typing doesn't split every field again on each keystroke.
function wordStarts(field, term, split) {
    return (" " + field).indexOf(" " + term) >= 0 || (split || words(field)).some(word => word.startsWith(term));
}

// How well one folded field matches a folded term; 0 for no match. Fuzzy (letters in order, tightly
// packed: "ffx" finds Firefox) is only for names, where it helps; on long descriptions it is noise.
function fieldScore(field, term, fuzzy, inside, split) {
    if (!field || !term)
        return 0;
    if (field === term)
        return 1000;
    if (field.startsWith(term))
        return 800;
    if (wordStarts(field, term, split))
        return 600;
    if (inside !== false && field.indexOf(term) >= 0)
        return 450;
    if (!fuzzy || term.length < 2)
        return 0;
    let position = -1, gaps = 0;
    for (const c of term) {
        const next = field.indexOf(c, position + 1);
        if (next < 0)
            return 0;
        gaps += next - position - 1;
        position = next;
    }
    const score = 300 - gaps * 25;
    return score >= 100 ? score : 0;
}

// Descriptions count only where a word starts with the term ("spreadsheet" for "spread").
function descriptionScore(field, term, split) {
    if (!field || !term)
        return 0;
    return wordStarts(field, term, split) ? 500 : 0;
}

// The program a desktop entry runs, e.g. "code-oss" for ["/usr/bin/code-oss", "%F"], or the app id
// for Flatpak's exported entries ("/usr/bin/flatpak run --branch=stable com.spotify.Client").
function commandName(command) {
    const parts = (command || []).filter(part => part && !/^[A-Za-z_][A-Za-z0-9_]*=/.test(part) && part !== "env");
    const program = parts.length ? parts[0].split("/").pop() : "";
    if (program === "flatpak" && parts[1] === "run")
        return parts.slice(2).find(part => !part.startsWith("-")) || "";
    return program;
}

// The folded text of an app, computed once per desktop entry rather than on every keystroke.
// app: {name, genericName, comment, keywords, id, startupClass, command}.
function prepare(app) {
    const prepared = {
        name: fold(app.name), id: fold(app.id), startupClass: fold(app.startupClass), command: fold(commandName(app.command)),
        keywords: Array.from(app.keywords || [], fold), genericName: fold(app.genericName), comment: fold(app.comment)
    };
    prepared.split = {};
    for (const key of ["name", "id", "startupClass", "command", "genericName", "comment"])
        prepared.split[key] = words(prepared[key]);
    prepared.keywordSplit = prepared.keywords.map(words);
    return prepared;
}

// Score of a prepared app for an already folded and trimmed term. 0 means "not a result".
function scoreApp(app, term) {
    if (!term)
        return 1;
    const split = app.split || {};
    const name = fieldScore(app.name, term, true, true, split.name);
    const identity = Math.max(fieldScore(app.id, term, false, true, split.id), fieldScore(app.startupClass, term, false, true, split.startupClass),
                              fieldScore(app.command, term, false, true, split.command));
    // Keywords are whole words ("xls", "qemu"); matching inside them ("readsheet") is noise.
    const keywords = Math.max(0, ...app.keywords.map((keyword, i) => fieldScore(keyword, term, false, false, app.keywordSplit && app.keywordSplit[i])));
    const described = Math.max(descriptionScore(app.genericName, term, split.genericName), descriptionScore(app.comment, term, split.comment));
    return Math.max(name * 2, identity * 1.5, keywords * 1.2, described * 0.6);
}

// Frequently launched apps rise, with diminishing returns so habit never beats a clearly better match.
function usageBoost(launches) {
    return Math.log2(1 + Math.max(0, launches || 0)) * 30;
}

// Endings that make "word.word" a website. Endings that are mostly file types (md, pl, ai, in, js, py,
// sh, rs, ts) are left out, so "README.md" or "node.js" are searched; www. or https:// still opens them.
const DOMAINS = ["com", "org", "net", "io", "dev", "app", "co", "gov", "edu", "info", "me", "xyz", "tv", "gg", "fm", "ly",
                 "de", "uk", "fr", "nl", "ru", "ro", "eu", "ca", "au", "jp", "cn", "br", "es", "it", "se", "ch",
                 "at", "be", "cz", "us", "ua", "online", "site", "tech", "blog", "cloud", "page", "wiki", "land", "social", "art",
                 "news", "shop", "store", "games", "space", "studio", "design", "one"];

// A dotted IPv4 address with every part from 0 to 255.
function isIp(host) {
    return /^\d{1,3}(\.\d{1,3}){3}$/.test(host) && host.split(".").every(part => Number(part) <= 255);
}

// Whether a web-mode query should open as an address rather than be searched.
function isAddress(text) {
    return addressHost(text) !== "";
}

// The host part of an address-like query ("localhost" for "localhost?debug=1"), or "" when it isn't one.
function addressHost(text) {
    text = String(text || "").trim();
    if (!text || /\s/.test(text))
        return "";
    // Only web links open directly; file:// and other schemes are searched instead of handed to the system.
    if (/^[a-z][a-z0-9+.-]*:\/\//i.test(text)) {
        const web = /^https?:\/\/([^/:?#]+)/i.exec(text);
        return web ? web[1].toLowerCase() : "";
    }
    const match = /^([^/:?#]+)(:\d{1,5})?([/?#].*)?$/.exec(text);
    if (!match)
        return "";
    const host = match[1].toLowerCase();
    if (host === "localhost" || isIp(host))
        return host;
    if (/^[\d.]+$/.test(host) || !/^[a-z0-9-]+(\.[a-z0-9-]+)+$/.test(host))
        return "";
    if (host.startsWith("www.") || match[2] || match[3])
        return host;
    return DOMAINS.indexOf(host.split(".").pop()) >= 0 ? host : "";
}

// The URL to open for an address: as typed when it has a scheme, plain http for local hosts
// (dev servers rarely speak TLS), https otherwise.
function addressUrl(text) {
    text = String(text || "").trim();
    if (/^https?:\/\//i.test(text))
        return text;
    const host = addressHost(text);
    const local = host === "localhost" || isIp(host);
    return (local ? "http://" : "https://") + text;
}

// Seconds in a duration: "90s", "10m", "1h30m", "1.5h" or a bare number of minutes. 0 when it isn't one.
function parseDuration(text) {
    text = String(text || "").trim().toLowerCase();
    if (/^\d+(\.\d+)?$/.test(text))
        return Math.round(Number(text) * 60);
    const match = /^(?:(\d+(?:\.\d+)?)\s*h(?:ours?|rs?)?)?\s*(?:(\d+(?:\.\d+)?)\s*m(?:in(?:utes?|s)?)?)?\s*(?:(\d+)\s*s(?:ec(?:onds?|s)?)?)?$/.exec(text);
    if (!match || !(match[1] || match[2] || match[3]))
        return 0;
    return Math.round(Number(match[1] || 0) * 3600 + Number(match[2] || 0) * 60 + Number(match[3] || 0));
}

// "timer 10m tea" → {seconds: 600, label: "tea"}; null for anything else. Timers last up to a day.
function timerQuery(text) {
    const match = /^\s*timer\s+(.+?)\s*$/i.exec(String(text || ""));
    if (!match)
        return null;
    // The duration may be written with spaces ("1h 30m"); take the longest leading part that parses.
    const parts = match[1].split(/\s+/);
    for (let count = parts.length; count > 0; count--) {
        const seconds = parseDuration(parts.slice(0, count).join(""));
        if (seconds > 0)
            return seconds <= 86400 ? {seconds: seconds, label: parts.slice(count).join(" ").slice(0, 60)} : null;
    }
    return null;
}

// "focus 40" or "focus 1h" → 40 or 60 minutes; null for anything else. Sessions last 1 to 240 minutes.
function focusQuery(text) {
    const match = /^\s*focus\s+(.+?)\s*$/i.exec(String(text || ""));
    if (!match)
        return null;
    const seconds = parseDuration(match[1]);
    const minutes = Math.round(seconds / 60);
    return seconds >= 60 && minutes <= 240 ? minutes : null;
}

// Things the launcher can do besides opening apps. Session actions that end the session open the session
// menu, whose hold-to-confirm buttons stay the only way to log out, restart or shut down.
var ACTIONS = [
    {key: "lock", name: "Lock screen", keywords: ["lock"], glyph: "lock"},
    {key: "suspend", name: "Suspend", keywords: ["sleep", "suspend"], glyph: "moon"},
    {key: "power:logout", name: "Log out", keywords: ["logout", "sign out", "exit"], glyph: "logout"},
    {key: "power:reboot", name: "Restart", keywords: ["reboot", "restart"], glyph: "refresh"},
    {key: "power:shutdown", name: "Shut down", keywords: ["shutdown", "power off", "poweroff", "turn off"], glyph: "power"},
    {key: "page:wifi", name: "Wi-Fi", keywords: ["wifi", "wireless", "network", "vpn"], glyph: "wifi"},
    {key: "page:bluetooth", name: "Bluetooth", keywords: ["bluetooth", "headphones"], glyph: "bluetooth"},
    {key: "page:audio", name: "Sound", keywords: ["sound", "audio", "volume", "microphone"], glyph: "volume"},
    {key: "page:power", name: "Power mode", keywords: ["battery", "power mode", "performance", "saver"], glyph: "battery"},
    {key: "panel:settings", name: "Shale settings", keywords: ["settings", "preferences", "config"], glyph: "settings"},
    {key: "settings:Bar", name: "Bar settings", keywords: ["bar", "taskbar", "panel layout", "clock format"], glyph: "window"},
    {key: "settings:Control center", name: "Control center layout", keywords: ["control center", "quick settings", "tiles"], glyph: "settings"},
    {key: "settings:Shortcuts", name: "Keyboard shortcuts", keywords: ["shortcuts", "keybinds", "keybindings", "hotkeys"], glyph: "grid"},
    {key: "settings:Backup", name: "Back up settings", keywords: ["backup", "export settings", "import settings"], glyph: "folder"},
    {key: "panel:system", name: "System monitor", keywords: ["task manager", "processes", "cpu", "memory"], glyph: "gauge"},
    {key: "panel:clipboard", name: "Clipboard history", keywords: ["clipboard", "paste"], glyph: "clipboard"},
    {key: "panel:wallpaper", name: "Wallpapers", keywords: ["wallpaper", "background"], glyph: "palette"},
    {key: "panel:activity", name: "Activity", keywords: ["screen time", "usage"], glyph: "activity"},
    {key: "screenshot", name: "Screenshot", keywords: ["screenshot", "capture", "print screen"], glyph: "region"},
    {key: "color", name: "Pick a color", keywords: ["color picker", "colour", "eyedropper"], glyph: "palette"},
    {key: "focus", name: "Focus", keywords: ["focus", "do not disturb", "pomodoro"], glyph: "focus"},
    {key: "dnd", name: "Do not disturb", keywords: ["dnd", "notifications", "quiet"], glyph: "bell-off"}
];

// An action's score on the apps' scale; only a clear start of a word counts, so short typing stays for apps.
function scoreAction(action, term) {
    if (!term || term.length < 2)
        return 0;
    const best = Math.max(fieldScore(fold(action.name), term, false, false), ...action.keywords.map(keyword => fieldScore(fold(keyword), term, false, false)));
    return best >= 600 ? best * 2 - 100 : 0;
}

// An open window's score from its title and app id. Titles are long, so only word starts count there.
function scoreWindow(title, appId, term) {
    if (!term)
        return 0;
    const app = fieldScore(fold(appId).split(".").pop(), term, true, true);
    const named = descriptionScore(fold(title), term);
    return Math.max(app * 2, named * 1.6);
}
