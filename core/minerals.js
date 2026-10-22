.pragma library

// One colour per app, the same everywhere: a stable hash of the app id picks one of eight muted minerals.
// Nothing is stored, so the colour is the same on every run and every machine.

const NAMES = ["ember", "ochre", "lichen", "malachite", "azurite", "lapis", "amethyst", "rose"];
const COLORS = ["#eb9e84", "#b8964e", "#a8c781", "#55af95", "#72c8e9", "#8199da", "#d0a8e9", "#cc81a0"];
const GRANITE = "#7b8187";

// "Firefox", "firefox" and "firefox.desktop" are one app.
function normalize(app) {
    return String(app === undefined || app === null ? "" : app).trim().toLowerCase().replace(/\.desktop$/, "");
}

// FNV-1a, 32 bit, over UTF-8 so non-ASCII ids hash alike on every engine.
function hash(text) {
    let value = 0x811c9dc5;
    const bytes = unescape(encodeURIComponent(text));
    for (let i = 0; i < bytes.length; i++) {
        value ^= bytes.charCodeAt(i);
        value = Math.imul(value, 0x01000193) >>> 0;
    }
    return value >>> 0;
}

// -1 for an empty id, which gets granite.
function index(app) {
    const id = normalize(app);
    return id === "" ? -1 : hash(id) % NAMES.length;
}

function name(app) {
    const i = index(app);
    return i < 0 ? "granite" : NAMES[i];
}

function color(app) {
    const i = index(app);
    return i < 0 ? GRANITE : COLORS[i];
}
