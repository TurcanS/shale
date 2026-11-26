import QtQuick
import "../core"

// A small key chip in footers and on keyed actions ("Esc", "↵ Open", "L"). Mono for single keys.
Rectangle {
    id: root
    property string text: ""
    property bool mono: false
    property int textSize: 11
    property color textColor: Theme.textSecondary
    implicitWidth: label.implicitWidth + 14
    implicitHeight: label.implicitHeight + 4
    radius: 6
    color: Theme.module
    Accessible.ignored: true
    Label {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.textColor
        font.family: root.mono ? Theme.mono : Theme.font
        font.pixelSize: root.textSize
    }
}
