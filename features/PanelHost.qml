import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../core"

// Every panel on one screen. Each comes in its own way and from its own place (see Motion.qml for the character):
// Control pulls out of its key as a drawer, Notifications unrolls from the bell, Find opens from a scope line, Clock
// and sky flips down like a desk calendar, Capture is framed by brackets from the screen corners, and so on
// (entranceFor). One clock, t, runs 0 → 1 through an opening or a closing; frameAt() turns it into the shape of the
// case and of the few things drawn around it. The page lays out at its full size the whole time and is only
// revealed, never squashed. Calm and Reduce motion keep the plain rise and fade, as do chromeless pages.
PanelWindow {
    id: host
    required property string outputName
    readonly property bool showing: ShellState.panel !== "" && ShellState.screenName === outputName && !ShellState.locked
    property string retainedPanel: "launcher"
    // Settings → Appearance → Panel size. Every panel lays out at its own size and is drawn this much smaller or
    // larger, like a zoom; text and icons are vectors, so they stay sharp.
    readonly property real zoom: Theme.panelScale
    IpcHandler {
        target: "surface-" + host.outputName
        function status(): string {
            return JSON.stringify({
                panel: content.panel,
                visible: host.visible,
                content: content.objectName
            });
        }
    }
    function synchronizePanel() {
        if (showing)
            retainedPanel = ShellState.panel;
    }
    Connections {
        target: ShellState
        function onPanelChanged() {
            host.synchronizePanel();
        }
        function onScreenNameChanged() {
            host.synchronizePanel();
        }
    }
    onShowingChanged: {
        synchronizePanel();
        if (showing)
            begin();
        else
            finish();
    }

    // ---- where the case sits once it is open ----
    readonly property real homeWidth: Math.min((width - 24) / zoom, content.preferredWidth)
    readonly property real homeHeight: Math.min((height - 90) / zoom, content.preferredHeight)
    // Panels opened from the bar's right end line up with it, 8 px in from the screen edge.
    // On whole pixels: a case that starts between two has blurred hairlines.
    readonly property real homeX: Math.round(["control", "notifications"].indexOf(retainedPanel) >= 0 ? width - caseWidth * zoom - 8 : (width - caseWidth * zoom) / 2)
    readonly property real homeY: Math.round(["control", "notifications", "calendar"].indexOf(retainedPanel) >= 0 ? barBottom + 8 : Math.max(barBottom + 11, (height - caseHeight * zoom) * 0.38))
    readonly property int barBottom: ShellState.barBottomOn(outputName)
    // Switching panels in an open case morphs it to the new size and place.
    readonly property bool settled: showing && !drive.running
    property real caseWidth: homeWidth
    property real caseHeight: homeHeight
    property real caseX: homeX
    property real caseY: homeY
    Behavior on caseWidth {
        enabled: !Theme.reduced && host.settled
        NumberAnimation { duration: Theme.enter; easing.type: Easing.OutCubic }
    }
    Behavior on caseHeight {
        enabled: !Theme.reduced && host.settled
        NumberAnimation { duration: Theme.enter; easing.type: Easing.OutCubic }
    }
    Behavior on caseX {
        enabled: !Theme.reduced && host.settled
        NumberAnimation { duration: Theme.enter; easing.type: Easing.OutCubic }
    }
    Behavior on caseY {
        enabled: !Theme.reduced && host.settled
        NumberAnimation { duration: Theme.enter; easing.type: Easing.OutCubic }
    }

    // ---- the entrance ----
    property real t: 1
    property bool closing: false
    property string entrance: "rise"
    // The bar key the panel came out of, in this window's coordinates, with the key itself for the catch.
    property var origin: null
    function entranceFor(panel) {
        if (Motion.calm || content.chromeless)
            return "rise";
        const own = content.page("entrance", "");
        if (own !== "")
            return own;
        if (panel === "control")
            return ShellState.detail === "media" ? "eject" : "drawer";
        return ({notifications: "unroll", launcher: "scope", calendar: "flip", power: "session", clipboard: "receipt",
                 capture: "brackets", overview: "zoom", settings: "settings", system: "power", activity: "plot",
                 airdrop: "iris"})[panel] || "rise";
    }
    // How long each way takes, at Lively; Motion.ms scales it for the level.
    readonly property var spans: ({
        drawer: [440, 230], unroll: [560, 340], scope: [540, 340], session: [540, 340], flip: [420, 170],
        brackets: [1100, 230], receipt: [520, 170], eject: [560, 260], power: [790, 290], plot: [860, 220],
        iris: [460, 220], settings: [490, 240], zoom: [240, 300]
    })
    // When, into each entrance at Lively, the case has opened far enough for its items to start arriving.
    readonly property var innerDelay: ({
        drawer: 150, unroll: 120, scope: 300, session: 260, flip: 160, brackets: 380, receipt: 60, eject: 300,
        power: 220, plot: 540, iris: 200, settings: 220, zoom: 90
    })
    function span(name, leaving) {
        if (name === "rise")
            return leaving ? Theme.panelLeave : Theme.panelEnter;
        return Motion.ms(spans[name][leaving ? 1 : 0]);
    }
    function originOf(item) {
        if (!item)
            return null;
        // The bar is its own window, 8 px in from the screen's corner when it floats.
        const inset = ShellState.setting("barStyle", "floating") === "edge" ? 0 : 8;
        const p = item.mapToItem(null, 0, 0);
        return {x: p.x + inset, y: p.y + inset, w: item.width, h: item.height, item: item};
    }
    function begin() {
        drive.stop();
        closing = false;
        origin = originOf(Motion.take());
        entrance = entranceFor(ShellState.panel);
        t = 0;
        // Control's own page (the Player is "media") is set just after the panel opens; look again before the first frame.
        Qt.callLater(() => {
            if (!host.showing || host.closing)
                return;
            host.entrance = host.entranceFor(host.retainedPanel);
            drive.duration = host.span(host.entrance, false);
            drive.from = 0;
            drive.to = 1;
            drive.restart();
            if (host.entrance === "iris")
                rings.restart();
            // The page's own items come in once the case has room for them (Cascade), the Player being Control's.
            const own = host.retainedPanel === "control" && ShellState.detail === "media" ? "player" : host.retainedPanel;
            Motion.entering(own, host.innerDelay[host.entrance] || 0);
        });
    }
    function finish() {
        // Closed while still opening: run the opening back to where it began rather than jump to the closing.
        if (drive.running && !closing) {
            drive.stop();
            drive.duration = Math.max(1, span(entrance, true) * t);
            drive.from = t;
            drive.to = 0;
            drive.start();
            return;
        }
        drive.stop();
        closing = true;
        t = 0;
        drive.duration = span(entrance, true);
        drive.from = 0;
        drive.to = 1;
        drive.restart();
    }
    NumberAnimation {
        id: drive
        target: host
        property: "t"
        duration: 1
        onFinished: {
            // The panel went back into its key: the key catches it.
            if (host.closing && ["drawer", "unroll", "eject", "iris"].indexOf(host.entrance) >= 0 && host.origin)
                Motion.landed(host.origin.item);
        }
    }
    NumberAnimation {
        id: rings
        target: host
        property: "ringT"
        from: 0
        to: 1
        duration: Motion.ms(1060)
    }
    property real ringT: 1

    readonly property var f: frameAt(entrance, closing, t, caseX, caseY, caseWidth * zoom, caseHeight * zoom, origin, width, height)
    function frameAt(name, leaving, t, X, Y, W, H, o, screenW, screenH) {
        const M = Motion, R = Theme.radiusCase * zoom;
        const clamp = v => M.clamp(v, 0, 1);
        const f = {bx: X, by: Y, bw: W, bh: H, cx: X, cy: Y, cw: W, ch: H, r: R, o: 1, co: 1, dx: 0, dy: 0, tx: 0, ty: 0,
                   sc: 1, rot: 0, shade: 0, flash: 0, vig: 0, line: null, roll: null, brk: null, dim: -1, plot: null, iris: null};
        // With no key to come from (a shortcut), a key-sized place at the top of the case.
        const k = o || {x: X + W / 2 - 30, y: Math.max(0, barBottom - 33), w: 60, h: 28};
        const cy = Y + H / 2;
        if (name === "rise") {
            const p = M.rack(t);
            f.o = leaving ? 1 - p : p;
            f.ty = (leaving ? p : 1 - p) * Theme.panelRise;
        } else if (name === "drawer") {
            // Pulled out from under its key: widens from the key's width, then pulls down and seats.
            const l0 = M.clamp(k.x - X, 0, W - 24), r0 = M.clamp(X + W - (k.x + k.w), 0, W - 24), gap = Y - (k.y + k.h);
            let a, b;
            if (!leaving) {
                a = M.out(clamp(t / 0.34));
                b = M.seat(M.ov(0.55), clamp((t - 0.16) / 0.84));
                const u = clamp((t - 0.34) / 0.68);
                f.dy = -16 * M.travel * (1 - M.seat(M.ov(0.8), u));
                f.co = clamp(u * 3);
            } else {
                b = 1 - M.away(clamp(t / 0.68));
                a = 1 - M.away(clamp((t - 0.5) / 0.5));
                f.co = 1 - clamp(t / 0.3);
                if (t > 0.9)
                    f.o = 1 - (t - 0.9) * 10;
            }
            f.cx = f.bx = X + l0 * (1 - a);
            f.cw = f.bw = W - (l0 + r0) * (1 - a);
            f.ch = f.bh = b > 1 ? H * b : M.lerp(12, H, b);
            f.ty = -gap * (1 - a);
            f.r = M.lerp(10, R, a);
        } else if (name === "unroll") {
            // A paper roll leaves the bell, widens to the case and rolls down it.
            const h0 = 18 * Math.min(1.3, M.travel);
            if (!leaving) {
                const a = M.out(clamp(t / 0.22)), u = clamp((t - 0.2) / 0.8), b = M.seat(M.ov(0.45), u);
                const reveal = Math.max(0, H * b);
                f.ch = f.bh = Math.min(reveal, H);
                f.roll = {x: M.lerp(k.x, X, a), w: M.lerp(k.w, W, a), y: M.lerp(k.y + k.h, Y, a) + Math.min(reveal, H + 12),
                          h: M.lerp(h0, 7, Math.min(1, b)), o: u > 0.86 ? 1 - (u - 0.86) / 0.14 : 1};
            } else if (t < 0.68) {
                const p = M.away(t / 0.68), reveal = H * (1 - p);
                f.ch = f.bh = reveal;
                f.co = 1 - clamp(t / 0.3);
                f.roll = {x: X, w: W, y: Y + reveal, h: M.lerp(7, h0, p), o: 1};
            } else {
                const p = M.away((t - 0.68) / 0.32);
                f.o = 0;
                f.roll = {x: M.lerp(X, k.x, p), w: M.lerp(W, k.w, p), y: M.lerp(Y, k.y + k.h, p), h: h0, o: 1 - p * p};
            }
        } else if (name === "scope" || name === "session") {
            // A lit hairline strikes like phosphor, opens wide across the middle, then the picture opens tall from it.
            if (!leaving) {
                if (t < 0.167) {
                    f.o = 0;
                    f.line = {x: X + W / 2 - 3, y: cy - 1, w: 6, h: 2, o: [1, 0.15, 0.9, 0.3, 1][Math.min(4, Math.floor(t / 0.167 * 5))]};
                } else if (t < 0.48) {
                    const w = W * M.out((t - 0.167) / 0.313);
                    f.o = 0;
                    f.line = {x: X + W / 2 - w / 2, y: cy - 1, w: w, h: 2, o: 1};
                } else {
                    const u = (t - 0.48) / 0.52, b = M.seat(M.ov(0.45), u), half = H / 2 * (1 - Math.min(1, b));
                    const grow = b > 1 ? H * (b - 1) / 2 : 0;
                    f.cy = f.by = Y + half - grow;
                    f.ch = f.bh = H - 2 * half + 2 * grow;
                    f.r = M.lerp(1, R, Math.min(1, b * 1.4));
                    f.line = {x: X, y: cy - 1, w: W, h: 2, o: 1 - clamp((t - 0.555) / 0.296)};
                    f.dy = 8 * M.travel * (1 - M.seat(M.ov(0.5), u));
                    f.co = clamp(u * 3);
                    f.flash = M.glow ? 0.16 * Math.pow(1 - u, 2) : 0;
                }
                if (name === "session")
                    f.vig = M.out(clamp(t * 540 / 420));
            } else {
                if (t < 0.38) {
                    const p = M.away(t / 0.38), half = H / 2 * p;
                    f.cy = f.by = Y + half;
                    f.ch = f.bh = H - 2 * half;
                    f.r = M.lerp(R, 1, p);
                    f.co = 1 - clamp(t / 0.18);
                } else if (t < 0.735) {
                    const w = M.lerp(W, 4, M.away((t - 0.38) / 0.355));
                    f.o = 0;
                    f.line = {x: X + W / 2 - w / 2, y: cy - 1, w: w, h: 2, o: 1};
                } else {
                    const p = (t - 0.735) / 0.265;
                    f.o = 0;
                    f.line = {x: X + W / 2 - 2, y: cy - 1 - p, w: 4, h: 2 + 2 * p, o: 1 - p};
                }
                if (name === "session")
                    f.vig = 1 - M.away(clamp(t * 340 / 200));
            }
        } else if (name === "flip") {
            // Hinged on its top edge like a desk calendar page: falls down, shaded while it faces away, and seats.
            if (!leaving) {
                const s = M.seat(M.ov(1.1), t);
                f.o = clamp(t * 4);
                f.rot = 86 * (1 - s);
                f.shade = 0.55 * (1 - clamp(s));
            } else {
                const p = M.away(t);
                f.o = 1 - p * p;
                f.rot = 78 * p;
                f.shade = 0.55 * p;
            }
        } else if (name === "brackets") {
            // Four corner marks fly in from the screen's corners, frame the case and tick; it lights inside them.
            const S = 22, ms = t * 1100;
            const to = [[X - 7, Y - 7], [X + W - 15, Y - 7], [X - 7, Y + H - 15], [X + W - 15, Y + H - 15]];
            const from = [[0, 0], [screenW - S, 0], [0, screenH - S], [screenW - S, screenH - S]];
            if (!leaving) {
                const tick = ms > 378 ? Math.sin(Math.PI * clamp((ms - 378) / 140)) : 0;
                f.brk = to.map((q, i) => {
                    const tt = clamp((ms - i * 16) / 330), s = M.seat(M.ov(1.1), tt);
                    return {x: M.lerp(from[i][0], q[0], s), y: M.lerp(from[i][1], q[1], s), s: 1 - 0.18 * tick,
                            o: clamp(tt * 3) * (t > 0.77 ? 1 - (t - 0.77) / 0.23 : 1)};
                });
                const p = M.out(clamp((ms - 330) / 200));
                f.o = p;
                f.sc = M.lerp(0.97, 1, p);
                f.dy = 6 * M.travel * (1 - M.seat(M.ov(0.4), clamp((ms - 390) / 220)));
            } else {
                const p = M.away(t);
                f.o = 1 - clamp(t * 230 / 110);
                f.brk = to.map((q, i) => ({x: M.lerp(q[0], from[i][0], p), y: M.lerp(q[1], from[i][1], p), s: 1, o: 1 - p * p}));
            }
        } else if (name === "receipt") {
            // The header comes first and the case feeds down out of it like a receipt.
            const head = 52 * zoom;
            if (!leaving) {
                f.ch = f.bh = M.lerp(head, H, M.out(t));
            } else {
                const p = M.away(t);
                f.ch = f.bh = H - (H - head) * p;
                f.co = 1 - clamp(t / 0.35);
                if (p > 0.7)
                    f.o = 1 - (p - 0.7) / 0.3;
            }
        } else if (name === "eject") {
            // A motorised tray behind the bar. The latch lets go with a knock, a beat, then it glides down to its stop.
            const edge = barBottom + 2, travel = H + (Y - edge) + 2;
            let y;
            if (!leaving) {
                let fr;
                if (t < 0.12)
                    fr = M.lerp(1, 0.86, M.out(t / 0.12));
                else if (t < 0.2)
                    fr = 0.86 - 0.012 * Math.sin(Math.PI * (t - 0.12) / 0.08);
                else {
                    const u = (t - 0.2) / 0.8;
                    fr = u < 0.72 ? 0.86 * (1 - M.inOut(u / 0.72)) : 0;
                }
                const kk = t > 0.2 ? (t - 0.2) / 0.8 : 0;
                const knock = kk > 0.72 ? 6 * M.travel * Math.sin(Math.PI * (kk - 0.72) / 0.28) * (1 - (kk - 0.72) / 0.28) : 0;
                y = -travel * fr + knock;
            } else {
                y = -travel * M.away(t);
                f.co = 1 - clamp(t / 0.3);
            }
            f.by = Y + y;
            f.cy = Math.max(Y + y, edge);
            f.ch = Math.max(0, Y + y + H - f.cy);
            f.dy = y;
        } else if (name === "power") {
            // The unit sits dark in the rack, then a lit bar sweeps across and switches the face on as it passes.
            const bar = x => ({x: X + W * clamp(x) - 1, y: Y + 14 * zoom, w: 2, h: H - 28 * zoom, o: 1});
            if (!leaving) {
                if (t < 0.19) {
                    const tt = t / 0.19;
                    f.o = clamp(tt * 3);
                    f.ty = 12 * M.travel * (1 - M.seat(M.ov(0.5), tt));
                    f.dim = -0.07;
                } else if (t < 0.696) {
                    const x = M.lerp(-0.07, 1, M.inOut((t - 0.19) / 0.506));
                    f.dim = x;
                    f.line = bar(x);
                } else {
                    const u = (t - 0.696) / 0.304;
                    f.line = bar(1);
                    f.line.o = 1 - clamp(u / 0.58);
                    f.flash = 0.07 * M.travel * Math.sin(Math.PI * u) * (1 - u * 0.5);
                }
            } else if (t < 0.724) {
                const x = M.lerp(1, -0.07, M.away(t / 0.724));
                f.dim = x;
                f.line = bar(x);
            } else {
                f.dim = -0.07;
                f.o = 1 - (t - 0.724) / 0.276;
            }
        } else if (name === "plot") {
            // A pen draws the case's outline once round, then the face fills in inside the line.
            if (!leaving) {
                if (t < 0.605) {
                    f.o = 0;
                    f.plot = {d: M.inOut(t / 0.605), off: 0, o: 1, pen: 1};
                } else {
                    const p = M.out(clamp((t - 0.605) / 0.233));
                    f.o = p;
                    f.sc = M.lerp(0.985, 1, p);
                    f.plot = {d: 1, off: 0, o: 1 - clamp((t - 0.698) / 0.302), pen: 1 - clamp((t - 0.605) / 0.14)};
                    const u = clamp((t - 0.65) / 0.28);
                    f.dy = 8 * M.travel * (1 - M.seat(M.ov(0.4), u));
                    f.co = clamp(u * 3);
                }
            } else {
                f.o = 1 - clamp(t / 0.45);
                f.plot = {d: 1, off: M.away(t), o: 1 - 0.4 * t, pen: 0};
            }
        } else if (name === "iris") {
            // Opens as a circle from the key, like a radar's sweep reaching out.
            const ix = k.x + k.w / 2, iy = k.y + k.h / 2;
            const far = Math.max(Math.hypot(ix - X, iy - Y), Math.hypot(ix - X - W, iy - Y), Math.hypot(ix - X, iy - Y - H), Math.hypot(ix - X - W, iy - Y - H));
            // Only while it moves: the mask goes once the case is open, so the shadow shows whole.
            if (leaving || t < 1)
                f.iris = {x: ix, y: iy, r: Math.max(0.5, far * (leaving ? 1 - M.away(t) : M.out(t)))};
            if (!leaving) {
                const u = clamp((t - 0.43) / 0.52);
                f.dy = 6 * M.travel * (1 - M.seat(M.ov(0.4), u));
                f.co = clamp(u * 3);
            }
        } else if (name === "settings") {
            // The sidebar slides out of the case's left edge, then the page pulls out from behind it.
            const sb = Math.min(W, 246 * zoom);
            if (!leaving) {
                const ms = t * 490;
                f.cw = f.bw = sb + (W - sb) * M.out(clamp((ms - 110) / 380));
                f.dx = -26 * M.travel * (1 - M.seat(M.ov(0.6), clamp(ms / 300)));
                f.co = clamp(ms / 100);
            } else if (t < 0.625) {
                f.cw = f.bw = W - (W - sb) * M.away(t / 0.625);
                f.co = 1 - clamp(t / 0.25);
            } else {
                const p = M.away((t - 0.625) / 0.375);
                f.cw = f.bw = sb;
                f.co = 0;
                f.o = 1 - p;
                f.tx = -10 * p;
            }
        } else if (name === "zoom") {
            // Pages: the view pulls back from the desktop to the pages.
            if (!leaving) {
                const p = M.out(t);
                f.o = p;
                f.sc = M.lerp(1.04, 1, p);
            } else {
                const p = clamp((t * 300 - 80) / 220);
                f.o = 1 - p;
                f.sc = M.lerp(1, 1.03, p);
            }
        }
        return f;
    }

    visible: showing || drive.running
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shale-panel"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: showing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    MouseArea {
        anchors.fill: parent
        onClicked: ShellState.close()
    }
    // Session: the screen behind dims in from its edges.
    Shape {
        id: vignette
        anchors.fill: parent
        visible: host.f.vig > 0
        opacity: Math.min(1, host.f.vig * 1.5)
        readonly property real ray: Math.hypot(width / 2, height * 0.58) * 1.62
        readonly property real inner: Motion.lerp(120, 28, host.f.vig) / 162
        ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: vignette.width / 2
                centerY: vignette.height * 0.42
                focalX: centerX
                focalY: centerY
                centerRadius: vignette.ray
                focalRadius: 0
                GradientStop { position: Math.min(0.99, vignette.inner); color: "transparent" }
                GradientStop { position: Math.min(1, vignette.inner + 42 / 162); color: Qt.rgba(0, 0, 0, 0.72) }
            }
            startX: 0
            startY: 0
            PathLine { x: vignette.width; y: 0 }
            PathLine { x: vignette.width; y: vignette.height }
            PathLine { x: 0; y: vignette.height }
            PathLine { x: 0; y: 0 }
        }
    }
    // The case and everything that moves with it. Masked to a circle while AirDrop opens.
    Item {
        id: body
        anchors.fill: parent
        opacity: host.f.o
        visible: opacity > 0
        transform: [
            Translate {
                x: host.f.tx
                y: host.f.ty
            },
            Scale {
                origin.x: host.caseX + host.caseWidth * host.zoom / 2
                origin.y: host.caseY + host.caseHeight * host.zoom / 2
                xScale: host.f.sc
                yScale: host.f.sc
            },
            Rotation {
                origin.x: host.caseX + host.caseWidth * host.zoom / 2
                origin.y: host.caseY
                axis { x: 1; y: 0; z: 0 }
                angle: host.f.rot
            }
        ]
        layer.enabled: !!host.f.iris
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: irisMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }
        // The case's long soft shadow; skipped when effects are trimmed. It follows the part of the case on show.
        RectangularShadow {
            readonly property real shownTop: Math.max(host.f.by, host.f.cy)
            x: Math.max(host.f.bx, host.f.cx)
            y: shownTop
            width: Math.max(0, Math.min(host.f.bx + host.f.bw, host.f.cx + host.f.cw) - x)
            height: Math.max(0, Math.min(host.f.by + host.f.bh, host.f.cy + host.f.ch) - shownTop)
            visible: !content.chromeless && !Theme.lowPower && width > 0 && height > 0
            radius: Math.min(host.f.r, height / 2)
            blur: Theme.caseShadow.blur
            offset.x: Theme.caseShadow.x
            offset.y: Theme.caseShadow.y
            color: Theme.caseShadow.color
        }
        // With effects trimmed the shadow is gone; a dark ring just outside the hairline keeps the case apart from
        // bright wallpapers at no cost.
        Rectangle {
            x: host.f.bx - 1
            y: host.f.by - 1
            width: host.f.bw + 2
            height: host.f.bh + 2
            visible: !content.chromeless && Theme.lowPower
            radius: host.f.r + 1
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, 0.55)
        }
        // The window the case shows through; the case itself and the page sit inside at their own places.
        Item {
            id: window_
            x: host.f.cx
            y: host.f.cy
            width: Math.max(0, host.f.cw)
            height: Math.max(0, host.f.ch)
            clip: true
            // A hairline edge keeps the case apart from dark wallpapers.
            Rectangle {
                x: host.f.bx - window_.x
                y: host.f.by - window_.y
                width: host.f.bw
                height: host.f.bh
                visible: !content.chromeless
                radius: host.f.r
                color: Theme.caseColor
                border.width: 1
                border.color: Theme.hairline
            }
            PanelContent {
                id: content
                bare: true
                panel: host.retainedPanel
                x: host.caseX + host.f.dx - window_.x
                y: host.caseY + host.f.dy - window_.y
                width: host.caseWidth
                height: host.caseHeight
                scale: host.zoom
                transformOrigin: Item.TopLeft
                opacity: host.f.co
                entering: drive.running && !host.closing
                enabled: host.showing
                visible: host.visible
                active: host.visible
            }
            // System powering up: the part the light bar hasn't reached yet stays dark.
            Rectangle {
                readonly property real edge: host.caseX + host.caseWidth * host.zoom * host.f.dim
                visible: host.f.dim > -1
                x: edge - window_.x
                y: host.f.by - window_.y
                width: host.caseX + host.caseWidth * host.zoom - edge
                height: host.f.bh
                radius: host.f.r
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Theme.tint(Theme.backdrop, 0) }
                    GradientStop { position: Math.min(1, 0.07 * host.caseWidth * host.zoom / Math.max(1, host.caseX + host.caseWidth * host.zoom - (host.caseX + host.caseWidth * host.zoom * host.f.dim))); color: Theme.tint(Theme.backdrop, 0.8) }
                }
            }
            // A lamp's flash as the face comes on (System, and Playful's phosphor after a scope line).
            Rectangle {
                x: host.f.bx - window_.x
                y: host.f.by - window_.y
                width: host.f.bw
                height: host.f.bh
                radius: host.f.r
                visible: host.f.flash > 0
                color: Theme.knob
                opacity: host.f.flash
            }
            // Clock and sky's page is darker while it faces away, so it reads as a sheet turning in the light.
            Rectangle {
                x: host.f.bx - window_.x
                y: host.f.by - window_.y
                width: host.f.bw
                height: host.f.bh
                radius: host.f.r
                visible: host.f.shade > 0
                color: "black"
                opacity: host.f.shade
            }
        }
    }
    // AirDrop's circle, as a mask over the case.
    Item {
        id: irisMask
        anchors.fill: parent
        visible: false
        layer.enabled: !!host.f.iris
        Rectangle {
            readonly property real r: host.f.iris ? host.f.iris.r : 0
            x: (host.f.iris ? host.f.iris.x : 0) - r
            y: (host.f.iris ? host.f.iris.y : 0) - r
            width: r * 2
            height: r * 2
            radius: r
            color: "white"
        }
    }
    // AirDrop's radar rings leave its key as the case opens.
    Repeater {
        model: 3
        delegate: Rectangle {
            required property int index
            readonly property real p: Motion.out(Motion.clamp((host.ringT * 1060 - index * 150) / 760, 0, 1))
            readonly property real size: 300 * p * (Motion.playful ? 1.25 : 1)
            readonly property var key: host.origin || {x: host.caseX + host.caseWidth * host.zoom / 2, y: host.caseY, w: 0, h: 0}
            visible: host.ringT < 1 && p > 0 && p < 1 && host.entrance === "iris"
            x: key.x + key.w / 2 - size / 2
            y: key.y + key.h / 2 - size / 2
            width: size
            height: size
            radius: size / 2
            color: "transparent"
            border.width: 1.5
            border.color: Theme.accent
            opacity: 0.8 * (1 - p)
        }
    }
    // The scope line, and System's light bar.
    Rectangle {
        visible: !!host.f.line && host.f.line.o > 0
        x: host.f.line ? host.f.line.x : 0
        y: (host.f.line ? host.f.line.y : 0) + host.f.ty
        width: host.f.line ? host.f.line.w : 0
        height: host.f.line ? host.f.line.h : 0
        radius: Math.min(width, height) / 2
        opacity: host.f.line ? host.f.line.o : 0
        color: Theme.mix(Theme.knob, Theme.accent, 0.25)
        layer.enabled: visible && !Theme.lowPower
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Theme.accent
            shadowBlur: Motion.glow ? 1 : 0.6
            shadowOpacity: Motion.glow ? 1 : 0.7
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 0
            blurMax: 16
        }
    }
    // Notifications' paper roll.
    Rectangle {
        visible: !!host.f.roll && host.f.roll.o > 0
        x: host.f.roll ? host.f.roll.x : 0
        y: host.f.roll ? host.f.roll.y - host.f.roll.h / 2 : 0
        width: host.f.roll ? host.f.roll.w : 0
        height: host.f.roll ? host.f.roll.h : 0
        radius: height / 2
        opacity: host.f.roll ? host.f.roll.o : 0
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.keyHover }
            GradientStop { position: 0.38; color: Theme.key }
            GradientStop { position: 0.7; color: Theme.module }
            GradientStop { position: 1; color: Theme.backdrop }
        }
        border.width: Motion.glow ? 1 : 0
        border.color: Theme.accentLine
    }
    // Capture's corner brackets: a rounded corner of an accent frame each.
    Repeater {
        model: 4
        delegate: Item {
            required property int index
            readonly property var b: host.f.brk ? host.f.brk[index] : null
            visible: !!b && b.o > 0
            x: b ? b.x : 0
            y: b ? b.y : 0
            width: 22
            height: 22
            opacity: b ? b.o : 0
            scale: b ? b.s : 1
            clip: true
            Rectangle {
                x: index % 2 ? -22 : 0
                y: index > 1 ? -22 : 0
                width: 44
                height: 44
                radius: 8
                color: "transparent"
                border.width: 2
                border.color: Theme.accent
            }
        }
    }
    // Activity's pen, drawing the outline of the case.
    Shape {
        id: plotter
        anchors.fill: parent
        visible: !!host.f.plot && host.f.plot.o > 0
        opacity: host.f.plot ? host.f.plot.o : 0
        readonly property real ox: host.caseX
        readonly property real oy: host.caseY
        readonly property real ow: host.caseWidth * host.zoom
        readonly property real oh: host.caseHeight * host.zoom
        readonly property real orad: Theme.radiusCase * host.zoom
        readonly property real stroke: 1.6
        readonly property real length: 2 * (ow + oh) - 8 * orad + 2 * Math.PI * orad
        // A point that far along the outline, clockwise from the top left corner's end.
        function pointAt(d) {
            const runs = [ow - 2 * orad, Math.PI * orad / 2, oh - 2 * orad, Math.PI * orad / 2, ow - 2 * orad, Math.PI * orad / 2, oh - 2 * orad, Math.PI * orad / 2];
            let s = d * length;
            for (let i = 0; i < 8; i++) {
                if (s <= runs[i] || i === 7) {
                    const q = Math.min(1, s / runs[i]), a = q * Math.PI / 2;
                    switch (i) {
                    case 0: return {x: ox + orad + s, y: oy};
                    case 1: return {x: ox + ow - orad + orad * Math.sin(a), y: oy + orad - orad * Math.cos(a)};
                    case 2: return {x: ox + ow, y: oy + orad + s};
                    case 3: return {x: ox + ow - orad + orad * Math.cos(a), y: oy + oh - orad + orad * Math.sin(a)};
                    case 4: return {x: ox + ow - orad - s, y: oy + oh};
                    case 5: return {x: ox + orad - orad * Math.sin(a), y: oy + oh - orad + orad * Math.cos(a)};
                    case 6: return {x: ox, y: oy + oh - orad - s};
                    default: return {x: ox + orad - orad * Math.cos(a), y: oy + orad - orad * Math.sin(a)};
                    }
                }
                s -= runs[i];
            }
            return {x: ox, y: oy};
        }
        ShapePath {
            strokeColor: Theme.mix(Theme.knob, Theme.accent, 0.25)
            strokeWidth: plotter.stroke
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            strokeStyle: ShapePath.DashLine
            dashPattern: [plotter.length / plotter.stroke, plotter.length / plotter.stroke]
            dashOffset: host.f.plot ? plotter.length / plotter.stroke * (host.f.plot.off - host.f.plot.d + 1) : 0
            startX: plotter.ox + plotter.orad
            startY: plotter.oy
            PathLine { x: plotter.ox + plotter.ow - plotter.orad; y: plotter.oy }
            PathArc { x: plotter.ox + plotter.ow; y: plotter.oy + plotter.orad; radiusX: plotter.orad; radiusY: plotter.orad }
            PathLine { x: plotter.ox + plotter.ow; y: plotter.oy + plotter.oh - plotter.orad }
            PathArc { x: plotter.ox + plotter.ow - plotter.orad; y: plotter.oy + plotter.oh; radiusX: plotter.orad; radiusY: plotter.orad }
            PathLine { x: plotter.ox + plotter.orad; y: plotter.oy + plotter.oh }
            PathArc { x: plotter.ox; y: plotter.oy + plotter.oh - plotter.orad; radiusX: plotter.orad; radiusY: plotter.orad }
            PathLine { x: plotter.ox; y: plotter.oy + plotter.orad }
            PathArc { x: plotter.ox + plotter.orad; y: plotter.oy; radiusX: plotter.orad; radiusY: plotter.orad }
        }
    }
    Rectangle {
        readonly property var at: host.f.plot ? plotter.pointAt(host.f.plot.d) : null
        visible: !!at && host.f.plot.pen > 0
        x: at ? at.x - 3 : 0
        y: at ? at.y - 3 : 0
        width: 6
        height: 6
        radius: 3
        color: Theme.knob
        opacity: host.f.plot ? host.f.plot.pen : 0
        border.width: 1
        border.color: Theme.accent
    }
}
