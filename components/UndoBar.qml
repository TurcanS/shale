import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import "../core"
import "." as C

// Floats 14 px above the bottom of a panel after something was removed: what went, and Undo for a few seconds.
// show(text) opens it (again); undone() fires on Undo, expired() when it goes without one. Resting the pointer on it
// holds it open. Anchor it to the bottom of the page; it ignores the pointer while hidden.
Item {
    id: root
    property string text: ""
    property int timeout: 5000
    property bool open: false
    signal undone()
    signal expired()
    function show(message) {
        text = message;
        open = true;
        timer.restart();
    }
    function close() {
        open = false;
        timer.stop();
    }
    implicitHeight: 44
    visible: reveal > 0
    enabled: open
    z: 5
    property real reveal: open ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.open ? Theme.panelEnter : Theme.panelLeave
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.easeOut
        }
    }
    opacity: reveal
    transform: Translate {
        y: (1 - root.reveal) * Theme.panelRise
    }
    Timer {
        id: timer
        interval: root.timeout
        onTriggered: {
            root.open = false;
            root.expired();
        }
    }
    HoverHandler {
        onHoveredChanged: if (hovered)
            timer.stop();
        else if (root.open)
            timer.restart()
    }
    RectangularShadow {
        anchors.fill: bar
        visible: !Theme.lowPower
        radius: bar.radius
        blur: 24
        offset.y: 10
        color: Qt.rgba(0, 0, 0, 0.45)
    }
    Rectangle {
        id: bar
        anchors.fill: parent
        radius: Theme.radiusCard
        color: Theme.keySelected
        Accessible.role: Accessible.StatusBar
        Accessible.name: root.text
        // Takes the clicks that miss Undo, so they don't reach the rows underneath.
        MouseArea {
            anchors.fill: parent
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 6
            spacing: Theme.gapS
            C.Label {
                text: root.text
                font.pixelSize: 13
                Layout.fillWidth: true
            }
            C.Button {
                text: "Undo"
                flat: true
                labelSize: 13
                implicitHeight: 32
                cornerRadius: 8
                foreground: Theme.accentText
                onClicked: {
                    root.close();
                    root.undone();
                }
            }
        }
    }
}
