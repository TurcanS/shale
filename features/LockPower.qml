import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import "../core"
import "../components" as C

// Sleep, restart and shut down as round keys. Restart and shut down need a press and hold, like the Power page,
// so a stray click never ends the session; sleep keeps the lock screen up.
RowLayout {
    id: root
    required property var context
    readonly property bool active: restart.pressed || restart.fired || power.pressed || power.fired
    // The keys give the keyboard back to the password field once let go.
    signal released()
    spacing: 8

    // A round 40 px key. With `hold` it fires only after `delay` ms held down, drawing its progress as a ring.
    component RoundKey: AbstractButton {
        id: key
        property string glyph: ""
        property string holdText: ""
        property string doneText: ""
        property bool danger: false
        property bool hold: false
        property real progress: 0
        property bool fired: false
        property bool explained: false
        property double startedAt: 0
        // True while the screen fades out after a correct password.
        property bool closing: false
        readonly property int delay: 1200
        readonly property string note: fired ? doneText : pressed && hold ? "Keep holding…" : hovered || explained ? holdText : ""
        signal triggered()
        signal letGo()
        implicitWidth: 40
        implicitHeight: 40
        hoverEnabled: true
        // The password field keeps the keyboard.
        focusPolicy: Qt.NoFocus
        enabled: !fired && !closing
        function cancel() {
            holdTimer.stop();
            progress = 0;
        }
        onPressed: {
            if (!hold)
                return;
            startedAt = Date.now();
            holdTimer.restart();
        }
        onReleased: {
            if (!hold) {
                triggered();
            } else if (!fired && progress < 1) {
                // A quick click explains what the key needs instead of doing nothing silently.
                explained = true;
                explainTimer.restart();
            }
            cancel();
            letGo();
        }
        onCanceled: cancel()
        Timer {
            id: explainTimer
            interval: 2200
            onTriggered: key.explained = false
        }
        Timer {
            id: holdTimer
            interval: 16
            repeat: true
            onTriggered: {
                if (!key.pressed) {
                    key.cancel();
                    return;
                }
                key.progress = Math.min(1, (Date.now() - key.startedAt) / key.delay);
                if (key.progress >= 1) {
                    stop();
                    key.fired = true;
                    key.triggered();
                }
            }
        }
        scale: down && !Theme.reduced ? 0.96 : 1
        Behavior on scale { NumberAnimation { duration: Theme.press; easing.type: Easing.OutCubic } }
        background: Rectangle {
            radius: width / 2
            color: key.danger ? Theme.tint(Theme.danger, key.pressed || key.fired ? 0.3 : key.hovered ? 0.24 : 0.18)
                              : key.pressed ? Theme.tint(Theme.keyHover, 0.85)
                              : key.hovered ? Theme.tint(Theme.key, 0.75)
                              : Theme.tint(Theme.caseColor, 0.55)
            Behavior on color { ColorAnimation { duration: Theme.fast } }
        }
        contentItem: Item {
            C.Icon {
                anchors.centerIn: parent
                name: key.glyph
                size: 17
                color: key.danger ? Theme.dangerText : Theme.text
            }
            // Hold progress drawn as a ring around the key.
            Shape {
                anchors.fill: parent
                visible: key.progress > 0 || key.fired
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: key.danger ? Theme.danger : Theme.text
                    strokeWidth: 2
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: key.width / 2
                        centerY: key.height / 2
                        radiusX: key.width / 2 - 1
                        radiusY: key.height / 2 - 1
                        startAngle: -90
                        sweepAngle: 360 * (key.fired ? 1 : key.progress)
                    }
                }
            }
        }
    }

    Connections {
        target: root.context
        function onPowerFailed() {
            restart.fired = false;
            power.fired = false;
        }
    }
    // What the key under the pointer does, or how a hold is going.
    C.Label {
        readonly property string note: power.note || restart.note || sleep.note
        text: note
        color: power.fired || power.pressed || restart.fired || restart.pressed ? Theme.text : Theme.textMuted
        font.pixelSize: 13
        font.weight: Font.Medium
        elide: Text.ElideNone
        opacity: note !== "" ? 1 : 0
        Layout.rightMargin: 4
        Behavior on opacity { NumberAnimation { duration: Theme.fast } }
    }
    RoundKey {
        id: sleep
        closing: root.context.unlocking
        onLetGo: root.released()
        glyph: "moon"
        holdText: "Sleep"
        Accessible.name: "Sleep"
        Accessible.description: "Suspend the computer. It stays locked."
        onTriggered: root.context.suspend()
    }
    RoundKey {
        id: restart
        closing: root.context.unlocking
        onLetGo: root.released()
        glyph: "refresh"
        hold: true
        holdText: "Hold to restart"
        doneText: "Restarting…"
        Accessible.name: "Restart"
        Accessible.description: "Press and hold to restart the computer."
        onTriggered: root.context.reboot()
    }
    RoundKey {
        id: power
        closing: root.context.unlocking
        onLetGo: root.released()
        objectName: "powerButton"
        glyph: "power"
        danger: true
        hold: true
        holdText: "Hold to shut down"
        doneText: "Shutting down…"
        Accessible.name: "Shut down"
        Accessible.description: "Press and hold to power off the computer."
        onTriggered: root.context.shutdown()
    }
}
