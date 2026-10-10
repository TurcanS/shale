.pragma library

// Launcher matching as plain functions, so tests can run them outside QML (tests/test_search.py).

// Case- and accent-insensitive form: "Paramètres" and "parametres" compare equal.
function fold(text) {
    return String(text || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
}

function words(text) {
    // Plain separators rather than Unicode property classes, which Qt's JS engine may not support.
    return text.split(/[\s\-_.,;:()\/+&'"!?]+/).filter(word => word !== "");
}

// How well one folded field matches a folded term; 0 for no match. Fuzzy (letters in order, tightly
// packed: "ffx" finds Firefox) is only for names, where it helps; on long descriptions it is noise.
function fieldScore(field, term, fuzzy, inside) {
    if (!field || !term)
        return 0;
    if (field === term)
        return 1000;
    if (field.startsWith(term))
        return 800;
    if ((" " + field).indexOf(" " + term) >= 0 || words(field).some(word => word.startsWith(term)))
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
function descriptionScore(field, term) {
    if (!field || !term)
        return 0;
    return (" " + field).indexOf(" " + term) >= 0 || words(field).some(word => word.startsWith(term)) ? 500 : 0;
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
    return {
        name: fold(app.name), id: fold(app.id), startupClass: fold(app.startupClass), command: fold(commandName(app.command)),
        keywords: Array.from(app.keywords || [], fold), genericName: fold(app.genericName), comment: fold(app.comment)
    };
}

// Score of a prepared app for an already folded and trimmed term. 0 means "not a result".
function scoreApp(app, term) {
    if (!term)
        return 1;
    const name = fieldScore(app.name, term, true);
    const identity = Math.max(fieldScore(app.id, term, false), fieldScore(app.startupClass, term, false), fieldScore(app.command, term, false));
    // Keywords are whole words ("xls", "qemu"); matching inside them ("readsheet") is noise.
    const keywords = Math.max(0, ...app.keywords.map(keyword => fieldScore(keyword, term, false, false)));
    const described = Math.max(descriptionScore(app.genericName, term), descriptionScore(app.comment, term));
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

// Whether a web-mode query should open as an address rather than be searched.
function isAddress(text) {
    return addressHost(text) !== "";
}

// The host part of an address-like query ("localhost" for "localhost?debug=1"), or "" when it isn't one.
function addressHost(text) {
    text = String(text || "").trim();
    if (!text || /\s/.test(text))
        return "";
    const scheme = /^[a-z][a-z0-9+.-]*:\/\/([^/:?#]*)/i.exec(text);
    if (scheme)
        return scheme[1].toLowerCase() || text;
    const match = /^([^/:?#]+)(:\d{1,5})?([/?#].*)?$/.exec(text);
    if (!match)
        return "";
    const host = match[1].toLowerCase();
    if (host === "localhost" || /^\d{1,3}(\.\d{1,3}){3}$/.test(host))
        return host;
    if (!/^[a-z0-9-]+(\.[a-z0-9-]+)+$/.test(host))
        return "";
    if (host.startsWith("www.") || match[2] || match[3])
        return host;
    return DOMAINS.indexOf(host.split(".").pop()) >= 0 ? host : "";
}

// The URL to open for an address: as typed when it has a scheme, plain http for local hosts
// (dev servers rarely speak TLS), https otherwise.
function addressUrl(text) {
    text = String(text || "").trim();
    if (/^[a-z][a-z0-9+.-]*:\/\//i.test(text))
        return text;
    const host = addressHost(text);
    const local = host === "localhost" || /^\d{1,3}(\.\d{1,3}){3}$/.test(host);
    return (local ? "http://" : "https://") + text;
}
