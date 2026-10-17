import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import "../core"

// After an unlock: holds the lock screen's last frame over the desktop and opens it from the clock outward, so the
// windows come into view the way the particles left instead of all at once. It is mapped while the lock screen is
// still up (and hidden by it), so its first frame is ready the moment the compositor takes the lock away.
PanelWindow {
    id: root
    required property var context
    readonly property bool particles: ShellState.setting("lockStyle", "particles") !== "classic"
    property bool armed: false
    // 0: the lock's last frame covers the output; 1: the desktop is fully back.
    property real open: 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shale-unlock"
    WlrLayershell.layer: WlrLayer.Overlay
    mask: Region {}
    visible: armed && !Theme.reduced
    Connections {
        target: root.context
        function onUnlockingChanged() {
            if (!root.context.unlocking)
                return;
            reveal.stop();
            root.open = 0;
            root.armed = true;
            // Should the session stay locked after all, the cover must not linger once it is lifted.
            safety.restart();
        }
    }
    Connections {
        target: ShellState
        function onLockedChanged() {
            if (!ShellState.locked && root.armed)
                reveal.restart();
            else if (ShellState.locked)
                root.armed = false;
        }
    }
    Timer {
        id: safety
        interval: 5000
        onTriggered: if (!reveal.running) root.armed = false
    }
    SequentialAnimation {
        id: reveal
        NumberAnimation {
            target: root
            property: "open"
            from: 0
            to: 1
            duration: Theme.lowPower ? 320 : 620
            easing.type: Easing.OutCubic
        }
        ScriptAction { script: root.armed = false }
    }

    // What the lock screen ends on: the particles' plain wallpaper, or black once the classic screen has faded.
    Item {
        id: cover
        anchors.fill: parent
        visible: false
        LockBackdrop {
            anchors.fill: parent
            visible: root.particles
            screenName: root.screen ? root.screen.name : ""
            sharp: true
            blur: 0
            dim: 0
        }
        Rectangle {
            anchors.fill: parent
            visible: !root.particles
            color: "#000000"
        }
    }
    // A soft-edged circle from the clock's centre: clear inside, the cover outside. It grows until the soft edge has
    // passed the farthest corner.
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
        source: cover
        maskEnabled: true
        maskSource: iris
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1
    }
}
