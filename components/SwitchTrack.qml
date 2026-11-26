import QtQuick
import "../core"

// The 40×22 switch: a key-coloured track that turns accent, with a light knob. The knob clicks over past a detent,
// and the track warms up like a lamp as it turns on. Used by Switch (module headers) and Toggle (rows).
Rectangle {
    id: root
    property bool on: false
    // Hovered, focused or pressed: the "off" track lightens.
    property bool hot: false
    implicitWidth: 40
    implicitHeight: 22
    radius: 11
    color: on ? Theme.accent : hot ? Theme.keyHover : Theme.key
    Behavior on color {
        ColorAnimation {
            duration: Theme.slide
        }
    }
    onOnChanged: if (on) lamp.flash()
    WarmUp {
        id: lamp
        anchors.fill: parent
        radius: parent.radius
        peak: 0.3
    }
    Rectangle {
        x: root.on ? 21 : 3
        y: 3
        width: 16
        height: 16
        radius: 8
        color: Theme.knob
        Detent on x {
            overshoot: 1.4
        }
    }
}
