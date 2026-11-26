.pragma library
// How an AirDrop request is put into words, the same on its card, on the lock screen and in the bar.

// What one file is, from the type the sender gave (a UTI such as public.jpeg).
function kindOf(file) {
    const uti = String(file.uti || "").toLowerCase();
    const name = String(file.name || "").toLowerCase();
    if (file.dir)
        return "folder";
    if (/image|jpeg|png|heic|heif|gif|tiff|raw/.test(uti) || /\.(jpe?g|png|heic|heif|gif|webp|dng)$/.test(name))
        return "photo";
    if (/movie|video|mpeg-4|quicktime|mpeg/.test(uti) || /\.(mov|mp4|m4v|hevc)$/.test(name))
        return "video";
    if (/audio|mp3|m4a/.test(uti))
        return "audio";
    if (/pdf/.test(uti))
        return "PDF";
    if (/contact|vcard/.test(uti))
        return "contact";
    return "file";
}

const plurals = {photo: "photos", video: "videos", audio: "recordings", PDF: "PDFs", contact: "contacts", folder: "folders", file: "files"};
const singles = {photo: "a photo", video: "a video", audio: "a recording", PDF: "a PDF", contact: "a contact", folder: "a folder", file: "a file"};

// "3 photos", "2 photos and a video", "a link", "4 items".
function summary(files, urls) {
    if (urls && urls.length)
        return urls.length === 1 ? "a link" : urls.length + " links";
    if (!files || !files.length)
        return "something";
    const counts = {};
    for (const file of files) {
        const kind = kindOf(file);
        counts[kind] = (counts[kind] || 0) + 1;
    }
    const kinds = Object.keys(counts);
    if (kinds.length > 2)
        return files.length + " items";
    return kinds.map(kind => counts[kind] === 1 ? singles[kind] : counts[kind] + " " + plurals[kind]).join(" and ");
}

// The glyph for a device or a request.
function deviceGlyph(kind) {
    return ({iphone: "phone", ipad: "tablet", mac: "laptop"})[kind] || "airdrop";
}

// "2 photos" → "2 photos", "a video" → "A video": a summary at the start of a line.
function capital(text) {
    const s = String(text || "");
    return s.charAt(0).toUpperCase() + s.slice(1);
}

// Time still to go at the current rate, rounded the way a person would say it: "a few seconds left", "40 s left",
// "about 3 min left"; "" until the rate is known.
function left(done, total, rate) {
    if (!(rate > 0) || !(total > done))
        return "";
    const seconds = (total - done) / rate;
    if (seconds < 5)
        return "a few seconds left";
    if (seconds < 60)
        return Math.ceil(seconds / 5) * 5 + " s left";
    return "about " + Math.round(seconds / 60) + " min left";
}

// The first names, shortened: "IMG_0412.HEIC, IMG_0413.HEIC and 1 more".
function names(files, most) {
    const shown = (files || []).slice(0, most || 2).map(file => file.name + (file.dir ? "/" : ""));
    const rest = (files || []).length - shown.length;
    return shown.join(", ") + (rest > 0 ? " and " + rest + " more" : "");
}
