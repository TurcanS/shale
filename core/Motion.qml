pragma Singleton
import QtQuick

// The shell's motion character: studio gear. Things have weight like hardware: modules seat in their rails with a
// small knock, drawers pull out of their keys, switches click past a detent, lamps warm up, meters swing like VU
// needles. Settings → Appearance → Motion picks how much: Calm is the plain Rack motion (short rises and fades),
// Lively the character at a moderate size, Playful the same turned up. Reduce motion wins over all of them, and
// power saver or Reduce effects fall back to Calm.
QtObject {
    id: root
    readonly property string chosen: ShellState.setting("motion", "lively")
    readonly property string style: Theme.reduced ? "reduced" : Theme.lowPower ? "calm"
                                  : ["calm", "lively", "playful"].indexOf(chosen) >= 0 ? chosen : "lively"
    readonly property bool reduced: style === "reduced"
    // Calm and Reduce motion both mean "no character": callers then keep today's Theme timings.
    readonly property bool calm: style === "calm" || reduced
    readonly property bool playful: style === "playful"
    // Travel: how far things move; dur: a time factor; stagger: ms between items in a cascade; over: how far a seat
    // or detent runs past home (see ov()); glow: Playful's phosphor on scope lines and warm-ups.
    readonly property var levels: ({
        reduced: {travel: 0, dur: 1, stagger: 0, over: 0, glow: 0},
        calm: {travel: 0, dur: 1, stagger: 0, over: 0, glow: 0},
        lively: {travel: 1, dur: 1, stagger: 28, over: 1, glow: 0},
        playful: {travel: 1.7, dur: 1.22, stagger: 46, over: 1.9, glow: 1}
    })
    readonly property var level: levels[style]
    readonly property real travel: level.travel
    readonly property int stagger: level.stagger
    readonly property real glow: level.glow
    // Only preview stubs change this, to look at motion slowly; the shell itself always runs at 1.
    property real slowmo: 1
    function ms(base) {
        return reduced ? 0 : Math.round(base * level.dur * slowmo);
    }
    // How far past home a seat or a detent runs, as a fraction of the travel; k scales it per use.
    function ov(k) {
        return 0.07 * level.over * (k === undefined ? 1 : k);
    }

    // ---- curves, for motion worked out frame by frame (PanelHost) ----
    function lerp(a, b, p) {
        return a + (b - a) * p;
    }
    function clamp(v, a, b) {
        return Math.max(a, Math.min(b, v));
    }
    function smooth(s) {
        return s * s * (3 - 2 * s);
    }
    // cubic-bezier(x1, y1, x2, y2) at x, by Newton's method.
    function bezier(x1, y1, x2, y2, x) {
        if (x <= 0)
            return 0;
        if (x >= 1)
            return 1;
        const cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx;
        const cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by;
        let t = x;
        for (let i = 0; i < 6; i++) {
            const d = (3 * ax * t + 2 * bx) * t + cx;
            if (Math.abs(d) < 1e-6)
                break;
            t -= (((ax * t + bx) * t + cx) * t - x) / d;
        }
        t = clamp(t, 0, 1);
        return ((ay * t + by) * t + cy) * t;
    }
    // Theme.easeOut, today's Rack curve.
    function rack(t) {
        return bezier(0.2, 0.8, 0.2, 1, t);
    }
    // Strong ease-out for travel; quick and accelerating away for exits; both ends soft for gliding.
    function out(t) {
        return bezier(0.16, 1, 0.3, 1, t);
    }
    function away(t) {
        return bezier(0.55, 0, 0.8, 0.3, t);
    }
    function inOut(t) {
        return bezier(0.65, 0, 0.35, 1, t);
    }
    // Seat: a module pushed home in its rail. Travels past home by o, comes back a little under, settles.
    function seat(o, t) {
        if (t < 0.56)
            return (1 + o) * (1 - Math.pow(1 - t / 0.56, 3));
        if (t < 0.8)
            return lerp(1 + o, 1 - o * 0.32, smooth((t - 0.56) / 0.24));
        return lerp(1 - o * 0.32, 1, smooth(Math.min(1, (t - 0.8) / 0.2)));
    }
    // Detent: resists for the first third, then snaps past the middle with a click and comes back to rest.
    function detent(o, t) {
        if (t < 0.32)
            return 0.09 * Math.pow(t / 0.32, 2);
        if (t < 0.74)
            return 0.09 + (1 + o - 0.09) * (1 - Math.pow(1 - (t - 0.32) / 0.42, 3));
        return lerp(1 + o, 1, smooth(Math.min(1, (t - 0.74) / 0.26)));
    }
    // Warm-up: an indicator lamp. Rises to a flash above rest (1.6), then settles at rest (1).
    function warm(t) {
        return t < 0.28 ? 1.6 * (1 - Math.pow(1 - t / 0.28, 2)) : lerp(1.6, 1, smooth(Math.min(1, (t - 0.28) / 0.72)));
    }

    // ---- the same curves as Easing.BezierSpline lists, for NumberAnimation ----
    // Each piece of seat(), detent() and warm() is a cubic with its x running evenly, so it is exact as a spline.
    function seatCurve(o) {
        return [0.56 / 3, 1 + o, 1.12 / 3, 1 + o, 0.56, 1 + o,
                0.64, 1 + o, 0.72, 1 - o * 0.32, 0.8, 1 - o * 0.32,
                0.8 + 0.2 / 3, 1 - o * 0.32, 0.8 + 0.4 / 3, 1, 1, 1];
    }
    function detentCurve(o) {
        return [0.32 / 3, 0, 0.64 / 3, 0.03, 0.32, 0.09,
                0.32 + 0.14, 1 + o, 0.32 + 0.28, 1 + o, 0.74, 1 + o,
                0.74 + 0.26 / 3, 1 + o, 0.74 + 0.52 / 3, 1, 1, 1];
    }
    readonly property var warmCurve: [0.28 / 3, 1.6 * 2 / 3, 0.56 / 3, 1.6, 0.28, 1.6,
                                      0.28 + 0.24, 1.6, 0.28 + 0.48, 1, 1, 1]

    // ---- where a panel comes from ----
    // A bar key marks itself when pressed; the panel host takes the mark once, while it is fresh, and opens the
    // panel out of that key. Closing hands the panel back: landed() makes the key catch it.
    property var mark_: null
    function mark(item) {
        mark_ = {item: item, at: Date.now()};
    }
    function take() {
        const m = mark_;
        mark_ = null;
        return m && Date.now() - m.at < 700 ? m.item : null;
    }
    signal caught(Item item)
    // A panel's entrance has started; its items (Cascade) come in after delay ms, one after another.
    signal entering(string panel, int delay)
    function landed(item) {
        if (item && !calm)
            caught(item);
    }
}
