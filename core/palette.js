.pragma library

// Colour picking shared by the media visualizer and the wallpaper accent.
// Inputs are ColorQuantizer colours; outputs are Qt colours or "#rrggbb" strings.

function vividness(color) {
    return color.hsvSaturation * color.hsvValue;
}

function hueGap(a, b) {
    return Math.min(Math.abs(a - b), 1 - Math.abs(a - b));
}

function luminance(color) {
    return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b);
}

function hex(color) {
    return "#" + [color.r, color.g, color.b].map(value => Math.round(value * 255).toString(16).padStart(2, "0")).join("");
}

// The most vivid colour and a partner with a clearly different hue, ignoring near-black buckets.
// Returns null without usable colours and {grey: true} when the image is essentially monochrome.
function vividPair(colors) {
    const usable = [];
    for (let i = 0; i < (colors ? colors.length : 0); i++)
        if (colors[i].hsvValue > 0.2)
            usable.push(colors[i]);
    if (!usable.length)
        return null;
    usable.sort((a, b) => vividness(b) - vividness(a));
    if (vividness(usable[0]) < 0.12)
        return {grey: true, first: usable[0], second: usable[0]};
    const second = usable.find(color => vividness(color) >= 0.12 && hueGap(color.hslHue, usable[0].hslHue) > 0.08) || usable[0];
    return {grey: false, first: usable[0], second: second};
}

// Lifts a colour so it reads over dark surfaces and busy artwork.
function tone(color, lightness) {
    return Qt.hsla(Math.max(0, color.hslHue), Math.max(0.5, color.hslSaturation), Math.max(lightness, Math.min(0.8, color.hslLightness)), 1);
}

function linear(value) {
    return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
}

function gamma(value) {
    return value <= 0.0031308 ? 12.92 * value : 1.055 * Math.pow(value, 1 / 2.4) - 0.055;
}

// OKLCH keeps perceived lightness steady while chroma changes, unlike HSL.
function oklch(color) {
    const r = linear(color.r), g = linear(color.g), b = linear(color.b);
    const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
    const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
    const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
    const a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
    const bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
    return {l: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s, c: Math.hypot(a, bb), h: Math.atan2(bb, a)};
}

// Linear sRGB channels for an OKLCH colour; values outside 0..1 are out of gamut.
function fromOklch(lightness, chroma, hue) {
    const a = chroma * Math.cos(hue), b = chroma * Math.sin(hue);
    const l = Math.pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3);
    const m = Math.pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3);
    const s = Math.pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3);
    return [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s];
}

// The most saturated in-gamut colour at this lightness and hue, up to the requested chroma.
function inGamut(lightness, chroma, hue) {
    let low = 0, high = chroma;
    for (let i = 0; i < 20; i++) {
        const middle = (low + high) / 2;
        if (fromOklch(lightness, middle, hue).every(value => value >= -0.0001 && value <= 1.0001))
            low = middle;
        else
            high = middle;
    }
    const channels = fromOklch(lightness, low, hue).map(value => gamma(Math.max(0, Math.min(1, value))));
    return Qt.rgba(channels[0], channels[1], channels[2], 1);
}

// A rich accent with the wallpaper's hue, its chroma boosted so quantized (averaged) colours
// don't come out pastel, and bright enough for the backend's 0.28 luminance floor (0.30
// leaves room for rounding to hex). Empty without usable colours.
function accentFrom(colors) {
    const pair = vividPair(colors);
    if (!pair)
        return "";
    const source = oklch(pair.first);
    const chroma = pair.grey ? 0 : Math.max(0.10, Math.min(0.19, source.c * 1.4));
    let lightness = 0.74;
    let color = inGamut(lightness, chroma, source.h);
    while (luminance(color) < 0.30 && lightness < 0.95) {
        lightness += 0.01;
        color = inGamut(lightness, chroma, source.h);
    }
    return hex(color);
}
