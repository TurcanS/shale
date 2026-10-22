pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import "../core"
import "../core/station.js" as Station

// The desktop's way in and out of the lock screen, on one output. Locking: the lock screen's first frame (the plain
// wallpaper, or black for the classic style) closes in from every edge toward the clock, over the windows and the
// bar, and the session lock takes over once it covers the output (ShellState.lockLead). Unlocking: the lock screen's
// last frame, the same picture, opens from the clock outward, so the windows come into view the way the particles
// left. Between the two it sits under the lock screen, unseen, ready for the moment the compositor takes the lock away.
// The station style is a core sample instead: the picture closes from both sides onto the Front (now, where the
// drum's stylus stands) and splits open along it.
PanelWindow {
    id: root
    required property var context
    readonly property bool particles: ShellState.setting("lockStyle", "particles") !== "classic"
    readonly property bool split: ShellState.setting("lockStyle", "particles") === "station"
    // Where the Front stands, fixed when the fold or the reveal starts so the seam does not creep while it moves.
    property real front: width / 2
    function placeFront() {
        const now = Date.now();
        const day = new Date(now);
        front = Station.front(now, new Date(day.getFullYear(), day.getMonth(), day.getDate()).getTime(),
                              new Date(day.getFullYear(), day.getMonth(), day.getDate() + 1).getTime(), backdrop.width || width);
    }
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
                root.placeFront();
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
                root.placeFront();
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
            root.placeFront();
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
        layer.enabled: true
        readonly property real cx: width / 2
        readonly property real cy: height * (root.particles ? 0.4 : 0.47)
        readonly property real reach: Math.hypot(Math.max(cx, width - cx), Math.max(cy, height - cy))
        readonly property real feather: reach * 0.3
        readonly property real inner: root.open * (reach + feather) - feather
        Shape {
            anchors.fill: parent
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
    }
    MultiEffect {
        anchors.fill: parent
        visible: !root.split
        source: cover
        maskEnabled: true
        maskSource: iris
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1
    }
    // The core sample: the picture in two pieces, cut at the Front, each pushed out to its own side. A thin accent
    // seam marks the cut while it is close.
    Repeater {
        model: root.split ? 2 : 0
        delegate: Item {
            id: piece
            required property int index
            readonly property bool first: index === 0
            readonly property real side: first ? root.front : root.width - root.front
            x: (first ? 0 : root.front) + (first ? -1 : 1) * root.open * (side + 4)
            width: side
            height: root.height
            ShaderEffectSource {
                anchors.fill: parent
                sourceItem: cover
                sourceRect: Qt.rect(piece.first ? 0 : root.front, 0, piece.side, root.height)
            }
            Rectangle {
                x: piece.first ? parent.width - width : 0
                width: 2
                height: parent.height
                color: Theme.accent
                opacity: 0.8 * (1 - root.open)
            }
        }
    }
}
