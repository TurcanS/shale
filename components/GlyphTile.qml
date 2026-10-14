import QtQuick
import "../core"

// The rounded square that carries a row's or tile's glyph, with an optional green status dot.
Rectangle {
    id: root
    property string glyph: ""
    property int size: 32
    property bool selected: false
    property bool positive: false
    property color glyphColor: Theme.text
    implicitWidth: size
    implicitHeight: size
    radius: Theme.radiusSmall + 2
    // Sits on a tile that is itself tinted when selected, so selected steps one shade further.
    color: selected ? Theme.selectionHover : Theme.raised
    Behavior on color { ColorAnimation { duration: Theme.fast } }
    Icon {
        anchors.centerIn: parent
        name: root.glyph
        size: Math.round(root.size / 2) + 1
        color: root.glyphColor
    }
    Rectangle {
        visible: root.positive
        width: 7
        height: 7
        radius: 3.5
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        color: Theme.success
    }
}
