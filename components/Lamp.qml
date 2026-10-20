import QtQuick
import "../core"

// A small indicator lamp: lit when something is true, a hollow ring when it is not. `breathing` slows it to a pulse.
Item {
    id: lamp
    property bool lit: true
    property color color: Theme.accent
    property bool breathing: false
    property int size: 8
    implicitWidth: size
    implicitHeight: size
    // The glow around a lit lamp; left out in power saver.
    Rectangle {
        anchors.centerIn: parent
        width: lamp.size * 2.4
        height: width
        radius: width / 2
        color: lamp.color
        visible: lamp.lit && !Theme.lowPower
        opacity: 0.22 * lamp.pulse
    }
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: lamp.lit ? lamp.color : "transparent"
        border.width: lamp.lit ? 0 : 1
        border.color: Theme.muted
        opacity: lamp.pulse
    }
    property real pulse: 1
    SequentialAnimation on pulse {
        running: lamp.breathing && lamp.lit && lamp.visible && !Theme.reduced && !Theme.lowPower
        loops: Animation.Infinite
        onRunningChanged: if (!running) lamp.pulse = 1
        NumberAnimation { to: 0.35; duration: 900; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
    }
}
