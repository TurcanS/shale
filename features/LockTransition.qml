import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import "../core"

// The desktop's way in and out of the lock screen, on one output. Locking: the lock screen's first frame (the plain
// wallpaper, or black for the classic style) closes in from every edge toward the clock, over the windows and the
// bar, and the session lock takes over once it covers the output (ShellState.lockLead). Unlocking: the lock screen's
// last frame, the same picture, opens from the clock outward, so the windows come into view the way the particles
// left. Between the two it sits under the lock screen, unseen, ready for the moment the compositor takes the lock away.
// Lively and Playful switch it off like an old CRT instead: the desktop squeezes into a bright line across the
// middle, the line into a dot, and unlocking powers it back on from the dot (Calm keeps the circle).
PanelWindow {
    id: root
    required property var context
    readonly property bool particles: ShellState.setting("lockStyle", "particles") !== "classic"
    property bool armed: false
    // 0: the cover hides the whole output; 1: the desktop shows in full.
    property real open: 1
    readonly property bool coverReady: !particles || backdrop.ready
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shale-lock-transition"
    WlrLayershell.layer: WlrLayer.Overlay
    mask: Region {}
    visible: armed && !Theme.reduced
    Connections {
        target: ShellState
        function onLockedChanged() {
            if (ShellState.locked && ShellState.lockOwner === "shell") {
                reveal.stop();
                root.open = 1;
                root.armed = true;
                // The picture gets a moment to load, so the fold never shows a placeholder.
                if (root.coverReady)
                    fold.restart();
                else
                    waiting.restart();
            } else if (!ShellState.locked && root.armed) {
                waiting.stop();
                fold.stop();
                reveal.restart();
            }
        }
    }
    // A shell that started while the session was already locked has not folded anything: cover up under the lock
    // screen as soon as the password is accepted, so the reveal still has its first frame.
    Connections {
        target: root.context
        function onUnlockingChanged() {
            if (!root.context.unlocking || root.armed)
                return;
            root.open = 0;
            root.armed = true;
        }
    }
    onCoverReadyChanged: if (coverReady && waiting.running) {
        waiting.stop();
        fold.restart();
    }
    Timer {
        id: waiting
        interval: 160
        onTriggered: fold.restart()
    }
    NumberAnimation {
        id: fold
        target: root
        property: "open"
        to: 0
        duration: Theme.lowPower ? 240 : 460
        easing.type: Easing.InOutCubic
    }
    SequentialAnimation {
        id: reveal
        NumberAnimation {
            target: root
            property: "open"
            to: 1
            duration: Theme.lowPower ? 320 : 620
            easing.type: Easing.OutCubic
        }
        ScriptAction { script: root.armed = false }
    }

    // What the lock screen starts and ends on: the plain wallpaper, or black around the classic screen's fade.
    Item {
        id: cover
        anchors.fill: parent
        visible: false
        LockBackdrop {
            id: backdrop
            // The output's size even while the window is unmapped (and so has none yet): the picture is decoded at
            // this size, the same as the lock screen's.
            width: root.screen ? root.screen.width : 0
            height: root.screen ? root.screen.height : 0
            visible: root.particles
            screenName: root.screen ? root.screen.name : ""
            // Kept decoded at the output's size (about 8 MB at 1080p): a lock can come at any moment, and decoding a
            // large wallpaper from disk can take a second, during which the fold would show the dark placeholder.
            // The lock screen asks for the same picture at the same size, so it gets this copy at once too.
            sharp: root.particles && width > 0
            blur: 0
            dim: 0
        }
        Rectangle {
            anchors.fill: parent
            visible: !root.particles
            color: "#000000"
        }
    }
    // A soft-edged circle around the clock's centre: clear inside, the cover outside. Fully open, its soft edge has
    // passed the farthest corner; fully closed, it has shrunk to nothing.
    Item {
        id: iris
        anchors.fill: parent
        visible: false
        // A full-screen texture: kept only while a fold or reveal can run.
        layer.enabled: root.armed
        readonly property real cx: width / 2
        // The particle clock sits at 40% of the height; the classic one is the 168 px box under the date line,
        // placed as LockClassic places it.
        readonly property real cy: root.particles ? height * 0.4 : Math.round(height * 0.145) + dateLine.height + 6 + 84
        readonly property real reach: Math.hypot(Math.max(cx, width - cx), Math.max(cy, height - cy))
        readonly property real feather: reach * 0.3
        FontMetrics {
            id: dateLine
            font.family: Theme.font
            font.pixelSize: 22
            font.weight: Font.Medium
        }
        readonly property real inner: root.open * (reach + feather) - feather
        readonly property bool crt: !Motion.calm
        Shape {
            anchors.fill: parent
            visible: !iris.crt
            ShapePath {
                strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: iris.cx
                    centerY: iris.cy
                    focalX: iris.cx
                    focalY: iris.cy
                    focalRadius: Math.max(0, iris.inner)
                    centerRadius: Math.max(1, iris.inner + iris.feather)
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: "white" }
                }
                startX: 0
                startY: 0
                PathLine { x: iris.width; y: 0 }
                PathLine { x: iris.width; y: iris.height }
                PathLine { x: 0; y: iris.height }
                PathLine { x: 0; y: 0 }
            }
        }
        // The CRT: the cover everywhere but a band through the middle that the picture squeezes into.
        Item {
            id: crtBand
            anchors.fill: parent
            visible: iris.crt
            readonly property real bandHeight: root.open > 0.25 ? Motion.lerp(2, iris.height, Math.pow((root.open - 0.25) / 0.75, 2)) : 2
            readonly property real bandWidth: root.open > 0.25 ? iris.width : iris.width * Motion.clamp((root.open - 0.06) / 0.19, 0, 1)
            readonly property real bandTop: iris.height / 2 - bandHeight / 2
            readonly property real bandLeft: iris.width / 2 - bandWidth / 2
            Rectangle { width: parent.width; height: crtBand.bandTop; color: "white" }
            Rectangle { y: crtBand.bandTop + crtBand.bandHeight; width: parent.width; height: parent.height - y; color: "white" }
            Rectangle { y: crtBand.bandTop; width: crtBand.bandLeft; height: crtBand.bandHeight; color: "white" }
            Rectangle { x: crtBand.bandLeft + crtBand.bandWidth; y: crtBand.bandTop; width: parent.width - x; height: crtBand.bandHeight; color: "white" }
        }
    }
    MultiEffect {
        anchors.fill: parent
        source: cover
        maskEnabled: true
        maskSource: iris
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1
    }
    // The phosphor line, brightest as the picture gets thin, and the dot it leaves.
    Rectangle {
        visible: root.armed && iris.crt && opacity > 0
        x: crtBand.bandLeft
        y: crtBand.bandTop - 1
        width: crtBand.bandWidth
        height: crtBand.bandHeight + 2
        radius: Math.min(width, height) / 2
        color: Theme.mix(Theme.knob, Theme.accent, 0.25)
        opacity: root.open < 1 && root.open > 0.06 ? Math.max(0, 1 - crtBand.bandHeight / 60) : 0
        layer.enabled: visible
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Theme.accent
            shadowBlur: 1
            shadowOpacity: 0.9
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 0
            blurMax: 24
        }
    }
}
