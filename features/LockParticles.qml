import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import "../core"
import "../components" as C

// The particle lock screen: the time is drawn in points of light that never sit still. Locking draws them in from
// every side of the screen to settle into the digits; the seconds re-form every second; each minute the digits that
// change come apart in a different way (a swirl, rain, a burst, a wave); typing sends a pulse through them; unlocking
// bursts them outward while the blur clears to the desktop's own wallpaper.
// Motion runs on Qt's render thread (animators), so busy script never makes it stutter.
Item {
    id: root
    required property var context
    property string screenName: ""

    // Power saver keeps the particles but drops the glow, the drifting dust and the shimmer, and shortens the
    // sequences; reduced motion shows every state in place.
    readonly property bool reduced: Theme.reduced
    readonly property bool calm: Theme.lowPower
    readonly property real tempo: calm ? 0.6 : 1
    // Qt's software renderer can't draw the glow.
    readonly property bool glow: !calm && GraphicsInfo.api !== GraphicsInfo.Software
    property bool started: false
    property bool settled: reduced
    property bool frozen: false
    // The particles drift about their places all the time, except in power saver and with reduced motion.
    readonly property bool living: started && !frozen && !reduced && !calm

    // The clock is a grid of cells about 16 rows tall, fitted to the font's digits; each lit cell holds one particle.
    // The seconds use the same grid at a smaller step, sitting on the minutes' baseline.
    property int rows: 16
    property int cols: 10
    readonly property real digitHeight: Math.round(Math.min(height * 0.25, width * 0.13))
    readonly property real step: digitHeight / rows
    readonly property real dot: step * 0.66
    readonly property real digitWidth: cols * step
    readonly property real colonWidth: 4 * step
    readonly property real secStep: step * 0.42
    readonly property real secDot: secStep * 0.72
    readonly property real secWidth: cols * secStep
    readonly property real secGap: 1.6 * step
    readonly property real clockWidth: 4 * digitWidth + 2 * step + colonWidth + secGap + 2 * secWidth + secStep
    readonly property real clockCx: width / 2
    readonly property real clockCy: height * 0.4
    readonly property real clockY: clockCy - digitHeight / 2
    // Two pairs of cells for the colon, a third of the way in from the top and the bottom.
    readonly property var colonCells: {
        const upper = Math.round(rows * 0.3) - 1, lower = rows - 1 - upper - 1;
        return [[1, upper], [2, upper], [1, upper + 1], [2, upper + 1], [1, lower], [2, lower], [1, lower + 1], [2, lower + 1]];
    }

    readonly property bool clock24h: ShellState.setting("clock24h", true)
    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }
    // Always seven characters, hours and minutes then seconds; a 12-hour time before ten leaves the first one blank.
    readonly property string time: (" " + Qt.formatDateTime(clock.date, clock24h ? "HH:mm" : "h:mm")).slice(-5) + Qt.formatDateTime(clock.date, "ss")
    onTimeChanged: if (started && !frozen)
        arrange(reduced ? "instant" : "morph")
    // A screen's size can still change just after the lock surface appears: the intro waits until it holds, and
    // later changes glide the particles to their new places rather than snapping them.
    onWidthChanged: resized()
    onHeightChanged: resized()
    function resized() {
        if (!started)
            settle.restart();
        else
            arrange(reduced ? "instant" : "glide");
    }
    Timer {
        id: settle
        interval: 150
        onTriggered: root.begin()
    }

    // Each digit's lit cells, read from the interface font once at start: the digits are drawn as Text, captured,
    // and each cell counts as lit when the glyph covers enough of it. (Canvas text would punch holes where a variable
    // font's strokes overlap, as in a 4.) All of it sits under the backdrop, so it is never seen.
    property var glyphs: null
    readonly property int perDigit: glyphs ? Math.max(...Object.keys(glyphs).map(key => glyphs[key].length)) : 0
    readonly property int poolSize: glyphs ? 6 * perDigit + colonCells.length : 0
    readonly property int sampleCell: 8
    property var specimenShot: null
    Row {
        id: specimen
        visible: !root.glyphs
        Repeater {
            model: 10
            Text {
                required property int index
                width: 24 * root.sampleCell
                height: 32 * root.sampleCell
                text: String(index)
                color: "white"
                font.family: Theme.font
                font.weight: Font.Bold
                // Digits stand about 0.72 em, so this makes them about 16 cells tall.
                font.pixelSize: Math.round(16 * root.sampleCell / 0.72)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
    Timer {
        id: capture
        interval: 30
        running: true
        onTriggered: {
            if (!specimen.grabToImage(result => root.specimenShot = result, Qt.size(specimen.width, specimen.height)))
                restart();
        }
    }
    Image {
        id: specimenImage
        visible: false
        source: root.specimenShot ? root.specimenShot.url : ""
        onStatusChanged: if (status === Image.Ready)
            sampler.requestPaint()
    }
    Canvas {
        id: sampler
        width: specimen.width
        height: specimen.height
        visible: !root.glyphs
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Immediate
        onPaint: {
            if (specimenImage.status !== Image.Ready || root.glyphs)
                return;
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            ctx.drawImage(specimenImage, 0, 0);
            const data = ctx.getImageData(0, 0, width, height).data;
            const cell = root.sampleCell, across = 24, down = 32;
            const sampled = {};
            let left = across, right = 0, top = down, bottom = 0;
            for (let digit = 0; digit < 10; digit++) {
                const cells = [];
                for (let r = 0; r < down; r++) {
                    for (let c = 0; c < across; c++) {
                        // Sixteen points a cell; lit when at least six fall inside the glyph.
                        let inside = 0;
                        for (let i = 0; i < 4; i++)
                            for (let j = 0; j < 4; j++)
                                if (data[((r * cell + 1 + 2 * j) * width + digit * across * cell + c * cell + 1 + 2 * i) * 4 + 3] > 128)
                                    inside++;
                        if (inside >= 6) {
                            cells.push([c, r]);
                            left = Math.min(left, c);
                            right = Math.max(right, c);
                            top = Math.min(top, r);
                            bottom = Math.max(bottom, r);
                        }
                    }
                }
                sampled[String(digit)] = cells;
            }
            if (right < left)
                return;
            // The grid is the box around every digit, so each one keeps its place within it.
            for (const digit in sampled)
                sampled[digit] = sampled[digit].map(([c, r]) => [c - left, r - top]);
            root.cols = right - left + 1;
            root.rows = bottom - top + 1;
            root.glyphs = sampled;
            root.specimenShot = null;
            settle.restart();
        }
    }

    // Stage values the sequences animate. Reduced motion starts at the end.
    property real veil: reduced ? 1 : 0
    property real chrome: reduced ? 1 : 0
    property real textIn: reduced ? 1 : 0
    property real squeeze: 1
    property real scatter: 0
    property real danger: 0
    // A band of light passing through the particles: across the clock, or out from its centre.
    property real wave: -1
    property real waveLevel: 0
    property bool waveRadial: false

    // Awake while someone is at the keyboard or pointer; after ten quiet seconds only the clock stays.
    property bool awake: true
    property real idleness: awake ? 0 : 1
    Behavior on idleness {
        NumberAnimation { duration: root.reduced ? 0 : 420; easing.type: Easing.InOutCubic }
    }
    function wake() {
        awake = true;
        idleTimer.restart();
    }
    Timer {
        id: idleTimer
        interval: 10000
        running: true
        onTriggered: {
            if (root.context.password === "" && root.context.status === "" && root.context.prompt === "" && !root.context.busy && !root.context.unlocking)
                root.awake = false;
            else
                restart();
        }
    }
    // The clock leans a little toward the pointer, the dust behind it further.
    readonly property bool leaning: !reduced && !calm && !frozen
    property real leanX: 0
    property real leanY: 0
    Behavior on leanX { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
    Behavior on leanY { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

    property int typed: context.password.length
    onTypedChanged: {
        wake();
        if (typed > 0 && !reduced && !context.busy && !frozen)
            pulse.restart();
    }
    Connections {
        target: root.context
        function onStatusChanged() {
            root.wake();
        }
        function onPromptChanged() {
            root.wake();
        }
        function onBusyChanged() {
            root.wake();
            if (root.reduced)
                return;
            if (root.context.busy) {
                shimmer.stop();
                pulse.stop();
                root.waveRadial = false;
                root.waveLevel = 1;
                checking.start();
            } else {
                checking.stop();
                waveOff.start();
            }
        }
        function onFailed() {
            if (!root.reduced)
                failure.restart();
        }
        function onUnlockingChanged() {
            if (root.context.unlocking)
                root.unlock();
        }
    }

    function begin() {
        if (started || settle.running || !glyphs || !(backdrop.ready || backdrop.waited) || width <= 0 || height <= 0)
            return;
        started = true;
        arrange(reduced ? "instant" : "intro");
        if (!reduced)
            intro.start();
    }
    Timer {
        // Waits briefly for the sharp wallpaper so the first frame matches the desktop.
        interval: 250
        running: true
        onTriggered: {
            backdrop.waited = true;
            settle.restart();
        }
    }

    // Sends every particle to its place for the current time. "intro" draws them in from far off, "morph" moves only
    // the digits that changed, "glide" moves everything after a resize, "instant" puts them straight there.
    // Hours and minutes change with one of several transitions, never the same twice running; seconds flip quickly.
    readonly property var transitions: ["swirl", "rain", "burst", "wave", "arc"]
    property string lastTransition: ""
    property string shown: ""
    property real shownOffset: 0
    function arrange(mode) {
        if (mode === "glide" && frozen)
            return;
        const text = time;
        // A blank first digit centres the rest.
        const offset = text.charAt(0) === " " ? -(digitWidth + step) / 2 : 0;
        const left = clockCx - clockWidth / 2 + offset;
        const minutesEnd = left + 4 * digitWidth + 2 * step + colonWidth;
        const slotX = [left, left + digitWidth + step, left + 2 * digitWidth + step, left + 2 * digitWidth + step + colonWidth,
                       left + 3 * digitWidth + 2 * step + colonWidth, minutesEnd + secGap, minutesEnd + secGap + secWidth + secStep];
        const slotSize = [perDigit, perDigit, colonCells.length, perDigit, perDigit, perDigit, perDigit];
        const slotStart = [];
        slotSize.reduce((sum, size) => (slotStart.push(sum), sum + size), 0);
        const moved = mode !== "morph" || offset !== shownOffset;
        // One transition for every hour and minute digit that changes this time.
        let style = "arc";
        if (mode === "morph") {
            const choices = transitions.filter(name => name !== lastTransition);
            style = choices[Math.floor(Math.random() * choices.length)];
        }
        let styled = false;
        for (let slot = 0; slot < 7; slot++) {
            const ch = text.charAt(slot);
            if (!moved && ch === shown.charAt(slot))
                continue;
            const seconds = slot >= 5;
            const cellStep = seconds ? secStep : step, size = seconds ? secDot : dot;
            const top = seconds ? clockY + digitHeight - rows * secStep : clockY;
            const cells = ch === ":" ? colonCells : glyphs[ch] || [];
            const width = ch === ":" ? colonWidth : seconds ? secWidth : digitWidth;
            const centreX = slotX[slot] + width / 2, centreY = top + rows * cellStep / 2;
            const inset = (cellStep - size) / 2;
            styled = styled || (mode === "morph" && !seconds);
            for (let j = 0; j < slotSize[slot]; j++) {
                const p = particles.itemAt(slotStart[slot] + j);
                if (!p)
                    continue;
                // Spare particles share a lit cell, hidden, ready for a digit with more cells.
                const cell = cells.length ? cells[j % cells.length] : [(width / cellStep - 1) / 2, rows / 2];
                const tx = slotX[slot] + cell[0] * cellStep + inset, ty = top + cell[1] * cellStep + inset;
                const lit = j < cells.length, alpha = lit ? 1 : 0;
                const wasLit = p.lit;
                p.size = size;
                p.lit = lit;
                p.nx = (tx - left) / clockWidth;
                p.ny = (ty - clockY) / digitHeight;
                if (mode === "instant" || (seconds && mode === "morph" && calm)) {
                    p.place(tx, ty, alpha);
                } else if (mode === "intro") {
                    // From a wide circle around the clock, rushing in out of the screen.
                    const angle = p.seed * 2 * Math.PI, reach = (0.55 + 0.6 * p.seed2) * Math.max(root.width, root.height);
                    p.place(clockCx + Math.cos(angle) * reach, clockCy + Math.sin(angle) * reach, 0, 2.6);
                    p.travel(tx, ty, alpha, 1, (950 + 450 * p.seed2) * tempo, (40 + 380 * p.seed) * tempo, Easing.OutCubic, Easing.OutQuart);
                } else if (mode === "glide" || (!wasLit && !lit)) {
                    p.travel(tx, ty, alpha, 1, 450 * tempo, 0, Easing.InOutCubic, Easing.InOutCubic);
                } else if (seconds) {
                    // A quick hop over to the new digit, done well before the next second.
                    p.travel(tx, ty, alpha, 1, 380 + 160 * p.seed2, 110 * p.seed, Easing.InOutQuad, Easing.OutBack);
                } else {
                    transition(p, style, tx, ty, alpha, centreX, centreY, (tx - slotX[slot]) / width);
                }
            }
        }
        if (styled)
            lastTransition = style;
        shown = text;
        shownOffset = offset;
    }
    // One particle's way from its old digit to its new place. `column` is 0–1 across the digit.
    function transition(p, style, tx, ty, alpha, centreX, centreY, column) {
        const t = tempo;
        if (style === "swirl") {
            // Pulled into a whirl at the digit's centre, then flung out to its new place.
            const dx = p.x - centreX, dy = p.y - centreY;
            const angle = Math.atan2(dy, dx) + 2.2, reach = (0.15 + 0.2 * p.seed) * digitHeight;
            p.route({x: centreX + Math.cos(angle) * reach, y: centreY + Math.sin(angle) * reach, opacity: 1, scale: 0.7, duration: 460 * t,
                     easeX: Easing.InCubic, easeY: Easing.InOutSine},
                    {x: tx, y: ty, opacity: alpha, scale: 1, duration: (560 + 240 * p.seed2) * t, easeX: Easing.OutCubic, easeY: Easing.OutBack},
                    120 * p.seed * t);
        } else if (style === "rain") {
            // The old digit falls away and the new one drops in from above, column by column.
            p.route({x: p.x + (p.seed - 0.5) * 2 * step, y: p.y + (0.8 + 0.6 * p.seed) * digitHeight, opacity: 0, scale: 0.8,
                     duration: 420 * t, easeX: Easing.Linear, easeY: Easing.InQuad},
                    {fromX: tx, fromY: ty - (0.7 + 0.6 * p.seed2) * digitHeight, x: tx, y: ty, opacity: alpha, scale: 1,
                     duration: (520 + 200 * p.seed2) * t, easeX: Easing.Linear, easeY: Easing.OutBounce},
                    (column * 260 + 60 * p.seed) * t);
        } else if (style === "burst") {
            // Blown apart from the centre, then drawn back together.
            const dx = p.x - centreX, dy = p.y - centreY, length = Math.max(1, Math.hypot(dx, dy));
            const reach = (0.2 + 0.3 * p.seed) * digitHeight;
            p.route({x: p.x + dx / length * reach, y: p.y + dy / length * reach, opacity: 1, scale: 1.6, duration: 380 * t,
                     easeX: Easing.OutCubic, easeY: Easing.OutCubic},
                    {x: tx, y: ty, opacity: alpha, scale: 1, duration: (620 + 200 * p.seed2) * t, easeX: Easing.InOutCubic, easeY: Easing.InOutCubic},
                    60 * p.seed * t);
        } else if (style === "wave") {
            // A hop up that runs across the digit like a wave, landing with a bounce.
            p.route({x: p.x, y: p.y - (2.5 + 2 * p.seed) * step, opacity: 1, scale: 1.2, duration: 260 * t, easeX: Easing.Linear, easeY: Easing.OutQuad},
                    {x: tx, y: ty, opacity: alpha, scale: 1, duration: 560 * t, easeX: Easing.InOutQuad, easeY: Easing.OutBounce},
                    (column * 320 + 40 * p.seed) * t);
        } else {
            // Arcing paths: the two axes ease differently.
            p.travel(tx, ty, alpha, 1, (680 + 420 * p.seed2) * t, 220 * p.seed * t, Easing.InOutCubic, Easing.OutBack);
        }
    }
    function unlock() {
        if (intro.running)
            intro.complete();
        shimmer.stop();
        pulse.stop();
        checking.stop();
        failure.stop();
        frozen = true;
        if (reduced)
            return;
        // Every particle flies out from the clock's centre and toward you as it fades.
        for (let i = 0; i < poolSize; i++) {
            const p = particles.itemAt(i);
            if (!p)
                continue;
            const fromX = p.x + p.size / 2 - clockCx, fromY = p.y + p.size / 2 - clockCy;
            const length = Math.max(1, Math.hypot(fromX, fromY));
            const angle = Math.atan2(fromY / length, fromX / length) + (p.seed - 0.5) * 0.7;
            const reach = (260 + 640 * p.seed2) * digitHeight / 240;
            p.travel(p.x + Math.cos(angle) * reach, p.y + Math.sin(angle) * reach, 0, 1.4 + 2.2 * p.seed, (600 + 180 * p.seed2) * tempo,
                     (120 + 70 * p.seed) * tempo, Easing.OutCubic, Easing.OutCubic);
        }
        outro.start();
    }

    // Lock: the backdrop blurs in while the particles gather (started by arrange), then the date, field and edges.
    ParallelAnimation {
        id: intro
        onFinished: root.settled = true
        NumberAnimation { target: root; property: "veil"; from: 0; to: 1; duration: 600 * root.tempo; easing.type: Easing.OutCubic }
        SequentialAnimation {
            PauseAnimation { duration: 1100 * root.tempo }
            ParallelAnimation {
                NumberAnimation { target: root; property: "textIn"; to: 1; duration: 500 * root.tempo; easing.type: Easing.OutCubic }
                NumberAnimation { target: root; property: "chrome"; to: 1; duration: 500 * root.tempo; easing.type: Easing.OutCubic }
            }
        }
        SequentialAnimation {
            PauseAnimation { duration: 1250 * root.tempo }
            ScriptAction { script: root.sweep(0.9) }
        }
    }
    // Unlock: the clock draws in a breath, then bursts (each particle's flight is set in unlock()) while the blur clears
    // to the plain wallpaper. LockScreen waits the same time before unlocking.
    SequentialAnimation {
        id: outro
        ParallelAnimation {
            NumberAnimation { target: root; property: "squeeze"; to: 0.94; duration: 120 * root.tempo; easing.type: Easing.InQuad }
            NumberAnimation { target: root; property: "textIn"; to: 0; duration: 220 * root.tempo; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "chrome"; to: 0; duration: 260 * root.tempo; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "danger"; to: 0; duration: 120 }
        }
        ParallelAnimation {
            NumberAnimation { target: root; property: "squeeze"; to: 1; duration: 300 * root.tempo; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "veil"; to: 0; duration: 700 * root.tempo; easing.type: Easing.InOutCubic }
        }
    }
    // A wrong password: the digits jolt apart and snap back, flushed red.
    ParallelAnimation {
        id: failure
        SequentialAnimation {
            NumberAnimation { target: root; property: "scatter"; to: 1; duration: 90; easing.type: Easing.OutQuad }
            NumberAnimation { target: root; property: "scatter"; to: 0; duration: 620; easing.type: Easing.OutElastic; easing.amplitude: 1.2; easing.period: 0.4 }
        }
        SequentialAnimation {
            NumberAnimation { target: root; property: "danger"; to: 1; duration: 90 }
            PauseAnimation { duration: 380 }
            NumberAnimation { target: root; property: "danger"; to: 0; duration: 520; easing.type: Easing.OutCubic }
        }
        onStopped: {
            root.scatter = 0;
        }
    }
    // Light passing through: a slow sweep every few seconds while locked, a pulse from the centre for each key, and
    // a quick repeating sweep while the password is checked.
    function sweep(level) {
        if (reduced || calm || frozen || context.busy)
            return;
        pulse.stop();
        waveRadial = false;
        waveLevel = level;
        shimmer.restart();
    }
    Timer {
        interval: 7000
        repeat: true
        running: root.settled && !root.frozen && !root.calm && !root.reduced && !root.context.busy
        onTriggered: root.sweep(0.75)
    }
    SequentialAnimation {
        id: shimmer
        NumberAnimation { target: root; property: "wave"; from: -0.25; to: 1.25; duration: 1800; easing.type: Easing.InOutSine }
        ScriptAction { script: root.waveLevel = 0 }
    }
    SequentialAnimation {
        id: pulse
        ScriptAction {
            script: {
                shimmer.stop();
                root.waveRadial = true;
                root.waveLevel = 1;
            }
        }
        ParallelAnimation {
            NumberAnimation { target: root; property: "wave"; from: 0; to: 0.75; duration: 520; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "waveLevel"; from: 1; to: 0; duration: 520; easing.type: Easing.InQuad }
        }
    }
    NumberAnimation {
        id: checking
        target: root
        property: "wave"
        from: -0.25
        to: 1.25
        duration: 900
        loops: Animation.Infinite
        easing.type: Easing.InOutSine
    }
    NumberAnimation {
        id: waveOff
        target: root
        property: "waveLevel"
        to: 0
        duration: 300
    }
    Component {
        id: glowEffect
        MultiEffect {
            shadowEnabled: true
            shadowColor: Theme.accent
            shadowBlur: 0.9
            shadowOpacity: 1
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 0
            blurMax: 28
            autoPaddingEnabled: true
        }
    }

    LockBackdrop {
        id: backdrop
        property bool waited: false
        anchors.fill: parent
        screenName: root.screenName
        sharp: true
        darken: 0.2
        blur: root.veil
        dim: root.veil
        onReadyChanged: settle.restart()
    }
    // Anywhere on the screen: a click gives the field the keyboard, a move wakes the clock and leans it.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: mouse => {
            root.wake();
            if (root.leaning) {
                root.leanX = (mouse.x - root.clockCx) / root.width * 2;
                root.leanY = (mouse.y - root.clockCy) / root.height * 2;
            }
        }
        onExited: {
            root.leanX = 0;
            root.leanY = 0;
        }
        onPressed: {
            root.wake();
            field.focusField();
        }
    }

    // Dust: faint motes drifting up the screen behind the clock.
    Item {
        anchors.fill: parent
        visible: !root.reduced && !root.calm
        opacity: root.veil
        transform: Translate {
            x: root.leanX * 16
            y: root.leanY * 16
        }
        Repeater {
            model: parent.visible ? 34 : 0
            delegate: Rectangle {
                id: mote
                readonly property real seed: Math.random()
                width: 1.5 + 2.5 * seed
                height: width
                radius: width / 2
                x: Math.random() * root.width
                y: root.height
                opacity: 0
                color: Theme.mix(Theme.accent, Theme.text, Math.random() * 0.5)
                SequentialAnimation {
                    running: true
                    PauseAnimation { duration: Math.random() * 14000 }
                    ParallelAnimation {
                        loops: Animation.Infinite
                        YAnimator { target: mote; from: root.height + 10; to: -10; duration: 22000 + mote.seed * 20000 }
                        SequentialAnimation {
                            OpacityAnimator { target: mote; from: 0; to: 0.2 + 0.4 * mote.seed; duration: 4000 }
                            PauseAnimation { duration: 14000 + mote.seed * 12000 }
                            OpacityAnimator { target: mote; to: 0; duration: 4000 }
                        }
                    }
                }
            }
        }
    }

    // The particles. They glow as one layer; each is placed and flown by its own animators.
    Item {
        id: swarm
        anchors.fill: parent
        layer.enabled: root.glow && root.started
        layer.effect: glowEffect
        transform: [
            Scale {
                origin.x: root.clockCx
                origin.y: root.clockCy
                xScale: root.squeeze
                yScale: root.squeeze
            },
            Translate {
                x: root.leanX * 6
                y: root.leanY * 6
            }
        ]
        Repeater {
            id: particles
            model: root.poolSize
            delegate: Item {
                id: particle
                required property int index
                readonly property real seed: Math.random()
                readonly property real seed2: Math.random()
                readonly property real spin: Math.random() * 2 * Math.PI
                // Where it sits in the clock (0–1 each way), for the passing light.
                property real nx: 0
                property real ny: 0
                property real size: root.dot
                // Showing part of a digit, rather than a spare waiting hidden.
                property bool lit: false
                width: size
                height: size
                x: -size
                y: -size
                opacity: 0
                function place(px, py, alpha, scaled) {
                    motion.stop();
                    x = px;
                    y = py;
                    opacity = alpha;
                    scale = scaled || 1;
                }
                function travel(px, py, alpha, scaled, duration, delay, easeX, easeY) {
                    route({x: px, y: py, opacity: alpha, scale: scaled, duration: duration, easeX: easeX, easeY: easeY}, null, delay);
                }
                // Up to two legs, each {x, y, opacity, scale, duration, easeX, easeY}; the second may start from
                // somewhere else (fromX, fromY), out of sight.
                function route(first, second, delay) {
                    motion.stop();
                    const last = second || first;
                    if (root.reduced) {
                        place(last.x, last.y, last.opacity, last.scale);
                        return;
                    }
                    wait.duration = delay;
                    const legs = [[x1, y1, o1, s1, first], [x2, y2, o2, s2, second || {x: first.x, y: first.y, opacity: first.opacity, scale: first.scale, duration: 0}]];
                    for (const [ax, ay, ao, scaler, leg] of legs) {
                        ax.to = leg.x;
                        ay.to = leg.y;
                        ao.to = leg.opacity;
                        scaler.to = leg.scale;
                        ax.duration = ay.duration = scaler.duration = leg.duration;
                        ao.duration = leg.opacity > 0 ? leg.duration * 0.6 : leg.duration;
                        ax.easing.type = leg.easeX || Easing.Linear;
                        ay.easing.type = leg.easeY || Easing.Linear;
                    }
                    // The second leg starts where the first ended unless it says otherwise.
                    x2.from = second && second.fromX !== undefined ? second.fromX : first.x;
                    y2.from = second && second.fromY !== undefined ? second.fromY : first.y;
                    o2.from = first.opacity;
                    s2.from = first.scale;
                    motion.start();
                }
                SequentialAnimation {
                    id: motion
                    PauseAnimation { id: wait }
                    ParallelAnimation {
                        XAnimator { id: x1; target: particle }
                        YAnimator { id: y1; target: particle }
                        OpacityAnimator { id: o1; target: particle; easing.type: Easing.OutCubic }
                        ScaleAnimator { id: s1; target: particle; easing.type: Easing.OutCubic }
                    }
                    ParallelAnimation {
                        XAnimator { id: x2; target: particle }
                        YAnimator { id: y2; target: particle }
                        OpacityAnimator { id: o2; target: particle; easing.type: Easing.OutCubic }
                        ScaleAnimator { id: s2; target: particle; easing.type: Easing.OutCubic }
                    }
                }
                // Always alive: each particle wanders a little around its place, out of step with the rest.
                readonly property real wander: size * 0.24
                SequentialAnimation {
                    loops: Animation.Infinite
                    running: root.living && particle.lit
                    ParallelAnimation {
                        XAnimator { target: core; to: (Math.random() - 0.5) * 2 * particle.wander; duration: 1400 + Math.random() * 1600; easing.type: Easing.InOutSine }
                        YAnimator { target: core; to: (Math.random() - 0.5) * 2 * particle.wander; duration: 1400 + Math.random() * 1600; easing.type: Easing.InOutSine }
                    }
                    ParallelAnimation {
                        XAnimator { target: core; to: (Math.random() - 0.5) * 2 * particle.wander; duration: 1400 + Math.random() * 1600; easing.type: Easing.InOutSine }
                        YAnimator { target: core; to: (Math.random() - 0.5) * 2 * particle.wander; duration: 1400 + Math.random() * 1600; easing.type: Easing.InOutSine }
                    }
                    ParallelAnimation {
                        XAnimator { target: core; to: 0; duration: 1400 + Math.random() * 1600; easing.type: Easing.InOutSine }
                        YAnimator { target: core; to: 0; duration: 1400 + Math.random() * 1600; easing.type: Easing.InOutSine }
                    }
                }
                Rectangle {
                    id: core
                    // How much the passing light lifts this particle.
                    readonly property real lift: {
                        if (root.waveLevel <= 0)
                            return 0;
                        const d = root.waveRadial ? Math.hypot(particle.nx - 0.5, (particle.ny - 0.5) * root.digitHeight / root.clockWidth) * 2
                                                  : particle.nx * 0.85 + particle.ny * 0.15;
                        return root.waveLevel * Math.max(0, 1 - Math.abs(d - root.wave) / 0.16);
                    }
                    width: particle.width
                    height: particle.height
                    radius: width / 2
                    antialiasing: true
                    color: Theme.mix(Theme.mix(Theme.text, Theme.accent, 0.3 + 0.5 * lift), Theme.danger, root.danger)
                    opacity: Math.min(1, 0.72 + 0.28 * particle.seed2 + 0.4 * lift)
                    scale: 1 + 0.25 * lift
                    transform: Translate {
                        x: root.scatter * Math.cos(particle.spin) * root.step * (1 + 1.5 * particle.seed)
                        y: root.scatter * Math.sin(particle.spin) * root.step * (1 + 1.5 * particle.seed)
                    }
                }
            }
        }
    }

    // Under the clock: the date, then the password field once someone is there.
    Item {
        id: below
        x: root.clockCx
        y: root.clockY + root.digitHeight + 3.5 * root.step
        opacity: root.textIn
        transform: Translate {
            x: root.leanX * 4
            y: root.leanY * 4 + (1 - root.textIn) * 12
        }
        C.Label {
            text: Qt.formatDateTime(clock.date, "dddd · d MMMM").toUpperCase()
            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.95)
            font.pixelSize: Math.max(12, Math.round(root.digitHeight * 0.065))
            font.weight: Font.DemiBold
            font.letterSpacing: 4
            elide: Text.ElideNone
            x: -width / 2
        }
        LockField {
            id: field
            context: root.context
            leftInset: 54
            width: 300
            height: 48
            x: -width / 2
            y: 52 + 10 * root.idleness
            opacity: 1 - root.idleness
            onKeyPressed: root.wake()
            LockAvatar {
                anchors.left: parent.left
                anchors.leftMargin: 7
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                height: 34
                border.width: 1
            }
        }
        LockNote {
            context: root.context
            width: 340
            x: -width / 2
            y: field.y + field.height + 12
            opacity: note !== "" ? 1 - root.idleness : 0
        }
    }

    // Around the edges, as in the classic style.
    LockStatus {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 28
        opacity: root.chrome * (1 - 0.4 * root.idleness)
        transform: Translate { y: -(1 - root.chrome) * 20 }
    }
    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 28
        spacing: Theme.gapL
        opacity: root.chrome * (1 - 0.4 * root.idleness)
        transform: Translate { y: (1 - root.chrome) * 20 }
        LockMedia {
            Layout.preferredWidth: Math.min(360, root.width / 2 - 40)
        }
        Item {
            Layout.fillWidth: true
        }
        LockPower {
            context: root.context
            onReleased: field.focusField()
        }
    }
}
