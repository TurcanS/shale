import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import "../core"
import "../components" as C

// The particle lock screen: the time is drawn in points of light. Locking draws them in from every side of the
// screen to settle into the digits; each minute the digits that change come apart and re-form; typing sends a pulse
// through them; unlocking bursts them outward while the blur clears to the desktop's own wallpaper.
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

    // The clock is a grid of cells about 21 rows tall, fitted to the font's digits; each lit cell holds one particle.
    property int rows: 21
    property int cols: 13
    readonly property real digitHeight: Math.round(Math.min(height * 0.26, width * 0.15))
    readonly property real step: digitHeight / rows
    readonly property real dot: step * 0.64
    readonly property real digitWidth: cols * step
    readonly property real colonWidth: 4 * step
    readonly property real clockWidth: 4 * digitWidth + 2 * step + colonWidth
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
        precision: SystemClock.Minutes
    }
    // Always five characters; a 12-hour time before ten leaves the first one blank.
    readonly property string time: (" " + Qt.formatDateTime(clock.date, clock24h ? "HH:mm" : "h:mm")).slice(-5)
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

    // Each digit's lit cells, read from the interface font once at start.
    property var glyphs: null
    readonly property int perDigit: glyphs ? Math.max(...Object.keys(glyphs).map(key => glyphs[key].length)) : 0
    readonly property int poolSize: glyphs ? 4 * perDigit + colonCells.length : 0
    Canvas {
        id: sampler
        // Eight pixels a cell, with room around the digits so none is cut; drawn under the backdrop, so never seen.
        readonly property int cell: 8
        width: 24 * cell
        height: 32 * cell
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Immediate
        // Its work is done once the digits are read.
        visible: !root.glyphs
        onPaint: {
            const ctx = getContext("2d");
            const sampled = {};
            const across = width / cell, down = height / cell;
            let left = across, right = 0, top = down, bottom = 0;
            for (const digit of "0123456789") {
                ctx.clearRect(0, 0, width, height);
                ctx.fillStyle = "#ffffff";
                // Digits stand about 0.72 em, so this makes them about 21 cells tall.
                ctx.font = "700 " + Math.round(21 * cell / 0.72) + "px \"" + Theme.font + "\"";
                ctx.textAlign = "center";
                ctx.textBaseline = "middle";
                ctx.fillText(digit, width / 2, height / 2);
                const data = ctx.getImageData(0, 0, width, height).data;
                const cells = [];
                for (let r = 0; r < down; r++) {
                    for (let c = 0; c < across; c++) {
                        const x = c * cell + cell / 2, y = r * cell + cell / 2;
                        if (data[(y * width + x) * 4 + 3] > 110) {
                            cells.push([c, r]);
                            left = Math.min(left, c);
                            right = Math.max(right, c);
                            top = Math.min(top, r);
                            bottom = Math.max(bottom, r);
                        }
                    }
                }
                sampled[digit] = cells;
            }
            if (right < left)
                return;
            // The grid is the box around every digit, so each one keeps its place within it.
            for (const digit in sampled)
                sampled[digit] = sampled[digit].map(([c, r]) => [c - left, r - top]);
            root.cols = right - left + 1;
            root.rows = bottom - top + 1;
            root.glyphs = sampled;
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

    // Sends every particle to its place for the current time. "intro" draws them in from far off, "morph" moves
    // only the digits that changed, "glide" moves everything after a resize, "instant" puts them straight there.
    property string shown: ""
    property real shownOffset: 0
    function arrange(mode) {
        const text = time;
        // A blank first digit centres the remaining three.
        const offset = text.charAt(0) === " " ? -(digitWidth + step) / 2 : 0;
        const left = clockCx - clockWidth / 2 + offset;
        const slotX = [left, left + digitWidth + step, left + 2 * digitWidth + step, left + 2 * digitWidth + step + colonWidth,
                       left + 3 * digitWidth + 2 * step + colonWidth];
        const slotStart = [0, perDigit, 2 * perDigit, 2 * perDigit + colonCells.length, 3 * perDigit + colonCells.length];
        const slotSize = [perDigit, perDigit, colonCells.length, perDigit, perDigit];
        const moved = mode !== "morph" || offset !== shownOffset;
        if (mode === "glide" && frozen)
            return;
        const inset = (step - dot) / 2;
        for (let slot = 0; slot < 5; slot++) {
            const ch = text.charAt(slot);
            if (!moved && ch === shown.charAt(slot))
                continue;
            const cells = ch === ":" ? colonCells : glyphs[ch] || [];
            const width = ch === ":" ? colonWidth : digitWidth;
            for (let j = 0; j < slotSize[slot]; j++) {
                const p = particles.itemAt(slotStart[slot] + j);
                if (!p)
                    continue;
                // Spare particles share a lit cell, hidden, ready for a digit with more cells.
                const cell = cells.length ? cells[j % cells.length] : [(width / step - 1) / 2, root.rows / 2];
                const tx = slotX[slot] + cell[0] * step + inset, ty = clockY + cell[1] * step + inset;
                const visible = j < cells.length;
                p.nx = (tx - left) / clockWidth;
                p.ny = (ty - clockY) / digitHeight;
                if (mode === "instant") {
                    p.place(tx, ty, visible ? 1 : 0);
                } else if (mode === "intro") {
                    // From a wide circle around the clock, rushing in out of the screen.
                    const angle = p.seed * 2 * Math.PI, reach = (0.55 + 0.6 * p.seed2) * Math.max(root.width, root.height);
                    p.place(clockCx + Math.cos(angle) * reach, clockCy + Math.sin(angle) * reach, 0, 2.6);
                    p.travel(tx, ty, visible ? 1 : 0, 1, (1050 + 550 * p.seed2) * tempo, (60 + 480 * p.seed) * tempo, Easing.OutCubic, Easing.OutQuart);
                } else if (mode === "glide") {
                    p.travel(tx, ty, visible ? 1 : 0, 1, 450 * tempo, 0, Easing.InOutCubic, Easing.InOutCubic);
                } else {
                    // Arcing paths: the two axes ease differently.
                    p.travel(tx, ty, visible ? 1 : 0, 1, (680 + 420 * p.seed2) * tempo, 220 * p.seed * tempo, Easing.InOutCubic, Easing.OutBack);
                }
            }
        }
        shown = text;
        shownOffset = offset;
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
            const fromX = p.x + dot / 2 - clockCx, fromY = p.y + dot / 2 - clockCy;
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
                width: root.dot
                height: root.dot
                x: -root.dot
                y: -root.dot
                opacity: 0
                function place(px, py, alpha, size) {
                    motion.stop();
                    x = px;
                    y = py;
                    opacity = alpha;
                    scale = size || 1;
                }
                function travel(px, py, alpha, size, duration, delay, easeX, easeY) {
                    motion.stop();
                    if (root.reduced) {
                        place(px, py, alpha, size);
                        return;
                    }
                    wait.duration = delay;
                    moveX.to = px;
                    moveX.duration = duration;
                    moveX.easing.type = easeX;
                    moveY.to = py;
                    moveY.duration = duration;
                    moveY.easing.type = easeY;
                    fade.to = alpha;
                    fade.duration = alpha > 0 ? duration * 0.6 : duration;
                    grow.to = size;
                    grow.duration = duration;
                    motion.start();
                }
                SequentialAnimation {
                    id: motion
                    PauseAnimation { id: wait }
                    ParallelAnimation {
                        XAnimator { id: moveX; target: particle }
                        YAnimator { id: moveY; target: particle }
                        OpacityAnimator { id: fade; target: particle; easing.type: Easing.OutCubic }
                        ScaleAnimator { id: grow; target: particle; easing.type: Easing.OutCubic }
                    }
                }
                Rectangle {
                    // How much the passing light lifts this particle.
                    readonly property real lift: {
                        if (root.waveLevel <= 0)
                            return 0;
                        const d = root.waveRadial ? Math.hypot(particle.nx - 0.5, (particle.ny - 0.5) * root.digitHeight / root.clockWidth) * 2
                                                  : particle.nx * 0.85 + particle.ny * 0.15;
                        return root.waveLevel * Math.max(0, 1 - Math.abs(d - root.wave) / 0.16);
                    }
                    anchors.fill: parent
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
