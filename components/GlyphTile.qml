import QtQuick
import "../core"

// The rounded square that carries a row's or tile's glyph, with an optional green status dot. A key at rest; when
// selected ("on") it fills with the accent and the glyph takes the dark ink.
Rectangle {
    id: root
    property string glyph: ""
    property int size: 32
    property bool selected: false
    property bool positive: false
    property color glyphColor: selected ? Theme.accentInk : Theme.text
    implicitWidth: size
    implicitHeight: size
    // 9 at 30 px, 11 at 36 px.
    radius: Math.round(size * 0.3)
    color: selected ? Theme.accent : Theme.key
    Behavior on color { ColorAnimation { duration: Theme.fast } }
    Icon {
        anchors.centerIn: parent
        name: root.glyph
        size: Math.round(root.size / 2)
        color: root.glyphColor
    }
    Rectangle {
        visible: root.positive
        width: 8
        height: 8
        radius: 4
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: -1
        color: Theme.success
        border.width: 1.5
        border.color: Theme.caseColor
    }
}
