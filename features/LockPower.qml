import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import "../core"
import "../components" as C

// Shut down: press and hold, like the Power page, so a stray click never powers off.
RowLayout {
    id: root
    required property var context
    readonly property bool active: power.pressed || power.fired
    // The button gives the keyboard back to the password field once let go.
    signal released()
    spacing: Theme.gapL
    C.Label {
        id: powerHint
        property bool shown: false
        text: power.fired ? "Shutting down…" : power.pressed ? "Keep holding…" : "Hold to shut down"
        color: power.fired || power.pressed ? Theme.text : Theme.muted
        font.pixelSize: Theme.small
        font.weight: Font.Medium
        elide: Text.ElideNone
        opacity: shown || power.hovered || power.pressed || power.fired ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.fast } }
        Timer {
            id: hintTimer
            interval: 2200
            onTriggered: powerHint.shown = false
        }
    }
    Connections {
        target: root.context
        function onPowerFailed() {
            power.fired = false;
        }
    }
    AbstractButton {
        id: power
        objectName: "powerButton"
        property real progress: 0
        property bool fired: false
        property double startedAt: 0
        readonly property int delay: 1200
        implicitWidth: 52
        implicitHeight: 52
        hoverEnabled: true
        // The password field keeps the keyboard.
        focusPolicy: Qt.NoFocus
        enabled: !fired && !root.context.unlocking
        Accessible.name: "Shut down"
        Accessible.description: "Press and hold to power off the computer."
        function cancel() {
            holdTimer.stop();
            progress = 0;
        }
        onPressed: {
            startedAt = Date.now();
            holdTimer.restart();
        }
        onReleased: {
            // A quick click explains what the button needs instead of doing nothing silently.
            if (!fired && progress < 1) {
                powerHint.shown = true;
                hintTimer.restart();
            }
            cancel();
            root.released();
        }
        onCanceled: cancel()
        Timer {
            id: holdTimer
            interval: 16
            repeat: true
            onTriggered: {
                if (!power.pressed) {
                    power.cancel();
                    return;
                }
                power.progress = Math.min(1, (Date.now() - power.startedAt) / power.delay);
                if (power.progress >= 1) {
                    stop();
                    power.fired = true;
                    root.context.shutdown();
                }
            }
        }
        background: Rectangle {
            radius: width / 2
            color: power.pressed || power.fired ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.22) : power.hovered ? Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.85) : Qt.rgba(Theme.panel.r, Theme.panel.g, Theme.panel.b, 0.62)
            border.width: 1
            border.color: power.hovered || power.pressed ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.5) : Qt.rgba(1, 1, 1, 0.08)
            Behavior on color { ColorAnimation { duration: Theme.fast } }
        }
        contentItem: Item {
            C.Icon {
                anchors.centerIn: parent
                name: "power"
                size: 20
            }
            // Hold progress drawn as a ring around the button.
            Shape {
                anchors.fill: parent
                visible: power.progress > 0 || power.fired
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: Theme.danger
                    strokeWidth: 2.5
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: power.width / 2
                        centerY: power.height / 2
                        radiusX: power.width / 2 - 1.5
                        radiusY: power.height / 2 - 1.5
                        startAngle: -90
                        sweepAngle: 360 * (power.fired ? 1 : power.progress)
                    }
                }
            }
        }
    }
}
